import Foundation
import Darwin

public enum TransferDirection: Sendable {
    case upload(local: URL, remotePath: String)
    case download(remotePath: String, local: URL)
}

public enum TransferEvent: Sendable {
    case progress(ScpProgress)
    case finished
    case failed(String)
}

public enum Transfer {
    /// Runs scp under a pty so it emits its progress meter. Cancel by cancelling the consuming task.
    public static func run(_ direction: TransferDirection, on machine: Machine) -> AsyncStream<TransferEvent> {
        AsyncStream { continuation in
            var m: Int32 = 0, s: Int32 = 0
            guard openpty(&m, &s, nil, nil, nil) == 0 else {
                continuation.yield(.failed("openpty failed")); continuation.finish(); return
            }
            let master = m, slave = s
            var args = machine.connectionOptions() + ["-r", "-p"]
            if let port = machine.port { args += ["-P", String(port)] }
            // scp speaks SFTP (OpenSSH 9+), so remote paths are literal: no shell quoting.
            switch direction {
            case let .upload(local, remote): args += [local.path, "\(machine.target):\(remote)"]
            case let .download(remote, local): args += ["\(machine.target):\(remote)", local.path]
            }

            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
            p.arguments = args
            let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
            p.standardOutput = slaveHandle; p.standardError = slaveHandle
            p.standardInput = FileHandle.nullDevice

            let tail = LockedData()
            let reader = FileHandle(fileDescriptor: master, closeOnDealloc: false)
            reader.readabilityHandler = { h in
                let d = h.availableData
                guard !d.isEmpty else { return }
                let s = String(decoding: d, as: UTF8.self)
                tail.append(d)
                if let prog = ScpProgressParser.parse(s) { continuation.yield(.progress(prog)) }
            }
            p.terminationHandler = { proc in
                reader.readabilityHandler = nil
                close(master); close(slave)
                if proc.terminationStatus == 0 {
                    continuation.yield(.finished)
                } else {
                    let msg = String(decoding: tail.value.suffix(600), as: UTF8.self)
                        .replacingOccurrences(of: "\r", with: "\n")
                        .split(separator: "\n").last.map(String.init) ?? "scp exited \(proc.terminationStatus)"
                    continuation.yield(.failed(msg))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in if p.isRunning { p.terminate() } }
            do { try p.run() } catch {
                close(master); close(slave)
                continuation.yield(.failed(error.localizedDescription)); continuation.finish()
            }
        }
    }
}
