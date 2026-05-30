import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Button(environment.isRecordingPaused ? "Resume Recording" : "Pause Recording") {
            environment.isRecordingPaused.toggle()
        }
        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
