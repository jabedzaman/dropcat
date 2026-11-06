import AppKit
import UniformTypeIdentifiers
import SSHDropCore

/// System icons (same ones Finder uses), cached by type.
@MainActor
enum FileIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for f: RemoteFile) -> NSImage {
        let key: String
        let type: UTType
        switch f.kind {
        case .directory: key = "dir"; type = .folder
        case .symlink: key = "alias"; type = .aliasFile
        default:
            let ext = (f.name as NSString).pathExtension.lowercased()
            key = ext; type = UTType(filenameExtension: ext) ?? .data
        }
        if let img = cache[key] { return img }
        let img = NSWorkspace.shared.icon(for: type)
        cache[key] = img
        return img
    }
}

extension Date {
    /// Finder-style: "Today at 19:21", "8 Oct 2026 at 17:28".
    var finderStyle: String {
        let cal = Calendar.current
        let time = formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        if cal.isDateInToday(self) { return "Today at \(time)" }
        if cal.isDateInYesterday(self) { return "Yesterday at \(time)" }
        return "\(formatted(.dateTime.day().month(.abbreviated).year())) at \(time)"
    }
}
