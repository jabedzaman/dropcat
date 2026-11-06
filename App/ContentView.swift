import SwiftUI
import SSHDropCore

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            MachinesSidebar()
        } detail: {
            if let m = model.selected {
                BrowserView(browser: model.browser(for: m)).id(m.id)
            } else {
                ContentUnavailableView("No machine selected", systemImage: "server.rack",
                                       description: Text("Pick a machine, or add one with +."))
            }
        }
        .focusEffectDisabled()
        .safeAreaInset(edge: .bottom) { TransferBar() }
        .alert("Error", isPresented: Binding(get: { model.alertError != nil }, set: { if !$0 { model.alertError = nil } })) {
            Button("OK") { model.alertError = nil }
        } message: { Text(model.alertError ?? "") }
        .alert("Test Connection", isPresented: Binding(get: { model.testResult != nil }, set: { if !$0 { model.testResult = nil } })) {
            Button("OK") { model.testResult = nil }
        } message: {
            if let r = model.testResult { Text("\(r.name): \(r.status.summary)") }
        }
    }
}
