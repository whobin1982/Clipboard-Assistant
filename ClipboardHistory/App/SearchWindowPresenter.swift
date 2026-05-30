import AppKit
import SwiftUI

@MainActor
final class SearchWindowPresenter {
    private var panel: NSPanel?

    func show(
        viewModel: ClipboardHistoryViewModel,
        onPaste: @escaping (ClipboardItem) -> Void,
        onCopy: @escaping (ClipboardItem) -> Void
    ) {
        let contentView = ClipboardPopupView(
            viewModel: viewModel,
            onPaste: onPaste,
            onCopy: onCopy
        )

        let panel = panel ?? makePanel()
        panel.contentViewController = NSHostingController(rootView: contentView)

        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Clipboard Search"
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace]
        panel.center()
        self.panel = panel
        return panel
    }
}
