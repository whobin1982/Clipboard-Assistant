import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Button("Open Search") {
            environment.openSearch()
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
                environment.settingsViewModel.clearNonFavorites()
            }

            Button("Clear All Records", role: .destructive) {
                environment.settingsViewModel.clearAll()
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
