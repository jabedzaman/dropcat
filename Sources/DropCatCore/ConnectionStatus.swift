import Foundation

public enum ConnectionStatus: Equatable, Sendable {
    case unknown
    case checking
    case online(ms: Int)
    /// Host answered but login was refused (bad/missing key).
    case authFailed(String)
    case offline(String)

    /// Classifies the result of `ssh host echo ok`.
    public static func classify(exit: Int32, stderr: String, ms: Int) -> ConnectionStatus {
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if exit == 0 { return .online(ms: ms) }
        let lower = err.lowercased()
        // git hosts (github, azure) authenticate fine but refuse a shell with exit != 0.
        if lower.contains("successfully authenticated") || lower.contains("you've successfully") { return .online(ms: ms) }
        if lower.contains("permission denied") { return .authFailed(err) }
        return .offline(err.isEmpty ? "Exit status \(exit)" : err)
    }

    public var summary: String {
        switch self {
        case .unknown: "Not checked"
        case .checking: "Checking…"
        case .online(let ms): "Connected · \(ms) ms"
        case .authFailed(let m): "Reachable, login refused: \(m)"
        case .offline(let m): "Unreachable: \(m)"
        }
    }
}

extension SSHClient {
    public func check() async -> ConnectionStatus {
        let start = ContinuousClock.now
        do {
            let r = try await run("echo ok")
            let d = ContinuousClock.now - start
            let ms = Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000)
            return .classify(exit: r.status, stderr: r.stderr, ms: ms)
        } catch { return .offline(error.localizedDescription) }
    }
}
