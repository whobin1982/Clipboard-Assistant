import AppKit
import SwiftUI

@MainActor
protocol SearchWindowPresenting: AnyObject {
    func show(
        viewModel: ClipboardHistoryViewModel,
        previousApplication: NSRunningApplication?,
        escapeClosesWindow: Bool,
        isRecordingPaused: Binding<Bool>,
        recordingPauseState: RecordingPauseState,
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
    private static let minimumSize = NSSize(width: 520, height: 360)

    private var panel: NSPanel?
    private var previousApplication: NSRunningApplication?
    private var localMouseEventMonitor: Any?
    private var globalMouseEventMonitor: Any?
    private var historyWindowStaysOpen: Binding<Bool> = .constant(false)
    private var historyWindowAlwaysOnTop: Binding<Bool> = .constant(false)
    private var onWindowBehaviorChanged: (Bool) -> Void = { _ in }
    private var windowModeButtons: [HistoryWindowMode: NSButton] = [:]

    func show(
        viewModel: ClipboardHistoryViewModel,
        previousApplication: NSRunningApplication?,
        escapeClosesWindow: Bool,
        isRecordingPaused: Binding<Bool>,
        recordingPauseState: RecordingPauseState,
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
            recordingPauseState: recordingPauseState,
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
        enforceMinimumSize(on: panel)
        panel.setFrame(preservedFrame, display: false)
        enforceMinimumSize(on: panel)
        applyWindowBehavior(alwaysOnTop: historyWindowAlwaysOnTop.wrappedValue)
        updateWindowModeButtons()

        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        enforceMinimumSize(on: panel)
        panel.setFrame(preservedFrame, display: true)
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
        enforceMinimumSize(on: panel)
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

    private func enforceMinimumSize(on panel: NSPanel) {
        let minimumFrame = NSRect(origin: .zero, size: Self.minimumSize)
        panel.contentMinSize = panel.contentRect(forFrameRect: minimumFrame).size
        panel.minSize = Self.minimumSize
    }

    private var effectiveHistoryWindowStaysOpen: Bool {
        historyWindowStaysOpen.wrappedValue || historyWindowAlwaysOnTop.wrappedValue
    }

    func applyWindowBehavior(alwaysOnTop: Bool) {
        panel?.level = alwaysOnTop ? .floating : .normal
    }

    private func addWindowModeAccessory(to panel: NSPanel) {
        windowModeButtons.removeAll()

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 88, height: 24))
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 2

        HistoryWindowMode.allCases.forEach { mode in
            let button = NSButton(image: mode.image, target: self, action: #selector(windowModeButtonClicked(_:)))
            button.identifier = mode.identifier
            button.title = ""
            button.imagePosition = .imageOnly
            button.bezelStyle = .texturedRounded
            button.setButtonType(.toggle)
            button.controlSize = .small
            button.toolTip = mode.toolTip
            button.setAccessibilityLabel(mode.title)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 28),
                button.heightAnchor.constraint(equalToConstant: 24)
            ])
            stack.addArrangedSubview(button)
            windowModeButtons[mode] = button
        }

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .left
        accessory.view = stack
        panel.addTitlebarAccessoryViewController(accessory)
    }

    @objc private func windowModeButtonClicked(_ sender: NSButton) {
        guard let mode = HistoryWindowMode(identifier: sender.identifier) else { return }
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
            historyWindowStaysOpen.wrappedValue = true
            historyWindowAlwaysOnTop.wrappedValue = true
        }

        let alwaysOnTop = historyWindowAlwaysOnTop.wrappedValue
        applyWindowBehavior(alwaysOnTop: alwaysOnTop)
        onWindowBehaviorChanged(alwaysOnTop)
        updateWindowModeButtons()
    }

    private func updateWindowModeButtons() {
        let selectedMode = currentWindowMode
        for (mode, button) in windowModeButtons {
            let isSelected = mode == selectedMode
            button.image = isSelected ? mode.selectedImage : mode.image
            button.state = isSelected ? .on : .off
            button.contentTintColor = isSelected ? .controlAccentColor : .secondaryLabelColor
            button.setAccessibilityValue(isSelected ? "已选中" : "未选中")
        }
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

private enum HistoryWindowMode: CaseIterable, Hashable {
    case normal
    case staysOpen
    case alwaysOnTop

    init?(identifier: NSUserInterfaceItemIdentifier?) {
        switch identifier?.rawValue {
        case Self.normal.identifier.rawValue:
            self = .normal
        case Self.staysOpen.identifier.rawValue:
            self = .staysOpen
        case Self.alwaysOnTop.identifier.rawValue:
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

    var identifier: NSUserInterfaceItemIdentifier {
        switch self {
        case .normal:
            return NSUserInterfaceItemIdentifier("history-window-mode-normal")
        case .staysOpen:
            return NSUserInterfaceItemIdentifier("history-window-mode-stays-open")
        case .alwaysOnTop:
            return NSUserInterfaceItemIdentifier("history-window-mode-always-on-top")
        }
    }

    var toolTip: String {
        "\(title)窗口"
    }

    var image: NSImage {
        Self.makeImage(symbolName: symbolName, description: title)
    }

    var selectedImage: NSImage {
        Self.makeImage(symbolName: selectedSymbolName, description: "\(title)（已选中）")
    }

    private var symbolName: String {
        switch self {
        case .normal:
            return "macwindow"
        case .staysOpen:
            return "pin"
        case .alwaysOnTop:
            return "pin.fill"
        }
    }

    private var selectedSymbolName: String {
        switch self {
        case .normal:
            return "checkmark.rectangle.fill"
        case .staysOpen:
            return "pin.fill"
        case .alwaysOnTop:
            return "arrow.up.to.line.compact"
        }
    }

    private static func makeImage(symbolName: String, description: String) -> NSImage {
        NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
            ?? NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: description)
            ?? NSImage(size: NSSize(width: 16, height: 16))
    }
}
