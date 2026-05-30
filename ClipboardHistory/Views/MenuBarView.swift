import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Button("Open Search") {
            environment.openSearch()
        }

        if let message = environment.lastErrorMessage ?? environment.settingsViewModel.lastErrorMessage {
            Text(message)
                .foregroundStyle(.red)
        }

        if environment.isSearchPresented {
            ClipboardPopupView(
                viewModel: environment.historyViewModel,
                onPaste: environment.paste,
                onCopy: environment.copy
            )

            Divider()
        }

        Divider()

        RecordMenusView(
            viewModel: environment.historyViewModel,
            onPaste: environment.paste
        )

        Divider()

        Button(environment.isRecordingPaused ? "Resume Recording" : "Pause Recording") {
            environment.isRecordingPaused.toggle()
        }

        Menu("Clear History") {
            Button("Clear Non-Favorites") {
                confirmClearNonFavorites()
            }

            Button("Clear All Records", role: .destructive) {
                confirmClearAll()
            }
        }

        Divider()

        Button("Settings") {
            environment.openSettings()
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .onAppear {
            environment.historyViewModel.reload()
        }
    }

    private func confirmClearNonFavorites() {
        guard confirmClear(
            title: "Clear Non-Favorites?",
            message: "This removes every clipboard record that is not marked as a favorite.",
            confirmTitle: "Clear Non-Favorites"
        ) else {
            return
        }

        environment.settingsViewModel.clearNonFavorites()
    }

    private func confirmClearAll() {
        guard confirmClear(
            title: "Clear All Records?",
            message: "This removes every clipboard record, including favorites.",
            confirmTitle: "Clear All Records"
        ) else {
            return
        }

        environment.settingsViewModel.clearAll()
    }

    private func confirmClear(title: String, message: String, confirmTitle: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

private struct RecordMenusView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    let onPaste: (ClipboardItem) -> Void

    var body: some View {
        Menu("Recent Records") {
            recordButtons(for: Array(viewModel.items.prefix(8)))
        }

        Menu("Favorites") {
            recordButtons(for: viewModel.items.filter(\.isFavorite))
        }
    }

    @ViewBuilder
    private func recordButtons(for items: [ClipboardItem]) -> some View {
        if items.isEmpty {
            Text("No Records")
                .foregroundStyle(.secondary)
        } else {
            ForEach(items) { item in
                Button(menuTitle(for: item)) {
                    onPaste(item)
                }
            }
        }
    }

    private func menuTitle(for item: ClipboardItem) -> String {
        switch item.kind {
        case .text:
            let value = item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? "Empty Text" : String(value.prefix(48))
        case .image:
            return "Image - \(item.copiedAt.formatted(date: .omitted, time: .shortened))"
        }
    }
}
