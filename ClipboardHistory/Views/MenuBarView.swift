import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Button("打开剪贴板历史") {
            environment.openSearch()
        }

        if let message = environment.lastErrorMessage ?? environment.settingsViewModel.lastErrorMessage {
            Text(message)
                .foregroundStyle(.red)
        }

        Divider()

        RecordMenusView(
            viewModel: environment.historyViewModel,
            onPaste: environment.paste
        )

        Divider()

        Button(environment.isRecordingPaused ? "继续记录剪贴板" : "暂停记录剪贴板") {
            environment.isRecordingPaused.toggle()
        }

        Menu("清空历史") {
            Button("清空非收藏记录") {
                confirmClearNonFavorites()
            }

            Button("清空全部记录", role: .destructive) {
                confirmClearAll()
            }
        }

        Divider()

        Button("设置") {
            environment.openSettings()
        }

        Button("帮助") {
            HelpWindowPresenter.shared.show()
        }

        Button("关于剪贴板助手") {
            AboutPanelPresenter.show()
        }

        Divider()

        Button("退出") {
            NSApplication.shared.terminate(nil)
        }
        .onAppear {
            environment.historyViewModel.reload()
        }
    }

    private func confirmClearNonFavorites() {
        guard confirmClear(
            title: "清空非收藏记录？",
            message: "这会删除所有没有标记为收藏的剪贴板记录。",
            confirmTitle: "清空非收藏记录"
        ) else {
            return
        }

        environment.settingsViewModel.clearNonFavorites()
    }

    private func confirmClearAll() {
        guard confirmClear(
            title: "清空全部记录？",
            message: "这会删除所有剪贴板记录，包括收藏记录。",
            confirmTitle: "清空全部记录"
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
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

private struct RecordMenusView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    let onPaste: (ClipboardItem) -> Void

    var body: some View {
        Menu("最近记录") {
            recordButtons(for: Array(viewModel.items.prefix(8)))
        }

        Menu("收藏记录") {
            recordButtons(for: viewModel.items.filter(\.isFavorite))
        }
    }

    @ViewBuilder
    private func recordButtons(for items: [ClipboardItem]) -> some View {
        if items.isEmpty {
            Text("暂无记录")
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
            return value.isEmpty ? "空文本" : String(value.prefix(48))
        case .image:
            return "图片 · \(item.copiedAt.formatted(date: .omitted, time: .shortened))"
        }
    }
}
