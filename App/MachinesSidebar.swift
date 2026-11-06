import SwiftUI
import DropCatCore

struct MachinesSidebar: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false
    @State private var importing = false

    var body: some View {
        List(selection: Binding(get: { model.sidebarSelection }, set: { model.select($0) })) {
            if let m = model.selected {
                Section("Favorites") {
                    ForEach(model.places(for: m), id: \.self) { path in
                        Label(Self.title(path), systemImage: Self.icon(path))
                            .tag(SidebarItem.place(path))
                            .contextMenu {
                                if path != "~" && path != "/" {
                                    Button("Remove from Favorites") { model.removeBookmark(path, on: m) }
                                }
                            }
                    }
                }
            }
            Section("Locations") {
                ForEach(model.machines.sorted { $0.isFavorite && !$1.isFavorite }) { m in
                    Label {
                        Text(m.name)
                    } icon: {
                        Image(systemName: "desktopcomputer")
                            .overlay(alignment: .bottomTrailing) { StatusDot(status: model.statusOf(m)).offset(x: 4, y: 3) }
                    }
                        .tag(SidebarItem.machine(m.id))
                        .help("\(m.target)\n\(model.statusOf(m).summary)")
                        .contextMenu {
                            Button("Test Connection") { model.test(m) }
                            Button(m.isFavorite ? "Unpin" : "Pin to Top") { model.toggleFavorite(m) }
                            Button("Remove", role: .destructive) { model.remove(m) }
                        }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Add Machine…") { adding = true }.keyboardShortcut("k", modifiers: .command)
                    Button("Import from SSH Config…") { importing = true }
                } label: { Label("Add", systemImage: "plus") }
            }
            ToolbarItem { Button { Task { await model.checkAll() } } label: { Label("Recheck connections", systemImage: "arrow.clockwise") } }
        }
        .sheet(isPresented: $adding) { AddMachineSheet() }
        .sheet(isPresented: $importing) { ImportSSHConfigSheet() }
        .overlay {
            if model.machines.isEmpty {
                ContentUnavailableView {
                    Label("No Machines", systemImage: "server.rack")
                } description: {
                    Text("Add a machine, or import from your SSH config.")
                } actions: {
                    Button("Add Machine…") { adding = true }
                    Button("Import from SSH Config…") { importing = true }
                }
            }
        }
    }

    static func title(_ path: String) -> String {
        path == "~" ? "Home" : path == "/" ? "Root" : (path as NSString).lastPathComponent
    }
    static func icon(_ path: String) -> String {
        path == "~" ? "house" : path == "/" ? "internaldrive" : "folder"
    }
}

struct StatusDot: View {
    let status: ConnectionStatus
    var body: some View {
        Group {
            if status == .checking {
                ProgressView().controlSize(.mini).scaleEffect(0.5)
            } else {
                Circle().fill(color).overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
            }
        }.frame(width: 8, height: 8)
    }
    private var color: Color {
        switch status {
        case .online: .green
        case .authFailed: .orange
        case .offline: .red
        default: .gray.opacity(0.6)
        }
    }
}

struct AddMachineSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var host = ""
    @State private var user = ""
    @State private var port = ""
    @State private var key = ""
    @State private var testing = ConnectionStatus.unknown
    @State private var configHosts: [Machine] = []

    private var draft: Machine {
        Machine(name: name.isEmpty ? host : name, host: host, user: user.isEmpty ? nil : user,
                port: Int(port), identityFile: key.isEmpty ? nil : key)
    }

    var body: some View {
        Form {
            if !configHosts.isEmpty {
                Menu("Fill from SSH config") {
                    ForEach(configHosts) { h in
                        Button(h.name) {
                            name = h.name; host = h.host; user = h.user ?? ""
                            port = h.port.map(String.init) ?? ""; key = h.identityFile ?? ""
                        }
                    }
                }
            }
            TextField("Name", text: $name)
            TextField("Host", text: $host)
            TextField("User", text: $user)
            TextField("Port", text: $port)
            TextField("Identity file", text: $key, prompt: Text("~/.ssh/id_ed25519"))
            HStack {
                Button("Test") {
                    testing = .checking
                    let m = draft
                    Task { testing = await SSHClient(m).check() }
                }.disabled(host.isEmpty || testing == .checking)
                if testing != .unknown {
                    StatusDot(status: testing)
                    Text(testing.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    let m = draft
                    model.add(m)
                    Task { await model.check(m) }
                    dismiss()
                }.keyboardShortcut(.defaultAction).disabled(host.isEmpty)
            }
        }
        .formStyle(.grouped).frame(width: 420).padding()
        .onAppear { configHosts = SSHConfigParser.loadDefault() }
    }
}

struct ImportSSHConfigSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var hosts: [Machine] = []
    @State private var picked = Set<Machine.ID>()

    private func isAdded(_ h: Machine) -> Bool {
        model.machines.contains { $0.name == h.name && $0.host == h.host }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import from SSH Config").font(.headline)
            Text("Pick hosts to add. Imported machines are managed here independently of ~/.ssh/config.")
                .font(.callout).foregroundStyle(.secondary)
            if hosts.isEmpty {
                ContentUnavailableView("No hosts found", systemImage: "doc.text.magnifyingglass")
            } else {
                List(hosts) { h in
                    Toggle(isOn: Binding(
                        get: { picked.contains(h.id) || isAdded(h) },
                        set: { if $0 { picked.insert(h.id) } else { picked.remove(h.id) } }
                    )) {
                        VStack(alignment: .leading) {
                            Text(h.name)
                            Text(h.target + (h.port.map { ":\($0)" } ?? "")).font(.caption).foregroundStyle(.secondary)
                        }
                    }.disabled(isAdded(h))
                }.frame(minHeight: 220)
            }
            HStack {
                Button("Select All") { picked = Set(hosts.filter { !isAdded($0) }.map(\.id)) }.disabled(hosts.isEmpty)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import \(picked.count)") {
                    model.importHosts(hosts.filter { picked.contains($0.id) }); dismiss()
                }.keyboardShortcut(.defaultAction).disabled(picked.isEmpty)
            }
        }
        .padding().frame(width: 440)
        .onAppear { hosts = SSHConfigParser.loadDefault() }
    }
}
