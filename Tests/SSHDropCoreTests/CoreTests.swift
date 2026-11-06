import Testing
import Foundation
@testable import SSHDropCore

@Test func parsesSSHConfig() {
    let text = """
    Host *
      ServerAliveInterval 60
    Host web prod-web
      HostName 10.0.0.5
      User deploy
      Port 2222
      IdentityFile ~/.ssh/id_ed25519
    Host jump
      HostName=jump.example.com
    Match host foo
      User nobody
    """
    let m = SSHConfigParser.parse(text)
    #expect(m.map(\.name) == ["web", "prod-web", "jump"])
    #expect(m[0].host == "10.0.0.5" && m[0].user == "deploy" && m[0].port == 2222)
    #expect(m[2].host == "jump.example.com")
    #expect(m[0].target == "deploy@10.0.0.5")
}

@Test func parsesListing() {
    let out = "/home/me\nDirectory|4096|1700000000|./docs\nRegular File|12|1700000100|./a|b.txt\n"
    let (cwd, files) = RemoteListing.parse(out)
    #expect(cwd == "/home/me")
    #expect(files.count == 2)
    #expect(files[0].isDirectory && files[0].path == "/home/me/docs")
    #expect(files[1].name == "a|b.txt" && files[1].size == 12)
}

@Test func parsesScpProgress() {
    let chunk = "big.iso   12%  120MB  10.1MB/s   01:23 ETA\rbig.iso   45%  450MB  11.0MB/s   00:50 ETA"
    let p = ScpProgressParser.parse(chunk)
    #expect(p?.fraction == 0.45 && p?.speed == "11.0MB/s" && p?.file == "big.iso")
}

@Test func quotes() {
    #expect(shellQuote("it's") == "'it'\\''s'")
}

@Test func classifiesConnection() {
    #expect(ConnectionStatus.classify(exit: 0, stderr: "", ms: 12) == .online(ms: 12))
    #expect(ConnectionStatus.classify(exit: 255, stderr: "git@x: Permission denied (publickey).", ms: 5)
            == .authFailed("git@x: Permission denied (publickey)."))
    #expect(ConnectionStatus.classify(exit: 1, stderr: "Hi me! You've successfully authenticated, but GitHub does not provide shell access.", ms: 9)
            == .online(ms: 9))
    #expect(ConnectionStatus.classify(exit: 255, stderr: "ssh: Could not resolve hostname x", ms: 1)
            == .offline("ssh: Could not resolve hostname x"))
}

@Test func stateDBRoundTrip() throws {
    let db = try StateDB(path: ":memory:")
    #expect(db.get("app", "x") == nil)
    db.setJSON("machine:1", "bookmarks", ["/a", "/b c"])
    #expect(db.getJSON("machine:1", "bookmarks", as: [String].self) == ["/a", "/b c"])
    db.setJSON("machine:1", "bookmarks", ["/z"])            // upsert
    #expect(db.getJSON("machine:1", "bookmarks", as: [String].self) == ["/z"])
    #expect(db.getJSON("machine:2", "bookmarks", as: [String].self) == nil)  // scoped
    db.delete("machine:1", "bookmarks")
    #expect(db.get("machine:1", "bookmarks") == nil)
}
