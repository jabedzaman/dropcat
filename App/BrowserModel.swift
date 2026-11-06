import SwiftUI
import SSHDropCore
import UniformTypeIdentifiers

struct TreeRow: Identifiable {
    let file: RemoteFile
    let depth: Int
    var id: String { file.id }

    // Sortable columns.
    var name: String { file.name }
    var modified: Date { file.modified }
    var sizeSort: Int64 { file.isDirectory ? -1 : file.size }
    var kind: String { file.kindDescription }
}

extension RemoteFile {
    var kindDescription: String {
        switch kind {
        case .directory: return "Folder"
        case .symlink: return "Alias"
        default:
            let ext = (name as NSString).pathExtension
            guard !ext.isEmpty, let d = UTType(filenameExtension: ext)?.localizedDescription else { return "Document" }
            return d.prefix(1).uppercased() + d.dropFirst()
        }
    }
}

/// A delete that needs the user's OK because it would remove non-empty folders.
struct DeleteRequest {
    let files: [RemoteFile]
    let nonEmpty: [(name: String, count: Int)]

    var title: String { files.count == 1 ? "Delete “\(files[0].name)”?" : "Delete \(files.count) items?" }
    var message: String {
        let noun = { (n: Int) in n == 1 ? "1 item" : "\(n) items" }
        let detail = nonEmpty.count == 1
            ? "“\(nonEmpty[0].name)” contains \(noun(nonEmpty[0].count))."
            : nonEmpty.map { "“\($0.name)” (\(noun($0.count)))" }.joined(separator: ", ") + " aren't empty."
        return "\(detail) This permanently deletes everything inside, and it can't be undone."
    }
}

enum ViewMode: String, Codable, Hashable { case icons, list }

/// Persisted form of the table sort order.
struct SortPref: Codable {
    var column: String
    var ascending: Bool

    init(column: String, ascending: Bool) { self.column = column; self.ascending = ascending }

    init?(_ c: KeyPathComparator<TreeRow>?) {
        guard let c else { return nil }
        let name: String
        switch c.keyPath {
        case \TreeRow.name: name = "name"
        case \TreeRow.modified: name = "modified"
        case \TreeRow.sizeSort: name = "size"
        case \TreeRow.kind: name = "kind"
        default: return nil
        }
        self.init(column: name, ascending: c.order == .forward)
    }

    var comparators: [KeyPathComparator<TreeRow>] {
        let o: SortOrder = ascending ? .forward : .reverse
        switch column {
        case "modified": return [KeyPathComparator(\TreeRow.modified, order: o)]
        case "size": return [KeyPathComparator(\TreeRow.sizeSort, order: o)]
        case "kind": return [KeyPathComparator(\TreeRow.kind, comparator: .localizedStandard, order: o)]
        default: return [KeyPathComparator(\TreeRow.name, comparator: .localizedStandard, order: o)]
        }
    }
}

@Observable @MainActor
final class BrowserModel {
    let machine: Machine
    var cwd = ""
    var files: [RemoteFile] = []
    var loading = false
    var error: String?
    var showHidden = false { didSet { save("showHidden", showHidden) } }
    var viewMode = ViewMode.list { didSet { save("viewMode", viewMode) } }
    var query = ""
    var selection = Set<RemoteFile.ID>()
    var deleteRequest: DeleteRequest?
    private var typeBuffer = ""
    private var typeTime = Date.distantPast
    var renamingID: RemoteFile.ID?
    var renameText = ""
    var sortOrder = [KeyPathComparator(\TreeRow.name, comparator: .localizedStandard)] {
        didSet { if let p = SortPref(sortOrder.first) { save("sort", p) } }
    }
    private let db: StateDB?
    private var scope: String { "machine:\(machine.id.uuidString)" }
    private func save<T: Encodable>(_ key: String, _ value: T) { db?.setJSON(scope, key, value) }
    private(set) var expanded = Set<String>()
    private var children: [String: [RemoteFile]] = [:]
    private(set) var loadingDirs = Set<String>()
    private var back: [String] = []
    private var forward: [String] = []

    init(machine: Machine, db: StateDB? = nil) {
        self.machine = machine
        self.db = db
        // Assigning in init doesn't fire didSet, so loading doesn't write back.
        let scope = "machine:\(machine.id.uuidString)"
        if let db {
            showHidden = db.getJSON(scope, "showHidden") ?? false
            viewMode = db.getJSON(scope, "viewMode") ?? .list
            if let p: SortPref = db.getJSON(scope, "sort") { sortOrder = p.comparators }
        }
    }

    /// First load: reopen the last folder, falling back to home if it's gone.
    func start() async {
        guard cwd.isEmpty else { return }
        if let last: String = db?.getJSON(scope, "lastPath") {
            await open(last)
            if error == nil { return }
        }
        await open(nil)
    }

    var folderName: String {
        cwd.isEmpty ? machine.name : cwd == "/" ? "/" : (cwd as NSString).lastPathComponent
    }

    private func sorted(_ list: [RemoteFile]) -> [RemoteFile] {
        list.filter { showHidden || !$0.isHidden }
            .map { TreeRow(file: $0, depth: 0) }
            .sorted(using: sortOrder)
            .map(\.file)
    }

    /// Flat rows for the table. In list mode, expanded folders are followed by their children.
    var rows: [TreeRow] {
        var out: [TreeRow] = []
        func walk(_ list: [RemoteFile], _ depth: Int) {
            for f in sorted(list) {
                out.append(TreeRow(file: f, depth: depth))
                if viewMode == .list, f.isDirectory, expanded.contains(f.path), let kids = children[f.path] { walk(kids, depth + 1) }
            }
        }
        walk(files, 0)
        guard !query.isEmpty else { return out }
        return out.filter { $0.file.name.localizedCaseInsensitiveContains(query) }
    }

