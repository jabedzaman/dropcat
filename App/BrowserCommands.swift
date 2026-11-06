import SwiftUI

/// What the menu bar can ask the focused browser window to do.
struct BrowserCommands {
    var canBack = false, canForward = false, canUp = false
    var hasSelection = false, singleSelection = false, hasFolderSelected = false
    var viewMode = ViewMode.list
    var showHidden = false
    /// True while a text field (rename or search) has focus, so ⌘⌫ edits text instead of deleting files.
    var isRenaming = false

    var back: () -> Void = {}
    var forward: () -> Void = {}
    var up: () -> Void = {}
    var home: () -> Void = {}
    var goTo: () -> Void = {}
    var openSelection: () -> Void = {}
    var newFolder: () -> Void = {}
    var rename: () -> Void = {}
    var delete: () -> Void = {}
    var quickLook: () -> Void = {}
    var copyPath: () -> Void = {}
    var setViewMode: (ViewMode) -> Void = { _ in }
    var toggleHidden: () -> Void = {}
    var refresh: () -> Void = {}
}

extension FocusedValues {
    @Entry var browserCommands: BrowserCommands?
}

/// Finder-style menus. Menu items are disabled while a text field is being edited, so ⌘⌫ never deletes files mid-typing.
struct BrowserMenuCommands: Commands {
    @FocusedValue(\.browserCommands) private var c
    @Environment(\.openWindow) private var openWindow

    private var off: Bool { c == nil || c?.isRenaming == true }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Folder") { c?.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift]).disabled(off)
            Button("Open") { c?.openSelection() }
                .keyboardShortcut("o", modifiers: .command).disabled(off || !(c?.singleSelection ?? false))
            Divider()
            Button("Rename") { c?.rename() }.disabled(off || !(c?.singleSelection ?? false))
            Button("Delete…") { c?.delete() }
                .keyboardShortcut(.delete, modifiers: .command).disabled(off || !(c?.hasSelection ?? false))
            Button("Quick Look") { c?.quickLook() }
                .keyboardShortcut("y", modifiers: .command).disabled(off || !(c?.singleSelection ?? false))
            Divider()
            Button("Copy Path") { c?.copyPath() }
                .keyboardShortcut("c", modifiers: [.command, .option]).disabled(off)
        }
        CommandGroup(before: .toolbar) {
            Button("as Icons") { c?.setViewMode(.icons) }
                .keyboardShortcut("1", modifiers: .command).disabled(off)
            Button("as List") { c?.setViewMode(.list) }
                .keyboardShortcut("2", modifiers: .command).disabled(off)
            Divider()
            Button((c?.showHidden ?? false) ? "Hide Hidden Files" : "Show Hidden Files") { c?.toggleHidden() }
                .keyboardShortcut(".", modifiers: [.command, .shift]).disabled(off)
            Button("Refresh") { c?.refresh() }
                .keyboardShortcut("r", modifiers: .command).disabled(off)
            Divider()
        }
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { openWindow(id: "shortcuts") }
                .keyboardShortcut("?", modifiers: .command)
        }
        CommandMenu("Go") {
            Button("Back") { c?.back() }
                .keyboardShortcut("[", modifiers: .command).disabled(off || !(c?.canBack ?? false))
            Button("Forward") { c?.forward() }
                .keyboardShortcut("]", modifiers: .command).disabled(off || !(c?.canForward ?? false))
            Button("Enclosing Folder") { c?.up() }
                .keyboardShortcut(.upArrow, modifiers: .command).disabled(off || !(c?.canUp ?? false))
            Button("Open Selected Item") { c?.openSelection() }
                .keyboardShortcut(.downArrow, modifiers: .command).disabled(off || !(c?.singleSelection ?? false))
            Divider()
            Button("Home") { c?.home() }
                .keyboardShortcut("h", modifiers: [.command, .shift]).disabled(off)
            Button("Go to Folder…") { c?.goTo() }
                .keyboardShortcut("g", modifiers: [.command, .shift]).disabled(off)
        }
    }
}

struct GoToFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    let go: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Go to the folder:").font(.headline)
            TextField("", text: $path, prompt: Text("/var/log or ~/projects"))
                .textFieldStyle(.roundedBorder).onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Go", action: submit).keyboardShortcut(.defaultAction)
                    .disabled(path.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding().frame(width: 380)
    }

    private func submit() {
        let p = path.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return }
        go(p); dismiss()
    }
}
