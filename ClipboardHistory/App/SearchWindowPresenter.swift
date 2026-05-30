import AppKit
import SwiftUI

@MainActor
protocol SearchWindowPresenting: AnyObject {
    func show(
        viewModel: ClipboardHistoryViewModel,
        onPaste: @escaping (ClipboardItem) -> Void,
        onCopy: @escaping (ClipboardItem) -> Void,
        onDelete: @escaping (ClipboardItem) -> Void
    )
    func orderOut()
    func reactivatePreviousApplication()
}

@MainActor
final class SearchWindowPresenter: SearchWindowPresenting {
    private var panel: NSPanel?
    private var previousApplication: NSRunningApplication?

    func show(
        viewModel: ClipboardHistoryViewModel,
        onPaste: @escaping (ClipboardItem) -> Void,
        onCopy: @escaping (ClipboardItem) -> Void,
        onDelete: @escaping (ClipboardItem) -> Void
    ) {
        capturePreviousApplication()

        let contentView = ClipboardPopupView(
            viewModel: viewModel,
            onPaste: onPaste,
            onCopy: onCopy,
            onDelete: onDelete
        )

        let panel = panel ?? makePanel()
        panel.contentViewController = NSHostingController(rootView: contentView)

        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func orderOut() {
        panel?.orderOut(nil)
    }

    func reactivatePreviousApplication() {
        if #available(macOS 14.0, *) {
            previousApplication?.activate()
        } else {
            previousApplication?.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func capturePreviousApplication() {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        if frontmostApplication?.processIdentifier == NSRunningApplication.current.processIdentifier {
            previousApplication = nil
        } else {
            previousApplication = frontmostApplication
        }
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
