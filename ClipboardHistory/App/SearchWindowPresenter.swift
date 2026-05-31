import AppKit
import SwiftUI

@MainActor
protocol SearchWindowPresenting: AnyObject {
    func show(
        viewModel: ClipboardHistoryViewModel,
        previousApplication: NSRunningApplication?,
        escapeClosesWindow: Bool,
        isRecordingPaused: Binding<Bool>,
        onClose: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onClearNonFavorites: @escaping () -> Void,
        onClearAll: @escaping () -> Void,
        onPaste: @escaping (ClipboardItem) -> Void,
        onCopy: @escaping (ClipboardItem) -> Void,
        onDelete: @escaping (ClipboardItem) -> Void
    )
    func orderOut()
    func consumePreviousApplication() -> NSRunningApplication?
}

@MainActor
final class SearchWindowPresenter: NSObject, SearchWindowPresenting, NSWindowDelegate {
    private static let frameAutosaveName = NSWindow.FrameAutosaveName("ClipboardHistorySearchWindow")

    private var panel: NSPanel?
    private var previousApplication: NSRunningApplication?
    private var localMouseEventMonitor: Any?
    private var globalMouseEventMonitor: Any?

    func show(
        viewModel: ClipboardHistoryViewModel,
        previousApplication: NSRunningApplication?,
        escapeClosesWindow: Bool,
        isRecordingPaused: Binding<Bool>,
        onClose: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onClearNonFavorites: @escaping () -> Void,
        onClearAll: @escaping () -> Void,
        onPaste: @escaping (ClipboardItem) -> Void,
        onCopy: @escaping (ClipboardItem) -> Void,
        onDelete: @escaping (ClipboardItem) -> Void
    ) {
        capturePreviousApplication(fallback: previousApplication)

        let contentView = ClipboardPopupView(
            viewModel: viewModel,
            escapeClosesWindow: escapeClosesWindow,
            isRecordingPaused: isRecordingPaused,
            onClose: onClose,
            onOpenSettings: onOpenSettings,
            onClearNonFavorites: onClearNonFavorites,
            onClearAll: onClearAll,
            onPaste: onPaste,
            onCopy: onCopy,
            onDelete: onDelete
        )

        let panel = panel ?? makePanel()
        let preservedFrame = panel.frame
        panel.contentViewController = NSHostingController(rootView: contentView)
        panel.setFrame(preservedFrame, display: false)

        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        installOutsideClickMonitors()
    }

    func orderOut() {
        saveWindowFrame()
        panel?.orderOut(nil)
        removeOutsideClickMonitors()
    }

    func consumePreviousApplication() -> NSRunningApplication? {
        defer { previousApplication = nil }
        return previousApplication
    }

    func windowDidMove(_ notification: Notification) {
        saveWindowFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveWindowFrame()
    }

    private func capturePreviousApplication(fallback: NSRunningApplication?) {
        let frontmostApplication = fallback ?? NSWorkspace.shared.frontmostApplication
        if frontmostApplication?.processIdentifier == NSRunningApplication.current.processIdentifier {
            previousApplication = nil
        } else {
            previousApplication = frontmostApplication
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "剪贴板历史"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.minSize = NSSize(width: 420, height: 360)
        panel.delegate = self
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        if !panel.setFrameUsingName(Self.frameAutosaveName) {
            panel.center()
        }
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        self.panel = panel
        return panel
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()

        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            guard let self else { return event }
            guard self.panel?.isVisible == true else { return event }
            if event.window === self.panel {
                return event
            }
            self.orderOut()
            return event
        }
        globalMouseEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
            Task { @MainActor in
                self?.orderOut()
            }
        }
    }

    private func removeOutsideClickMonitors() {
        if let localMouseEventMonitor {
            NSEvent.removeMonitor(localMouseEventMonitor)
            self.localMouseEventMonitor = nil
        }
        if let globalMouseEventMonitor {
            NSEvent.removeMonitor(globalMouseEventMonitor)
            self.globalMouseEventMonitor = nil
        }
    }

    private func saveWindowFrame() {
        panel?.saveFrame(usingName: Self.frameAutosaveName)
    }
}
