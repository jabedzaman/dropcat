import SwiftUI
import DropCatCore

enum SidebarItem: Hashable { case machine(UUID), place(String) }

@Observable @MainActor
final class AppModel {
    var machines: [Machine] = []
    var selectedID: Machine.ID?
    var sidebarSelection: SidebarItem?
    var status: [Machine.ID: ConnectionStatus] = [:]
    /// Files currently being fetched for Quick Look (shown dimmed with a spinner, not in the transfer bar).
    var previewing = Set<RemoteFile.ID>()
    var alertError: String?
    var testResult: (name: String, status: ConnectionStatus)?
    private var pollTask: Task<Void, Never>?
    private(set) var bookmarks: [Machine.ID: [String]] = [:]
    var transfers: [TransferItem] = []
    private let db = StateDB.shared
    private var store: MachineStore { MachineStore(db: db) }
    private var browsers: [Machine.ID: BrowserModel] = [:]

    init() {
        reload()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkAll()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func statusOf(_ m: Machine) -> ConnectionStatus { status[m.id] ?? .unknown }

    func checkAll() async {
        await withTaskGroup(of: Void.self) { g in
            for m in machines { g.addTask { await self.check(m) } }
        }
    }

    @discardableResult
    func check(_ m: Machine) async -> ConnectionStatus {
        status[m.id] = .checking
        let r = await SSHClient(m).check()
        status[m.id] = r
        return r
    }

    /// Manual "Test Connection": also surfaces the result in an alert.
    func test(_ m: Machine) {
        Task { let r = await check(m); testResult = (m.name, r) }
    }

    var selected: Machine? { machines.first { $0.id == selectedID } }

    func reload() {
        machines = store.load()
        migrateBookmarksIfNeeded()
        bookmarks = Dictionary(uniqueKeysWithValues: machines.compactMap { m in
            db?.getJSON("machine:\(m.id.uuidString)", "bookmarks", as: [String].self).map { (m.id, $0) }
        })
        if selectedID == nil {
            let saved: UUID? = db?.getJSON("app", "selectedMachine")
            selectedID = machines.first(where: { $0.id == saved })?.id ?? machines.first?.id
        }
        if sidebarSelection == nil, let id = selectedID { sidebarSelection = .machine(id) }
    }

    func select(_ item: SidebarItem?) {
        guard let item else { return }
        sidebarSelection = item
        switch item {
        case .machine(let id): selectedID = id; db?.setJSON("app", "selectedMachine", id)
        case .place(let path):
            guard let m = selected else { return }
            Task { await browser(for: m).open(path == "~" ? nil : path) }
        }
    }

    func places(for m: Machine) -> [String] { ["~", "/"] + (bookmarks[m.id] ?? []) }

    func addBookmark(_ path: String, on m: Machine) {
        guard !places(for: m).contains(path) else { return }
        bookmarks[m.id, default: []].append(path); saveBookmarks(m)
    }

    func removeBookmark(_ path: String, on m: Machine) {
        bookmarks[m.id]?.removeAll { $0 == path }; saveBookmarks(m)
    }

    private func saveBookmarks(_ m: Machine) {
        db?.setJSON("machine:\(m.id.uuidString)", "bookmarks", bookmarks[m.id] ?? [])
    }

    /// One-time import of the old UserDefaults bookmarks (keyed by machine name).
    private func migrateBookmarksIfNeeded() {
        guard let db, db.get("app", "migrated.bookmarks") == nil else { return }
        defer { db.set("app", "migrated.bookmarks", "1") }
        guard let data = UserDefaults.standard.data(forKey: "bookmarks"),
              let old = try? JSONDecoder().decode([String: [String]].self, from: data) else { return }
        for m in machines { if let b = old[m.name] { db.setJSON("machine:\(m.id.uuidString)", "bookmarks", b) } }
    }

    func browser(for m: Machine) -> BrowserModel {
        if let b = browsers[m.id] { return b }
        let b = BrowserModel(machine: m, db: db); browsers[m.id] = b; return b
    }

    /// Adds hosts picked from ~/.ssh/config as regular, independently managed machines (skips duplicates).
    func importHosts(_ hosts: [Machine]) {
        for h in hosts where !machines.contains(where: { $0.name == h.name && $0.host == h.host }) {
            var m = h; m.id = UUID(); m.source = .manual
            machines.append(m)
        }
        try? store.save(machines)
        if selectedID == nil { select(machines.first.map { .machine($0.id) }) }
        Task { await checkAll() }
    }

    func toggleFavorite(_ m: Machine) {
        guard let i = machines.firstIndex(of: m) else { return }
        machines[i].isFavorite.toggle()
        try? store.save(machines)
    }

    func add(_ m: Machine) {
        machines.append(m); selectedID = m.id; sidebarSelection = .machine(m.id)
        try? store.save(machines)
    }

    func remove(_ m: Machine) {
        machines.removeAll { $0.id == m.id }
        try? store.save(machines)
    }

    // MARK: Transfers

    func upload(_ urls: [URL], to remoteDir: String, on m: Machine, then refresh: @escaping @MainActor () -> Void) {
        for url in urls {
            start(TransferItem(name: url.lastPathComponent, machine: m.name, isUpload: true),
                  .upload(local: url, remotePath: remoteDir), on: m, then: refresh)
        }
    }

    func download(_ file: RemoteFile, on m: Machine, to dir: URL) {
        start(TransferItem(name: file.name, machine: m.name, isUpload: false),
              .download(remotePath: file.path, local: dir), on: m, then: {})
    }

    /// Downloads a file to a temp cache (skipped if already cached) and hands back the local URL for Quick Look.
    func fetchForPreview(_ file: RemoteFile, on m: Machine, completion: @escaping @MainActor (URL) -> Void) {
        let key = "\(abs(file.path.hashValue))-\(Int(file.modified.timeIntervalSince1970))-\(file.size)"
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dropcat-preview/\(m.id.uuidString)/\(key)", isDirectory: true)
        let local = dir.appendingPathComponent(file.name)
        if FileManager.default.fileExists(atPath: local.path) { completion(local); return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard previewing.insert(file.id).inserted else { return }
        Task {
            var failure: String?
            for await ev in Transfer.run(.download(remotePath: file.path, local: dir), on: m) {
                if case .failed(let msg) = ev { failure = msg }
            }
            previewing.remove(file.id)
            if let failure { alertError = "\(file.name): \(failure)" } else { completion(local) }
        }
    }

    /// Cross button: cancels a running transfer, or just removes a finished/failed one.
    func dismiss(_ item: TransferItem) {
        item.cancel()
        transfers.removeAll { $0.id == item.id }
    }

    func clearFinishedTransfers() {
        transfers.removeAll { $0.state != .running }
    }

    private func start(_ item: TransferItem, _ dir: TransferDirection, on m: Machine, then: @escaping @MainActor () -> Void) {
        transfers.insert(item, at: 0)
        item.task = Task {
            for await ev in Transfer.run(dir, on: m) {
                switch ev {
                case .progress(let p): item.progress = p.fraction; item.detail = "\(p.speed) · \(p.eta)"
                case .finished: item.state = .done; item.progress = 1; item.detail = "Done"; then()
                case .failed(let msg): item.state = .failed; item.detail = msg
                }
            }
            if Task.isCancelled, item.state == .running { item.state = .failed; item.detail = "Cancelled" }
        }
    }
}

@Observable @MainActor
final class TransferItem: Identifiable {
    enum State { case running, done, failed }
    let id = UUID()
    let name: String
    let machine: String
    let isUpload: Bool
    var progress = 0.0
    var detail = "Starting…"
    var state = State.running
    var task: Task<Void, Never>?
    init(name: String, machine: String, isUpload: Bool) { self.name = name; self.machine = machine; self.isUpload = isUpload }
    func cancel() { task?.cancel() }
}
