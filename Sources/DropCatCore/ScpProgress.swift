import Foundation

public struct ScpProgress: Equatable, Sendable {
    public var fraction: Double      // 0...1 of the current file
    public var speed: String         // e.g. "1.2MB/s"
    public var eta: String           // e.g. "00:03"
    public var file: String
}

public enum ScpProgressParser {
    // scp meter: "name      45%  1234KB   1.2MB/s   00:03 ETA"
    private static let regex = try! NSRegularExpression(
        pattern: #"^(.*?)\s+(\d{1,3})%\s+\S+\s+(\S+/s)\s+(\S+)"#)

    /// Parses the latest meter update in a chunk (scp redraws with `\r`).
    public static func parse(_ chunk: String) -> ScpProgress? {
        for piece in chunk.split(whereSeparator: { $0 == "\r" || $0 == "\n" }).reversed() {
            let s = String(piece)
            let range = NSRange(s.startIndex..., in: s)
            guard let m = regex.firstMatch(in: s, range: range),
                  let f = Range(m.range(at: 1), in: s), let p = Range(m.range(at: 2), in: s),
                  let sp = Range(m.range(at: 3), in: s), let e = Range(m.range(at: 4), in: s),
                  let pct = Double(s[p]) else { continue }
            return ScpProgress(fraction: min(pct, 100) / 100, speed: String(s[sp]), eta: String(s[e]), file: String(s[f]))
        }
        return nil
    }
}
