import Foundation

public struct RemoteFile: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case file, directory, symlink, other }
    public var id: String { path }
    public let name: String
    public let path: String
    public let kind: Kind
    public let size: Int64
    public let modified: Date

    public var isDirectory: Bool { kind == .directory }
    public var isHidden: Bool { name.hasPrefix(".") }
}

public enum RemoteListing {
    /// Parses lines of `type|size|mtime|name` (name may contain `|`).
    public static func parse(_ output: String) -> (cwd: String, files: [RemoteFile]) {
        var lines = output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard !lines.isEmpty else { return ("/", []) }
        let cwd = lines.removeFirst()
        let files: [RemoteFile] = lines.compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4, let size = Int64(parts[1]), let mtime = TimeInterval(parts[2]) else { return nil }
            var name = String(parts[3])
            if name.hasPrefix("./") { name.removeFirst(2) }
            let t = parts[0].lowercased()
            let kind: RemoteFile.Kind =
                t.contains("directory") ? .directory :
                t.contains("symbolic") ? .symlink :
                t.contains("regular") ? .file : .other
            let path = cwd == "/" ? "/\(name)" : "\(cwd)/\(name)"
            return RemoteFile(name: name, path: path, kind: kind, size: size, modified: Date(timeIntervalSince1970: mtime))
        }
        return (cwd, files)
    }
}

public func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
