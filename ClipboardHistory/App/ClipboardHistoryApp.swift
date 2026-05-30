import SwiftUI

@main
struct ClipboardHistoryApp: App {
    @StateObject private var environment = AppEnvironment.live()

    var body: some Scene {
        MenuBarExtra("Clipboard History", systemImage: "doc.on.clipboard") {
            MenuBarView()
                .environmentObject(environment)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(environment)
        }
    }
}
