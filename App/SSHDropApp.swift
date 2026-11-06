import SwiftUI

@main
struct SSHDropApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView().environment(model)
                .frame(minWidth: 900, minHeight: 560)
                .focusEffectDisabled()   // no blue focus rings anywhere
        }
        .commands { BrowserMenuCommands() }

        Window("Keyboard Shortcuts", id: "shortcuts") { ShortcutsView() }
            .windowResizability(.contentSize)
    }
}