    func file(id: RemoteFile.ID) -> RemoteFile? {
        files.first { $0.id == id } ?? children.values.lazy.compactMap { $0.first { $0.id == id } }.first
    }

    var canBack: Bool { !back.isEmpty }
    var canForward: Bool { !forward.isEmpty }
    func isExpanded(_ f: RemoteFile) -> Bool { expanded.contains(f.path) }

    func toggle(_ f: RemoteFile) async {
        guard f.isDirectory else { return }
        if expanded.contains(f.path) { expanded.remove(f.path); return }
        if children[f.path] == nil {
            loadingDirs.insert(f.path)
            defer { loadingDirs.remove(f.path) }
            do { children[f.path] = try await SSHClient(machine).list(f.path).files }
            catch { self.error = error.localizedDescription; return }
        }
        expanded.insert(f.path)
    }

    func open(_ path: String?, recordHistory: Bool = true) async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let r = try await SSHClient(machine).list(path)
            if recordHistory, !cwd.isEmpty, cwd != r.cwd { back.append(cwd); forward.removeAll() }
            if r.cwd != cwd || recordHistory { expanded.removeAll() }
            children.removeAll()
            cwd = r.cwd; files = r.files
            save("lastPath", r.cwd)
            await reloadExpanded()
        } catch { self.error = error.localizedDescription }
    }

    /// After a refresh, re-fetch folders that were open so the tree keeps its shape.
    private func reloadExpanded() async {
        for path in expanded where children[path] == nil {
            if let kids = try? await SSHClient(machine).list(path).files { children[path] = kids }
            else { expanded.remove(path) }
        }
    }

    /// Finder-style unique name: "untitled folder", "untitled folder 2", …
    private func uniqueName(_ base: String, among names: Set<String>) -> String {
        guard names.contains(base) else { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    private func join(_ dir: String, _ name: String) -> String { dir == "/" ? "/\(name)" : "\(dir)/\(name)" }

    /// Creates "untitled folder" in the current directory and returns its id so the UI can start renaming.
    func newUntitledFolder() async throws -> RemoteFile.ID {
        let name = uniqueName("untitled folder", among: Set(files.map(\.name)))
        let path = join(cwd, name)
        try await SSHClient(machine).makeDirectory(path)
        await refresh()
        return path
    }

    /// Deletes immediately unless a folder isn't empty, in which case `deleteRequest` is set for confirmation.
    func requestDelete(_ ids: Set<RemoteFile.ID>) async throws {
        let targets = ids.compactMap { file(id: $0) }
        guard !targets.isEmpty else { return }
        guard !targets.contains(where: { $0.path == "/" }) else { throw CommandError(message: "Refusing to delete “/”.") }
        let client = SSHClient(machine)
        var nonEmpty: [(String, Int)] = []
        for f in targets where f.isDirectory {
            let n = try await client.itemCount(inDirectory: f.path)
            if n > 0 { nonEmpty.append((f.name, n)) }
        }
        if nonEmpty.isEmpty { try await performDelete(targets) }
        else { deleteRequest = DeleteRequest(files: targets, nonEmpty: nonEmpty) }
    }

    func performDelete(_ targets: [RemoteFile]) async throws {
        deleteRequest = nil
        let client = SSHClient(machine)
        defer { Task { await refresh() } }
        for f in targets { try await client.delete(f.path) }
        selection.subtract(targets.map(\.id))
    }

    /// Finder-style type-to-select: typing quickly builds a prefix; selects the first match.
    func typeSelect(_ chars: String) {
        let now = Date()
        if now.timeIntervalSince(typeTime) > 1 { typeBuffer = "" }
        typeTime = now
        typeBuffer += chars.lowercased()
        if let hit = rows.first(where: { $0.file.name.lowercased().hasPrefix(typeBuffer) }) { selection = [hit.id] }
    }

    func moveSelection(by delta: Int) {
        let r = rows
        guard !r.isEmpty else { return }
        let idx = selection.first.flatMap { id in r.firstIndex { $0.id == id } }
        let next = idx.map { min(max($0 + delta, 0), r.count - 1) } ?? (delta > 0 ? 0 : r.count - 1)
        selection = [r[next].id]
    }

    func beginRename(_ id: RemoteFile.ID) {
        guard let f = file(id: id) else { return }
        renamingID = id; renameText = f.name
    }

    func cancelRename() { renamingID = nil }

    /// Applies the rename. No-op if unchanged. Returns the new id (path).
    @discardableResult
    func commitRename() async throws -> RemoteFile.ID? {
        guard let id = renamingID, let f = file(id: id) else { renamingID = nil; return nil }
        renamingID = nil   // clear first so blur + Return can't commit twice
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != f.name else { return id }
        guard !name.contains("/") else { throw CommandError(message: "Names can't contain “/”.") }
        let parent = (f.path as NSString).deletingLastPathComponent
        let siblings = parent == cwd ? files : (children[parent] ?? [])
        guard !siblings.contains(where: { $0.name == name }) else {
            throw CommandError(message: "“\(name)” already exists here.")
        }
        let dest = join(parent, name)
        try await SSHClient(machine).rename(f.path, to: dest)
        await refresh()
        return dest
    }

    func refresh() async { await open(cwd.isEmpty ? nil : cwd, recordHistory: false) }
    func goBack() async { guard let p = back.popLast() else { return }; forward.append(cwd); await open(p, recordHistory: false) }
    func goForward() async { guard let p = forward.popLast() else { return }; back.append(cwd); await open(p, recordHistory: false) }
    func goUp() async { await open((cwd as NSString).deletingLastPathComponent) }
}
