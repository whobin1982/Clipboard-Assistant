import AppKit
import SwiftUI

@MainActor
protocol SearchWindowPresenting: AnyObject {
    func show(
        viewModel: ClipboardHistoryViewModel,
        previousApplication: NSRunningApplication?,
        escapeClosesWindow: Bool,
        isRecordingPaused: Binding<Bool>,
        historyWindowStaysOpen: Binding<Bool>,
        historyWindowAlwaysOnTop: Binding<Bool>,
        onClose: @escaping () -> Void,
        onWindowBehaviorChanged: @escaping (Bool) -> Void,
        onOpenSettings: @escaping () -> Void,
        onClearNonFavorites: @escaping () -> Void,
        onClearAll: @escaping () -> Void,
        onPaste: @escaping (ClipboardItem) -> Void,
        onCopy: @escaping (ClipboardItem) -> Void,
        onDelete: @escaping (ClipboardItem) -> Void
    )
    func orderOut()
    func consumePreviousApplication() -> NSRunningApplication?
    func applyWindowBehavior(alwaysOnTop: Bool)
}

@MainActor
final class SearchWindowPresenter: NSObject, SearchWindowPresenting, NSWindowDelegate {
    private static let frameAutosaveName = NSWindow.FrameAutosaveName("ClipboardHistorySearchWindow")

    private var panel: NSPanel?
    private var previousApplication: NSRunningApplication?
    private var localMouseEventMonitor: Any?
    private var globalMouseEventMonitor: Any?
    private var historyWindowStaysOpen: Binding<Bool> = .constant(false)
    private var historyWindowAlwaysOnTop: Binding<Bool> = .constant(false)
    private var onWindowBehaviorChanged: (Bool) -> Void = { _ in }
    private weak var windowModeButton: NSPopUpButton?

    func show(
        viewModel: ClipboardHistoryViewModel,
        previousApplication: NSRunningApplication?,
        escapeClosesWindow: Bool,
        isRecordingPaused: Binding<Bool>,
        historyWindowStaysOpen: Binding<Bool>,
        historyWindowAlwaysOnTop: Binding<Bool>,
        onClose: @escaping () -> Void,
        onWindowBehaviorChanged: @escaping (Bool) -> Void,
        onOpenSettings: @escaping () -> Void,
        onClearNonFavorites: @escaping () -> Void,
        onClearAll: @escaping () -> Void,
        onPaste: @escaping (ClipboardItem) -> Void,
        onCopy: @escaping (ClipboardItem) -> Void,
        onDelete: @escaping (ClipboardItem) -> Void
    ) {
        capturePreviousApplication(fallback: previousApplication)
        self.historyWindowStaysOpen = historyWindowStaysOpen
        self.historyWindowAlwaysOnTop = historyWindowAlwaysOnTop
        self.onWindowBehaviorChanged = onWindowBehaviorChanged

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
        applyWindowBehavior(alwaysOnTop: historyWindowAlwaysOnTop.wrappedValue)
        updateWindowModeButtonSelection()

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
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "剪贴板历史"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .normal
        panel.minSize = NSSize(width: 520, height: 360)
        panel.delegate = self
        panel.collectionBehavior = [.moveToActiveSpace]
        panel.standardWindowButton(.zoomButton)?.isEnabled = false
        addWindowModeAccessory(to: panel)
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
            if self.effectiveHistoryWindowStaysOpen {
                return event
            }
            self.orderOut()
            return event
        }
        globalMouseEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard !self.effectiveHistoryWindowStaysOpen else { return }
                self.orderOut()
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

    private var effectiveHistoryWindowStaysOpen: Bool {
        historyWindowStaysOpen.wrappedValue || historyWindowAlwaysOnTop.wrappedValue
    }

    func applyWindowBehavior(alwaysOnTop: Bool) {
        panel?.level = alwaysOnTop ? .floating : .normal
    }

    private func addWindowModeAccessory(to panel: NSPanel) {
        let modeButton = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 86, height: 24), pullsDown: false)
        HistoryWindowMode.allCases.forEach { modeButton.addItem(withTitle: $0.title) }
        modeButton.controlSize = .small
        modeButton.toolTip = "窗口模式"
        modeButton.target = self
        modeButton.action = #selector(windowModeButtonChanged(_:))

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .left
        accessory.view = modeButton
        panel.addTitlebarAccessoryViewController(accessory)
        windowModeButton = modeButton
    }

    @objc private func windowModeButtonChanged(_ sender: NSPopUpButton) {
        guard let mode = HistoryWindowMode(title: sender.titleOfSelectedItem) else { return }
        applyWindowMode(mode)
    }

    private func applyWindowMode(_ mode: HistoryWindowMode) {
        switch mode {
        case .normal:
            historyWindowAlwaysOnTop.wrappedValue = false
            historyWindowStaysOpen.wrappedValue = false
        case .staysOpen:
            historyWindowAlwaysOnTop.wrappedValue = false
            historyWindowStaysOpen.wrappedValue = true
        case .alwaysOnTop:
            historyWindowAlwaysOnTop.wrappedValue = true
        }

        let alwaysOnTop = historyWindowAlwaysOnTop.wrappedValue
        applyWindowBehavior(alwaysOnTop: alwaysOnTop)
        onWindowBehaviorChanged(alwaysOnTop)
        updateWindowModeButtonSelection()
    }

    private func updateWindowModeButtonSelection() {
        windowModeButton?.selectItem(withTitle: currentWindowMode.title)
    }

    private var currentWindowMode: HistoryWindowMode {
        if historyWindowAlwaysOnTop.wrappedValue {
            return .alwaysOnTop
        }
        if historyWindowStaysOpen.wrappedValue {
            return .staysOpen
        }
        return .normal
    }
}

private enum HistoryWindowMode: CaseIterable {
    case normal
    case staysOpen
    case alwaysOnTop

    init?(title: String?) {
        switch title {
        case Self.normal.title:
            self = .normal
        case Self.staysOpen.title:
            self = .staysOpen
        case Self.alwaysOnTop.title:
            self = .alwaysOnTop
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .normal:
            return "普通"
        case .staysOpen:
            return "常驻"
        case .alwaysOnTop:
            return "置顶"
        }
    }
}
