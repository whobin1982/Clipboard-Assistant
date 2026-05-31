import AppKit
import SwiftUI

struct ClipboardPopupView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            KeyEventHandlingView(
                onDownArrow: {
                    selectionController.moveDown(in: viewModel.filteredItems)
                },
                onUpArrow: {
                    selectionController.moveUp(in: viewModel.filteredItems)
                },
                onReturn: {
                    guard let item = selectionController.selectedItem(in: viewModel.filteredItems) else { return }
                    onPaste(item)
                },
                onEscape: {
                    if escapeClosesWindow {
                        onClose()
                    }
                }
            )
            .frame(width: 0, height: 0)

            HStack(spacing: 8) {
                Toggle("自动记录", isOn: isRecordingEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
                    .help(isRecordingPaused ? "点击后继续记录剪贴板" : "点击后暂停记录剪贴板")

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
                    .frame(minWidth: 160, maxWidth: 220)
            }

            if let message = viewModel.lastErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            if viewModel.filteredItems.isEmpty {
                ContentUnavailableView("暂无剪贴板记录", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                List(viewModel.filteredItems) { item in
                    ClipboardRowView(
                        item: item,
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
        .frame(minWidth: 420, minHeight: 320)
        .onAppear {
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

    private var isRecordingEnabled: Binding<Bool> {
        Binding(
            get: { !isRecordingPaused },
            set: { isRecordingPaused = !$0 }
        )
    }
}

private enum ClipboardClearConfirmation: Hashable, Identifiable {
    case nonFavorites
    case all

    var id: Self { self }

    var title: String {
        switch self {
        case .nonFavorites:
            return "清空非收藏记录？"
        case .all:
            return "清空全部记录？"
        }
    }

    var message: String {
        switch self {
        case .nonFavorites:
            return "这会删除所有没有标记为收藏的剪贴板记录。"
        case .all:
            return "这会删除所有剪贴板记录，包括收藏记录。"
        }
    }

    var confirmTitle: String {
        switch self {
        case .nonFavorites:
            return "清空非收藏记录"
        case .all:
            return "清空全部记录"
        }
    }
}

private struct KeyEventHandlingView: NSViewRepresentable {
    let onDownArrow: () -> Void
    let onUpArrow: () -> Void
    let onReturn: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> KeyEventMonitorView {
        let view = KeyEventMonitorView()
        updateNSView(view, context: context)
        view.installMonitor()
        return view
    }

    func updateNSView(_ nsView: KeyEventMonitorView, context: Context) {
        nsView.onDownArrow = onDownArrow
        nsView.onUpArrow = onUpArrow
        nsView.onReturn = onReturn
        nsView.onEscape = onEscape
    }

    static func dismantleNSView(_ nsView: KeyEventMonitorView, coordinator: ()) {
        nsView.removeMonitor()
    }
}

private final class KeyEventMonitorView: NSView {
    var onDownArrow: () -> Void = {}
    var onUpArrow: () -> Void = {}
    var onReturn: () -> Void = {}
    var onEscape: () -> Void = {}

    private var monitor: Any?

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

    func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
