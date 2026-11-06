import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Small SQLite-backed store for app state: `(scope, key) -> JSON string`.
/// Scopes: `"app"` for globals, `"machine:<uuid>"` for per-machine state.
public final class StateDB: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSLock()

    public struct DBError: Error, LocalizedError { public let errorDescription: String? }

    public static var defaultURL: URL {
        let dir = AppPaths.supportDirectory
        return dir.appendingPathComponent("state.sqlite")
    }

    public static let shared: StateDB? = try? StateDB(path: defaultURL.path)

    /// Pass `":memory:"` for tests.
    public init(path: String) throws {
        guard sqlite3_open(path, &handle) == SQLITE_OK else {
            throw DBError(errorDescription: "Can't open database at \(path)")
        }
        try exec("PRAGMA journal_mode=WAL")
        try exec("""
        CREATE TABLE IF NOT EXISTS kv (
            scope TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL,
            PRIMARY KEY (scope, key)
        )
        """)
    }

    deinit { sqlite3_close(handle) }

    // MARK: Raw strings

    public func get(_ scope: String, _ key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT value FROM kv WHERE scope = ? AND key = ?", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, scope, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, key, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: c)
    }

    public func set(_ scope: String, _ key: String, _ value: String) {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        let sql = "INSERT INTO kv (scope, key, value) VALUES (?, ?, ?) ON CONFLICT(scope, key) DO UPDATE SET value = excluded.value"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, scope, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, key, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, value, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    public func delete(_ scope: String, _ key: String) {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "DELETE FROM kv WHERE scope = ? AND key = ?", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, scope, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, key, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    // MARK: JSON values

    public func getJSON<T: Decodable>(_ scope: String, _ key: String, as type: T.Type = T.self) -> T? {
        guard let s = get(scope, key), let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    public func setJSON<T: Encodable>(_ scope: String, _ key: String, _ value: T) {
        guard let d = try? JSONEncoder().encode(value) else { return }
        set(scope, key, String(decoding: d, as: UTF8.self))
    }

    private func exec(_ sql: String) throws {
        lock.lock(); defer { lock.unlock() }
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "sqlite error"
            sqlite3_free(err)
            throw DBError(errorDescription: msg)
        }
    }
}
