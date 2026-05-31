import AppKit
import SwiftUI

/// 剪贴板历史弹窗主视图，包含工具栏、搜索框、记录列表和键盘选择逻辑。
struct ClipboardPopupView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    @ObservedObject var recordingPauseState: RecordingPauseState
    @StateObject private var selectionController = ClipboardSelectionController()
    @State private var clearConfirmation: ClipboardClearConfirmation?

    var escapeClosesWindow: Bool
    @Binding var isRecordingPaused: Bool
    var onClose: () -> Void
    var onOpenSettings: () -> Void
    var onClearNonFavorites: () -> Void
    var onClearAll: () -> Void
    var onPaste: (ClipboardItem) -> Void
    var onCopy: (ClipboardItem) -> Void
    var onDelete: (ClipboardItem) -> Void

    /// 弹窗内容布局：顶部操作栏，中间错误或空状态，底部历史列表。
    var body: some View {
        let visibleItems = viewModel.filteredItems

        VStack(alignment: .leading, spacing: 10) {
            KeyEventHandlingView(
                onDownArrow: {
                    selectionController.moveDown(in: visibleItems)
                },
                onUpArrow: {
                    selectionController.moveUp(in: visibleItems)
                },
                onReturn: {
                    guard let item = selectionController.selectedItem(in: visibleItems) else { return }
                    onPaste(item)
                },
                onEscape: {
                    if escapeClosesWindow {
                        onClose()
                    }
                },
                searchQuery: viewModel.query,
                onNumberShortcut: { number in
                    guard let item = selectionController.selectNumberShortcut(number, in: visibleItems) else { return }
                    onPaste(item)
                }
            )
            .frame(width: 0, height: 0)

            HStack(spacing: 8) {
                Toggle("自动记录", isOn: isRecordingEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
                    .help(recordingPauseState.isPaused ? "点击后继续记录剪贴板" : "点击后暂停记录剪贴板")

                Menu {
                    Button("清空非收藏记录") {
                        clearConfirmation = .nonFavorites
                    }

                    Button("清空全部记录", role: .destructive) {
                        clearConfirmation = .all
                    }
                } label: {
                    Label("删除历史", systemImage: "trash")
                }
                .menuStyle(.button)
                .controlSize(.small)
                .help("清理剪贴板历史记录")

                Button {
                    onOpenSettings()
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
                .controlSize(.small)
                .help("打开设置")

                Spacer(minLength: 12)

                TextField("搜索剪贴板历史", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180, maxWidth: 260)
            }

            HStack(spacing: 8) {
                Spacer()

                Picker("记录类型", selection: $viewModel.filter) {
                    ForEach(ClipboardHistoryFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 320)
                .help("按记录类型筛选")

                Spacer()
            }
            .frame(maxWidth: .infinity)

            if let message = viewModel.lastErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            if visibleItems.isEmpty {
                ContentUnavailableView("暂无剪贴板记录", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                List(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                    ClipboardRowView(
                        item: item,
                        shortcutNumber: index < 9 ? index + 1 : nil,
                        isSelected: selectionController.selectedItemID == item.id,
                        onFavorite: { viewModel.toggleFavorite(item) },
                        onDelete: { onDelete(item) },
                        onPaste: { onPaste(item) },
                        onCopy: { onCopy(item) }
                    )
                }
                .listStyle(.plain)
                .frame(minHeight: 180)
            }
        }
        .padding(12)
        .frame(minWidth: 520, minHeight: 328)
        .onAppear {
            viewModel.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardHistoryDidChange)) { _ in
            viewModel.reload()
        }
        .alert(item: $clearConfirmation) { confirmation in
            Alert(
                title: Text(confirmation.title),
                message: Text(confirmation.message),
                primaryButton: .destructive(Text(confirmation.confirmTitle)) {
                    switch confirmation {
                    case .nonFavorites:
                        onClearNonFavorites()
                    case .all:
                        onClearAll()
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .onChange(of: viewModel.filteredItems.map(\.id)) { _, _ in
            selectionController.reconcileSelection(with: viewModel.filteredItems)
        }
    }

    /// 界面显示“自动记录”，底层存储的是“是否暂停”，因此这里反向绑定。
    private var isRecordingEnabled: Binding<Bool> {
        Binding(
            get: { !recordingPauseState.isPaused },
            set: { isRecordingPaused = !$0 }
        )
    }
}

/// 清空历史前的二次确认类型。
private enum ClipboardClearConfirmation: Hashable, Identifiable {
    case nonFavorites
    case all

    var id: Self { self }

    /// 确认弹窗标题。
    var title: String {
        switch self {
        case .nonFavorites:
            return "清空非收藏记录？"
        case .all:
            return "清空全部记录？"
        }
    }

    /// 确认弹窗说明。
    var message: String {
        switch self {
        case .nonFavorites:
            return "这会删除所有没有标记为收藏的剪贴板记录。"
        case .all:
            return "这会删除所有剪贴板记录，包括收藏记录。"
        }
    }

    /// 危险操作按钮文案。
    var confirmTitle: String {
        switch self {
        case .nonFavorites:
            return "清空非收藏记录"
        case .all:
            return "清空全部记录"
        }
    }
}

/// SwiftUI 包装的 AppKit 键盘监听视图，用来捕获上下键、回车和 Esc。
private struct KeyEventHandlingView: NSViewRepresentable {
    let onDownArrow: () -> Void
    let onUpArrow: () -> Void
    let onReturn: () -> Void
    let onEscape: () -> Void
    let searchQuery: String
    let onNumberShortcut: (Int) -> Void

    /// 创建原生 NSView 并安装本地键盘事件监听。
    func makeNSView(context: Context) -> KeyEventMonitorView {
        let view = KeyEventMonitorView()
        updateNSView(view, context: context)
        view.installMonitor()
        return view
    }

    /// SwiftUI 状态更新时同步最新回调，避免闭包捕获旧状态。
    func updateNSView(_ nsView: KeyEventMonitorView, context: Context) {
        nsView.onDownArrow = onDownArrow
        nsView.onUpArrow = onUpArrow
        nsView.onReturn = onReturn
        nsView.onEscape = onEscape
        nsView.searchQuery = searchQuery
        nsView.onNumberShortcut = onNumberShortcut
    }

    /// 视图销毁时移除监听。
    static func dismantleNSView(_ nsView: KeyEventMonitorView, coordinator: ()) {
        nsView.removeMonitor()
    }
}

/// 实际接收键盘事件的 NSView。
private final class KeyEventMonitorView: NSView {
    var onDownArrow: () -> Void = {}
    var onUpArrow: () -> Void = {}
    var onReturn: () -> Void = {}
    var onEscape: () -> Void = {}
    var searchQuery: String = ""
    var onNumberShortcut: (Int) -> Void = { _ in }

    private var monitor: Any?

    /// 安装窗口内 keyDown 监听；返回 nil 表示按键已被处理，不再传给其他控件。
    func installMonitor() {
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard
                let self,
                let window = self.window,
                event.window === window
            else {
                return event
            }

            if
                let number = ClipboardKeyboardShortcut.numberShortcut(
                    keyCode: event.keyCode,
                    modifierFlags: event.modifierFlags,
                    searchQuery: self.searchQuery,
                    isTextEditing: Self.isEditingText(in: window)
                )
            {
                self.onNumberShortcut(number)
                return nil
            }

            switch event.keyCode {
            case 125:
                self.onDownArrow()
                return nil
            case 126:
                self.onUpArrow()
                return nil
            case 36, 76:
                self.onReturn()
                return nil
            case 53:
                self.onEscape()
                return nil
            default:
                return event
            }
        }
    }

    /// 移除键盘监听。
    func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    /// 判断当前焦点是否在搜索框等文本编辑控件中，交给快捷键解析器决定是否截获数字。
    private static func isEditingText(in window: NSWindow) -> Bool {
        window.firstResponder is NSTextView
    }
}
