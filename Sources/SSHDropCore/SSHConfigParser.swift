import Foundation

public enum SSHConfigParser {
    /// Parses ssh_config text into machines. Skips wildcard/negated host patterns and `Match` blocks.
    public static func parse(_ text: String) -> [Machine] {
        struct Block { var names: [String] = []; var kv: [String: String] = [:] }
        var blocks: [Block] = []
        var current: Block?
        var inMatch = false

        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let (key, value) = split(line)
            switch key.lowercased() {
            case "host":
                if let c = current { blocks.append(c) }
                inMatch = false
                current = Block(names: value.split(separator: " ").map(String.init))
            case "match":
                if let c = current { blocks.append(c) }
                current = nil; inMatch = true
            default:
                guard !inMatch, current != nil else { continue }
                let k = key.lowercased()
                if current!.kv[k] == nil { current!.kv[k] = value } // first value wins, like ssh
            }
        }
        if let c = current { blocks.append(c) }

        return blocks.flatMap { b in
            b.names.filter { !$0.contains("*") && !$0.contains("?") && !$0.hasPrefix("!") }.map { name in
                Machine(
                    name: name,
                    host: b.kv["hostname"] ?? name,
                    user: b.kv["user"],
                    port: b.kv["port"].flatMap(Int.init),
                    identityFile: b.kv["identityfile"],
                    proxyJump: b.kv["proxyjump"],
                    source: .sshConfig
                )
            }
        }
    }

    public static func loadDefault() -> [Machine] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text)
    }

    private static func split(_ line: String) -> (String, String) {
        // Accepts "Key value" and "Key=value".
        guard let idx = line.firstIndex(where: { $0 == " " || $0 == "\t" || $0 == "=" }) else { return (line, "") }
        let key = String(line[..<idx])
        var value = line[line.index(after: idx)...].trimmingCharacters(in: CharacterSet(charactersIn: " \t="))
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 { value = String(value.dropFirst().dropLast()) }
        return (key, value)
    }
}
