import Foundation

public struct Machine: Identifiable, Codable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable { case manual, sshConfig }

    public var id: UUID
    public var name: String
    public var host: String
    public var user: String?
    public var port: Int?
    public var identityFile: String?
    public var proxyJump: String?
    public var group: String?
    public var isFavorite: Bool
    public var source: Source

    public init(
        id: UUID = UUID(), name: String, host: String, user: String? = nil, port: Int? = nil,
        identityFile: String? = nil, proxyJump: String? = nil, group: String? = nil,
        isFavorite: Bool = false, source: Source = .manual
    ) {
        self.id = id; self.name = name; self.host = host; self.user = user; self.port = port
        self.identityFile = identityFile; self.proxyJump = proxyJump; self.group = group
        self.isFavorite = isFavorite; self.source = source
    }

    /// `user@host` or `host`.
    public var target: String { user.map { "\($0)@\(host)" } ?? host }

    /// Options shared by ssh/scp invocations. Multiplexed so repeated calls skip re-auth.
    public func connectionOptions(controlDir: URL = Machine.defaultControlDir) -> [String] {
        var o = [
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(controlDir.path)/%C",
            "-o", "ControlPersist=600",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
        ]
        if let identityFile, !identityFile.isEmpty { o += ["-i", (identityFile as NSString).expandingTildeInPath] }
        if let proxyJump, !proxyJump.isEmpty { o += ["-J", proxyJump] }
        return o
    }

    public static var defaultControlDir: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dropcat/cm")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
