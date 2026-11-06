import Foundation

public enum AppPaths {
    /// `~/Library/Application Support/dropcat`. Moves the folder from the old "sshdrop" name once, so existing
    /// machines and settings carry over after the rename.
    public static var supportDirectory: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("dropcat", isDirectory: true)
        let old = base.appendingPathComponent("sshdrop", isDirectory: true)
        if !fm.fileExists(atPath: dir.path), fm.fileExists(atPath: old.path) {
            try? fm.moveItem(at: old, to: dir)
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
