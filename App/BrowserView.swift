import SwiftUI
import QuickLook
import DropCatCore

struct BrowserView: View {
    @Environment(AppModel.self) private var model
    let browser: BrowserModel
    @State private var dropTargeted = false
    @State private var previewURL: URL?
    @State private var showGoTo = false
    @FocusState private var searchFocused: Bool
    @State private var gridColumns = 1

    var body: some View {
        @Bindable var browser = browser
        Group {
            switch browser.viewMode {
            case .list: listView
            case .icons: iconsView
            }
        }
        .overlay {
            if browser.loading && browser.files.isEmpty { ProgressView() }
            else if browser.cwd.isEmpty, let e = browser.error {
                ContentUnavailableView("Can't list directory", systemImage: "exclamationmark.triangle", description: Text(e))
            }
        }
        .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 3).padding(4) } }
        .dropDestination(for: URL.self) { urls, _ in
            model.upload(urls, to: browser.cwd, on: browser.machine) { Task { await browser.refresh() } }
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .quickLookPreview($previewURL)
        .onKeyPress(.space) {
            guard let f = browser.selection.first.flatMap({ browser.file(id: $0) }), !f.isDirectory else { return .ignored }
            preview(f)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard browser.viewMode == .list, browser.selection.count == 1,
                  let f = browser.selection.first.flatMap({ browser.file(id: $0) }), f.isDirectory, !browser.isExpanded(f) else { return .ignored }
            Task { await browser.toggle(f) }; return .handled
        }
        .onKeyPress(.leftArrow) {
            guard browser.viewMode == .list, browser.selection.count == 1,
                  let f = browser.selection.first.flatMap({ browser.file(id: $0) }), f.isDirectory, browser.isExpanded(f) else { return .ignored }
            Task { await browser.toggle(f) }; return .handled
        }
        .onKeyPress(characters: .alphanumerics, phases: .down) { press in
            guard browser.renamingID == nil, press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
            browser.typeSelect(press.characters); return .handled
        }
        .onKeyPress(.return) {
            guard browser.renamingID == nil, browser.selection.count == 1, let id = browser.selection.first else { return .ignored }
            browser.beginRename(id)
            return .handled
        }
        .alert(browser.deleteRequest?.title ?? "", isPresented: Binding(
            get: { browser.deleteRequest != nil }, set: { if !$0 { browser.deleteRequest = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let r = browser.deleteRequest { run { try await browser.performDelete(r.files) } }
            }
            Button("Cancel", role: .cancel) { browser.deleteRequest = nil }
        } message: { Text(browser.deleteRequest?.message ?? "") }
        .onChange(of: browser.error) { _, e in
            // After the first load, navigation errors become an alert instead of replacing the file list.
            if let e, !browser.cwd.isEmpty { model.alertError = e; browser.error = nil }
        }
        .sheet(isPresented: $showGoTo) { GoToFolderSheet { p in Task { await browser.open(p) } } }
        .focusedSceneValue(\.browserCommands, commands)
        .navigationTitle(browser.folderName)
        .searchable(text: $browser.query, placement: .toolbar)
        .searchFocused($searchFocused)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { Task { await browser.goBack() } } label: { Image(systemName: "chevron.left") }.disabled(!browser.canBack)
                Button { Task { await browser.goForward() } } label: { Image(systemName: "chevron.right") }.disabled(!browser.canForward)
            }
            ToolbarItem {
                Picker("View", selection: $browser.viewMode) {
                    Label("as Icons", systemImage: "square.grid.2x2").tag(ViewMode.icons)
                    Label("as List", systemImage: "list.bullet").tag(ViewMode.list)
                }
                .pickerStyle(.segmented).labelStyle(.iconOnly)
            }
            ToolbarItem {
                Menu {
                    Button("Enclosing Folder") { Task { await browser.goUp() } }
                        .disabled(browser.cwd == "/" || browser.cwd.isEmpty)
                    Button("New Folder") { createFolder() }
                    Toggle("Show Hidden Files", isOn: $browser.showHidden)
                    Button("Refresh") { Task { await browser.refresh() } }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .task { await browser.start() }
    }

    // MARK: List

    private var listView: some View {
        @Bindable var browser = browser
        return Table(browser.rows, selection: $browser.selection, sortOrder: $browser.sortOrder) {
            TableColumn("Name", value: \.name) { row in
                let f = row.file
                HStack(spacing: 4) {
                    Color.clear.frame(width: CGFloat(row.depth) * 18, height: 1)
                    if f.isDirectory {
                        Button { Task { await browser.toggle(f) } } label: {
                            if browser.loadingDirs.contains(f.path) {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .rotationEffect(.degrees(browser.isExpanded(f) ? 90 : 0))
                            }
                        }.buttonStyle(.plain).frame(width: 14)
                    } else { Color.clear.frame(width: 14, height: 1) }
                    Image(nsImage: FileIcon.image(for: f)).resizable().frame(width: 18, height: 18)
                    if browser.renamingID == f.id {
                        RenameField(browser: browser, file: f)
                    } else {
                        Text(f.name).lineLimit(1)
                    }
                }
                .opacity(dim(f)).overlay(alignment: .leading) { spinner(f).padding(.leading, CGFloat(row.depth) * 18 + 4) }
            }
            TableColumn("Date Modified", value: \.modified) { row in
                Text(row.file.modified.finderStyle).foregroundStyle(.secondary).opacity(dim(row.file))
            }.width(min: 120, ideal: 190)
            TableColumn("Size", value: \.sizeSort) { row in
                Text(row.file.isDirectory ? "--" : row.file.size.formatted(.byteCount(style: .file)))
                    .foregroundStyle(.secondary).opacity(dim(row.file))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }.width(min: 60, ideal: 90)
            TableColumn("Kind", value: \.kind) { row in
                Text(row.file.kindDescription).foregroundStyle(.secondary).opacity(dim(row.file))
            }.width(min: 80, ideal: 130)
        }
        .contextMenu(forSelectionType: RemoteFile.ID.self) { ids in
            if let f = ids.first.flatMap({ browser.file(id: $0) }) { actions(f, ids: ids) } else { backgroundMenu }
        } primaryAction: { ids in
            if let f = ids.first.flatMap({ browser.file(id: $0) }) { activate(f) }
        }
    }

    // MARK: Icons

    private var iconsView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 12) {
                ForEach(browser.rows) { row in
                    let f = row.file
                    let selected = browser.selection.contains(f.id)
                    VStack(spacing: 4) {
                        // Finder: neutral grey tile behind the icon, solid accent pill behind the name.
                        Image(nsImage: FileIcon.image(for: f)).resizable().frame(width: 56, height: 56)
                            .padding(6)
                            .background(selected ? Color.primary.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        if browser.renamingID == f.id {
                            RenameField(browser: browser, file: f, centered: true)
                        } else {
                            Text(f.name).font(.callout).lineLimit(2).multilineTextAlignment(.center)
                                .foregroundStyle(selected ? Color.white : .primary)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(selected ? Color(nsColor: .selectedContentBackgroundColor) : .clear,
                                            in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .opacity(dim(f))
                    .overlay { spinner(f) }
                    .padding(4).frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { activate(f) }
                    .onTapGesture { browser.selection = [f.id] }
                    .contextMenu { actions(f, ids: [f.id]) }
                }
            }.padding(12)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in
            // Matches GridItem(.adaptive(minimum: 96), spacing: 8) with 12pt side padding.
            gridColumns = max(1, Int((w - 24 + 8) / (96 + 8)))
        }
        .onKeyPress(.leftArrow) { browser.moveSelection(by: -1); return .handled }
        .onKeyPress(.rightArrow) { browser.moveSelection(by: 1); return .handled }
        .onKeyPress(.upArrow) { browser.moveSelection(by: -gridColumns); return .handled }
        .onKeyPress(.downArrow) { browser.moveSelection(by: gridColumns); return .handled }
        .focusable()
        .focusEffectDisabled()
        .onTapGesture { browser.selection = [] }
        .contextMenu { backgroundMenu }
    }

    // MARK: Actions

    /// Right-click on empty space.
    @ViewBuilder private var backgroundMenu: some View {
        @Bindable var browser = browser
        Button("New Folder") { createFolder() }
        Divider()
        Button("Refresh") { Task { await browser.refresh() } }
        Menu("View") {
            Picker("View", selection: $browser.viewMode) {
                Text("as Icons").tag(ViewMode.icons)
                Text("as List").tag(ViewMode.list)
            }.pickerStyle(.inline)
            Divider()
            Toggle("Show Hidden Files", isOn: $browser.showHidden)
        }
        Divider()
        Button("Copy Path") {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(browser.cwd, forType: .string)
        }
    }

    @ViewBuilder private func actions(_ f: RemoteFile, ids: Set<RemoteFile.ID>) -> some View {
        if f.isDirectory {
            Button("Open") { activate(f) }
            Button("Add to Favorites") { model.addBookmark(f.path, on: browser.machine) }
        } else {
            Button("Quick Look") { preview(f) }
            Button("Download “\(f.name)”") { download(f) }
        }
        Button("Rename") { browser.selection = [f.id]; browser.beginRename(f.id) }
        Button("Delete", role: .destructive) { delete(ids.contains(f.id) ? ids : [f.id]) }
        Divider()
        Button("Copy Path") {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(f.path, forType: .string)
        }
    }

    private var single: RemoteFile? {
        browser.selection.count == 1 ? browser.selection.first.flatMap { browser.file(id: $0) } : nil
    }

    private var commands: BrowserCommands {
        BrowserCommands(
            canBack: browser.canBack, canForward: browser.canForward,
            canUp: !browser.cwd.isEmpty && browser.cwd != "/",
            hasSelection: !browser.selection.isEmpty, singleSelection: single != nil,
            hasFolderSelected: single?.isDirectory ?? false,
            viewMode: browser.viewMode, showHidden: browser.showHidden, isRenaming: browser.renamingID != nil || searchFocused,
            back: { Task { await browser.goBack() } },
            forward: { Task { await browser.goForward() } },
            up: { Task { await browser.goUp() } },
            home: { Task { await browser.open(nil) } },
            goTo: { showGoTo = true },
            openSelection: { if let f = single { activate(f) } },
            newFolder: { createFolder() },
            rename: { if let id = single?.id { browser.beginRename(id) } },
            delete: { delete(browser.selection) },
            quickLook: { if let f = single, !f.isDirectory { preview(f) } },
            copyPath: {
                let paths = browser.selection.isEmpty ? [browser.cwd] : browser.selection.sorted()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
            },
            setViewMode: { browser.viewMode = $0 },
            toggleHidden: { browser.showHidden.toggle() },
            refresh: { Task { await browser.refresh() } }
        )
    }

    private func delete(_ ids: Set<RemoteFile.ID>) { run { try await browser.requestDelete(ids) } }

    private func run(_ work: @escaping () async throws -> Void) {
        Task { do { try await work() } catch { model.alertError = error.localizedDescription } }
    }

    /// Like Finder: create "untitled folder", select it, and drop straight into rename.
    private func createFolder() {
        Task {
            do {
                let id = try await browser.newUntitledFolder()
                browser.selection = [id]
                browser.beginRename(id)
            } catch { model.alertError = error.localizedDescription }
        }
    }

    private func activate(_ f: RemoteFile) {
        if f.isDirectory { Task { await browser.open(f.path) } } else { download(f) }
    }

    private func dim(_ f: RemoteFile) -> Double { model.previewing.contains(f.id) ? 0.4 : 1 }

    @ViewBuilder private func spinner(_ f: RemoteFile) -> some View {
        if model.previewing.contains(f.id) { ProgressView().controlSize(.small) }
    }

    private func preview(_ f: RemoteFile) {
        model.fetchForPreview(f, on: browser.machine) { previewURL = $0 }
    }

    private func download(_ f: RemoteFile) {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        model.download(f, on: browser.machine, to: dir)
    }
}

/// Inline rename field shared by list and icon views. Return/blur commits, Esc cancels.
struct RenameField: View {
    @Environment(AppModel.self) private var model
    let browser: BrowserModel
    let file: RemoteFile
    var centered = false
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var browser = browser
        TextField("", text: $browser.renameText)
            .textFieldStyle(.plain)
            .multilineTextAlignment(centered ? .center : .leading)
            .focused($focused)
            .onSubmit { commit() }
            .onExitCommand { browser.cancelRename() }
            .onChange(of: focused) { _, isFocused in
                if !isFocused, browser.renamingID == file.id { commit() }
            }
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 2))
            .task { focused = true }
    }

    private func commit() {
        Task {
            do {
                if let id = try await browser.commitRename() { browser.selection = [id] }
            } catch { model.alertError = error.localizedDescription }
        }
    }
}
