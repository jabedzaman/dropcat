import SwiftUI

struct ShortcutGroup: Identifiable {
    let title: String
    let items: [(name: String, keys: String)]
    var id: String { title }
}

enum Shortcuts {
    static let groups: [ShortcutGroup] = [
        .init(title: "Go", items: [
            ("Back", "⌘ ["), ("Forward", "⌘ ]"), ("Enclosing Folder", "⌘ ↑"),
            ("Open Selected Item", "⌘ ↓"), ("Home", "⇧ ⌘ H"), ("Go to Folder…", "⇧ ⌘ G"),
        ]),
        .init(title: "File", items: [
            ("New Folder", "⇧ ⌘ N"), ("Open", "⌘ O"), ("Rename", "Return"),
            ("Delete", "⌘ ⌫"), ("Quick Look", "Space  or  ⌘ Y"), ("Copy Path", "⌥ ⌘ C"),
        ]),
        .init(title: "View", items: [
            ("as Icons", "⌘ 1"), ("as List", "⌘ 2"), ("Show / Hide Hidden Files", "⇧ ⌘ ."),
            ("Refresh", "⌘ R"), ("Search", "⌘ F"),
        ]),
        .init(title: "Selecting", items: [
            ("Move selection", "↑ ↓ ← →"), ("Expand folder (list view)", "→"),
            ("Collapse folder (list view)", "←"), ("Jump to item by name", "Type its first letters"),
        ]),
        .init(title: "Machines", items: [
            ("Add Machine…", "⌘ K"),
        ]),
    ]
}

struct ShortcutsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Shortcuts.groups) { g in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(g.title).font(.headline)
                        ForEach(g.items, id: \.name) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text(item.keys).monospaced().foregroundStyle(.secondary)
                            }
                            Divider()
                        }
                    }
                }
            }.padding(20)
        }
        .frame(width: 420, height: 520)
    }
}
