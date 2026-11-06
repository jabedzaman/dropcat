import Foundation

/// Persists the user's machines (database, with the old JSON file as a one-time migration source).
public struct MachineStore: Sendable {
    public let url: URL
    public let db: StateDB?

    /// With a `db`, machines live in the database; the JSON file is only read once as a migration source.
    public init(url: URL = MachineStore.defaultURL, db: StateDB? = nil) { self.url = url; self.db = db }

    public static var defaultURL: URL {
        let dir = AppPaths.supportDirectory
        return dir.appendingPathComponent("machines.json")
    }

    /// Only machines the user added (or explicitly imported). ssh_config is never merged in automatically.
    public func load() -> [Machine] {
        let saved: [Machine] = db?.getJSON("app", "machines")
            ?? (try? JSONDecoder().decode([Machine].self, from: Data(contentsOf: url))) ?? []
        // Machines auto-merged from ssh_config by older versions carry `.sshConfig`; imports are stored as `.manual`.
        return saved.filter { $0.source == .manual }
    }

    public func save(_ machines: [Machine]) throws {
        if let db { db.setJSON("app", "machines", machines); return }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(machines).write(to: url, options: .atomic)
    }
}
