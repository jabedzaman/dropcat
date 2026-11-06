import Foundation

public struct SSHClient: Sendable {
    public let machine: Machine
    public init(_ machine: Machine) { self.machine = machine }

    private var sshArgs: [String] {
        var a = machine.connectionOptions()
        if let port = machine.port { a += ["-p", String(port)] }
        return a + [machine.target]
    }

    public func run(_ command: String) async throws -> ProcessResult {
        try await ProcessRunner.run("/usr/bin/ssh", sshArgs + [command])
    }

    /// Returns nil on success, else the error message.
    public func testConnection() async -> String? {
        do {
            let r = try await run("echo ok")
            return r.status == 0 ? nil : r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch { return error.localizedDescription }
    }

    /// Lists a remote directory. Pass `nil` for the home directory.
    public func list(_ path: String?) async throws -> (cwd: String, files: [RemoteFile]) {
        // BSD stat (-f) and GNU stat (-c) differ; probe once and use the right format.
        // "~" and "~/x" are expanded by `cd` itself, since the quoted path would stay literal.
        let cd: String
        switch path {
        case nil, "~": cd = "cd"
        case let p? where p.hasPrefix("~/"): cd = "cd && cd -- \(shellQuote(String(p.dropFirst(2))))"
        case let p?: cd = "cd -- \(shellQuote(p))"
        }
        let script = """
        \(cd) && pwd && \
        if stat --version >/dev/null 2>&1; then F="-L -c %F|%s|%Y|%n"; else F="-L -f %HT|%z|%m|%N"; fi; \
        find . -mindepth 1 -maxdepth 1 -exec stat $F {} + 2>/dev/null; true
        """
        // Run under sh so word-splitting works regardless of the remote login shell (zsh/fish).
        let r = try await run("sh -c \(shellQuote(script))")
        guard r.status == 0 else { throw CommandError(message: r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return RemoteListing.parse(r.stdout)
    }

    public func makeDirectory(_ path: String) async throws {
        let r = try await run("mkdir -p -- \(shellQuote(path))")
        if r.status != 0 { throw CommandError(message: r.stderr) }
    }

    public func rename(_ from: String, to: String) async throws {
        let r = try await run("mv -n -- \(shellQuote(from)) \(shellQuote(to))")
        if r.status != 0 { throw CommandError(message: r.stderr) }
    }

    /// Number of entries (including hidden) directly inside a directory.
    public func itemCount(inDirectory path: String) async throws -> Int {
        let r = try await run("sh -c \(shellQuote("ls -A -- \(shellQuote(path)) | wc -l"))")
        guard r.status == 0 else { throw CommandError(message: r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return Int(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    public func delete(_ path: String) async throws {
        let r = try await run("rm -rf -- \(shellQuote(path))")
        if r.status != 0 { throw CommandError(message: r.stderr) }
    }
}
