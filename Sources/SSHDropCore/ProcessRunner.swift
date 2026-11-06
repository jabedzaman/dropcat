import Foundation

public struct ProcessResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let status: Int32
}

public struct CommandError: Error, LocalizedError, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum ProcessRunner {
    /// Runs a process to completion, capturing stdout/stderr.
    public static func run(_ executable: String, _ args: [String]) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: executable)
            p.arguments = args
            let out = Pipe(), err = Pipe()
            p.standardOutput = out; p.standardError = err
            p.standardInput = FileHandle.nullDevice

            // Drain both pipes concurrently so a full buffer can't deadlock the child.
            let outData = LockedData(), errData = LockedData()
            out.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData; if !d.isEmpty { outData.append(d) }
            }
            err.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData; if !d.isEmpty { errData.append(d) }
            }
            p.terminationHandler = { proc in
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                outData.append(out.fileHandleForReading.readDataToEndOfFile())
                errData.append(err.fileHandleForReading.readDataToEndOfFile())
                cont.resume(returning: ProcessResult(
                    stdout: String(decoding: outData.value, as: UTF8.self),
                    stderr: String(decoding: errData.value, as: UTF8.self),
                    status: proc.terminationStatus))
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }
}

final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ d: Data) { lock.lock(); data.append(d); lock.unlock() }
    var value: Data { lock.lock(); defer { lock.unlock() }; return data }
}
