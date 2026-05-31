import AppKit
import SwiftUI

struct ClipboardPopupView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    @StateObject private var selectionController = ClipboardSelectionController()

    var escapeClosesWindow: Bool
    var onClose: () -> Void
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

            TextField("搜索剪贴板历史", text: $viewModel.query)
                .textFieldStyle(.roundedBorder)

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
        .onChange(of: viewModel.filteredItems.map(\.id)) { _, _ in
            selectionController.reconcileSelection(with: viewModel.filteredItems)
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
