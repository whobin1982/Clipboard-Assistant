import AppKit
import SwiftUI

/// 旧版 SwiftUI 菜单栏内容视图，保留给未来如果改回 MenuBarExtra 时复用。
struct MenuBarView: View {
    @EnvironmentObject private var environment: AppEnvironment

    /// 菜单内容：打开历史、错误提示、记录子菜单、开关、清理、设置、帮助、关于和退出。
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

    /// 清空非收藏记录前确认。
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

    /// 清空全部记录前确认。
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

    /// 通用确认弹窗。
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

/// 最近记录和收藏记录两个子菜单。
private struct RecordMenusView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    let onPaste: (ClipboardItem) -> Void

    /// 分别展示最近 8 条和全部收藏记录。
    var body: some View {
        Menu("最近记录") {
            recordButtons(for: Array(viewModel.items.prefix(8)))
        }

        Menu("收藏记录") {
            recordButtons(for: viewModel.items.filter(\.isFavorite))
        }
    }

    /// 将记录数组渲染成菜单按钮；空列表显示占位文案。
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

    /// 菜单标题做截断，避免系统菜单过宽。
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
