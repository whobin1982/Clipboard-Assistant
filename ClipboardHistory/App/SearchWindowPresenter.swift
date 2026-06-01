import AppKit
import SwiftUI

/// 历史记录窗口展示接口，用于把窗口行为和业务环境解耦，方便测试注入。
@MainActor
protocol SearchWindowPresenting: AnyObject {
    /// 展示历史窗口，并传入窗口内所有需要的状态绑定和操作回调。
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
        onCopyImageText: @escaping (ClipboardItem) -> Void,
        onExportImage: @escaping (ClipboardItem) -> Void,
        onDelete: @escaping (ClipboardItem) -> Void
    )
    /// 隐藏历史窗口，同时保存窗口位置和尺寸。
    func orderOut()
    /// 取出并清空呼出窗口前的前台应用，用于选中记录后切回原应用。
    func consumePreviousApplication() -> NSRunningApplication?
    /// 应用置顶状态。
    func applyWindowBehavior(alwaysOnTop: Bool)
}

/// 用 AppKit NSPanel 承载 SwiftUI 历史列表，并处理窗口位置、外部点击关闭和标题栏模式按钮。
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

    /// 创建或复用历史窗口，刷新 SwiftUI 内容，并恢复上次保存的位置和尺寸。
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
        onCopyImageText: @escaping (ClipboardItem) -> Void,
        onExportImage: @escaping (ClipboardItem) -> Void,
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
            onCopyImageText: onCopyImageText,
            onExportImage: onExportImage,
            onDelete: onDelete
        )

        let panel = panel ?? makePanel()
        let preservedFrame = panel.frame
        panel.contentViewController = NSHostingController(rootView: contentView)
        // 更换 contentViewController 时 AppKit 可能重新计算窗口尺寸，所以这里主动恢复旧 frame。
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

    /// 隐藏历史窗口并移除事件监听，避免窗口不可见时仍拦截鼠标事件。
    func orderOut() {
        saveWindowFrame()
        panel?.orderOut(nil)
        removeOutsideClickMonitors()
    }

    /// 自动粘贴只能消费一次前台应用，防止后续操作误切到旧应用。
    func consumePreviousApplication() -> NSRunningApplication? {
        defer { previousApplication = nil }
        return previousApplication
    }

    /// 拖动窗口后立即保存 frame，保证下次打开位置正确。
    func windowDidMove(_ notification: Notification) {
        saveWindowFrame()
    }

    /// 用户结束缩放窗口时保存尺寸。
    func windowDidEndLiveResize(_ notification: Notification) {
        saveWindowFrame()
    }

    /// 捕获呼出窗口前的前台应用；如果当前前台就是自己，则不保存粘贴目标。
    private func capturePreviousApplication(fallback: NSRunningApplication?) {
        let frontmostApplication = fallback ?? NSWorkspace.shared.frontmostApplication
        if frontmostApplication?.processIdentifier == NSRunningApplication.current.processIdentifier {
            previousApplication = nil
        } else {
            previousApplication = frontmostApplication
        }
    }

    /// 创建历史记录面板，禁用最大化，并添加自定义窗口模式按钮。
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

    /// 安装本地和全局鼠标监听，实现“点击窗口外关闭”。
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

    /// 清理鼠标监听，防止重复安装或窗口关闭后泄漏。
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

    /// 保存当前窗口 frame 到系统自动保存名。
    private func saveWindowFrame() {
        panel?.saveFrame(usingName: Self.frameAutosaveName)
    }

    /// 同时设置 frame 和 content 的最小尺寸，避免 SwiftUI 内容把窗口压到不可用。
    private func enforceMinimumSize(on panel: NSPanel) {
        let minimumFrame = NSRect(origin: .zero, size: Self.minimumSize)
        panel.contentMinSize = panel.contentRect(forFrameRect: minimumFrame).size
        panel.minSize = Self.minimumSize
    }

    /// 置顶状态天然要求常驻，因此对外部点击关闭而言也算常驻。
    private var effectiveHistoryWindowStaysOpen: Bool {
        historyWindowStaysOpen.wrappedValue || historyWindowAlwaysOnTop.wrappedValue
    }

    /// 切换窗口层级，置顶时使用 floating，普通时回到 normal。
    func applyWindowBehavior(alwaysOnTop: Bool) {
        panel?.level = alwaysOnTop ? .floating : .normal
    }

    /// 在标题栏左侧添加普通、常驻、置顶三个独立图标按钮。
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

    /// 标题栏模式按钮点击入口。
    @objc private func windowModeButtonClicked(_ sender: NSButton) {
        guard let mode = HistoryWindowMode(identifier: sender.identifier) else { return }
        applyWindowMode(mode)
    }

    /// 应用窗口模式；置顶模式会同时打开常驻，因为置顶窗口不应点击外部就关闭。
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

    /// 根据当前模式刷新三个按钮的选中图标、状态和辅助功能描述。
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

    /// 将两个布尔设置折算成界面上的三种互斥模式。
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

/// 历史窗口模式：普通、常驻、置顶。界面上用三个独立图标表示，而不是循环切换。
private enum HistoryWindowMode: CaseIterable, Hashable {
    case normal
    case staysOpen
    case alwaysOnTop

    /// 通过按钮 identifier 反查模式。
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

    /// 用户可见的模式名称。
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

    /// 每个按钮固定使用独立 identifier，便于点击时定位模式。
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

    /// 鼠标悬停提示。
    var toolTip: String {
        "\(title)窗口"
    }

    /// 未选中状态图标。
    var image: NSImage {
        Self.makeImage(symbolName: symbolName, description: title)
    }

    /// 选中状态图标。
    var selectedImage: NSImage {
        Self.makeImage(symbolName: selectedSymbolName, description: "\(title)（已选中）")
    }

    /// 未选中状态使用的 SF Symbol 名称。
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

    /// 选中状态使用更醒目的 SF Symbol 名称。
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

    /// 创建系统符号图标，缺失时用通用图标兜底。
    private static func makeImage(symbolName: String, description: String) -> NSImage {
        NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
            ?? NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: description)
            ?? NSImage(size: NSSize(width: 16, height: 16))
    }
}
