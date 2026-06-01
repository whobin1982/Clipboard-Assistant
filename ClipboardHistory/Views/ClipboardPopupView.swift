import AppKit
import SwiftUI

/// 剪贴板历史弹窗主视图，包含工具栏、搜索框、记录列表和键盘选择逻辑。
struct ClipboardPopupView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    @ObservedObject var recordingPauseState: RecordingPauseState
    @StateObject private var selectionController = ClipboardSelectionController()
    @State private var clearConfirmation: ClipboardClearConfirmation?
    @State private var visibleRowFrames: [ClipboardVisibleRowFrame] = []
    @State private var scrollOffsetY: CGFloat = 0
    @State private var listViewportHeight: CGFloat = 0

    private static let historyListContentCoordinateSpace = "clipboardHistoryListContent"

    var escapeClosesWindow: Bool
    @Binding var isRecordingPaused: Bool
    var onClose: () -> Void
    var onOpenSettings: () -> Void
    var onClearNonFavorites: () -> Void
    var onClearAll: () -> Void
    var onPaste: (ClipboardItem) -> Void
    var onCopy: (ClipboardItem) -> Void
    var onCopyImageText: (ClipboardItem) -> Void
    var onExportImage: (ClipboardItem) -> Void
    var onDelete: (ClipboardItem) -> Void

    /// 弹窗内容布局：顶部操作栏，中间错误或空状态，底部历史列表。
    var body: some View {
        let visibleItems = viewModel.filteredItems
        let visibleShortcutItemIDs = ClipboardVisibleShortcutResolver.visibleIDs(
            rowFrames: visibleRowFrames,
            scrollOffsetY: scrollOffsetY,
            viewportHeight: listViewportHeight,
            itemIDs: visibleItems.map(\.id)
        )
        let allowsInitialShortcutFallback = listViewportHeight <= 0

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
                    let shortcutItems = ClipboardVisibleShortcutResolver.shortcutItems(
                        visibleIDs: visibleShortcutItemIDs,
                        items: visibleItems,
                        allowsFallback: allowsInitialShortcutFallback
                    )
                    guard let item = selectionController.selectNumberShortcut(number, in: shortcutItems) else { return }
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
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                                ClipboardRowView(
                                    item: item,
                                    shortcutNumber: shortcutNumber(
                                        for: item.id,
                                        visibleShortcutItemIDs: visibleShortcutItemIDs,
                                        allowsFallback: allowsInitialShortcutFallback,
                                        fallbackIndex: index
                                    ),
                                    isSelected: selectionController.selectedItemID == item.id,
                                    onFavorite: { viewModel.toggleFavorite(item) },
                                    onDelete: { onDelete(item) },
                                    onPaste: { onPaste(item) },
                                    onCopy: { onCopy(item) },
                                    onCopyImageText: { onCopyImageText(item) },
                                    onExportImage: { onExportImage(item) }
                                )
                                .id(item.id)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    ClipboardVisibleRowReporter(
                                        itemID: item.id,
                                        coordinateSpaceName: Self.historyListContentCoordinateSpace
                                    )
                                )

                                if index < visibleItems.index(before: visibleItems.endIndex) {
                                    Divider()
                                }
                            }
                        }
                        .coordinateSpace(name: Self.historyListContentCoordinateSpace)
                        .background(
                            ClipboardScrollPositionObserver { offsetY, viewportHeight in
                                updateScrollPosition(offsetY: offsetY, viewportHeight: viewportHeight)
                            }
                        )
                    }
                    .frame(minHeight: 180)
                    .onChange(of: selectionController.selectedItemID) { _, selectedItemID in
                        scrollToSelectedItem(selectedItemID, proxy: proxy)
                    }
                }
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
        .onPreferenceChange(ClipboardVisibleRowFramesPreferenceKey.self) { frames in
            visibleRowFrames = frames
        }
    }

    /// 键盘上下键改变选中项时，让滚动区域自动跟随到当前记录。
    private func scrollToSelectedItem(_ selectedItemID: UUID?, proxy: ScrollViewProxy) {
        guard let selectedItemID else {
            return
        }

        withAnimation(.easeInOut(duration: 0.12)) {
            proxy.scrollTo(selectedItemID, anchor: .center)
        }
    }

    /// 界面显示“自动记录”，底层存储的是“是否暂停”，因此这里反向绑定。
    private var isRecordingEnabled: Binding<Bool> {
        Binding(
            get: { !recordingPauseState.isPaused },
            set: { isRecordingPaused = !$0 }
        )
    }

    /// 根据当前滚动位置为可见记录分配快捷键编号。
    private func shortcutNumber(
        for itemID: UUID,
        visibleShortcutItemIDs: [UUID],
        allowsFallback: Bool,
        fallbackIndex: Int
    ) -> Int? {
        if let visibleIndex = visibleShortcutItemIDs.firstIndex(of: itemID) {
            return visibleIndex + 1
        }

        guard allowsFallback, visibleShortcutItemIDs.isEmpty, fallbackIndex < 9 else { return nil }
        return fallbackIndex + 1
    }

    /// 接收原生滚动视图的真实滚动位置，避免 SwiftUI 布局偏好在 macOS 滚动时不刷新的问题。
    private func updateScrollPosition(offsetY: CGFloat, viewportHeight: CGFloat) {
        let normalizedOffsetY = max(0, offsetY)
        guard
            abs(scrollOffsetY - normalizedOffsetY) > 0.5 ||
            abs(listViewportHeight - viewportHeight) > 0.5
        else {
            return
        }

        scrollOffsetY = normalizedOffsetY
        listViewportHeight = viewportHeight
    }
}

/// 汇总每一行相对历史列表可见区域的位置。
private struct ClipboardVisibleRowFramesPreferenceKey: PreferenceKey {
    static var defaultValue: [ClipboardVisibleRowFrame] = []

    static func reduce(value: inout [ClipboardVisibleRowFrame], nextValue: () -> [ClipboardVisibleRowFrame]) {
        value.append(contentsOf: nextValue())
    }
}

/// 记录历史列表视口高度，用来判断哪些行当前可见。
private struct ClipboardListViewportHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 给单行记录上报当前位置，不参与实际绘制。
private struct ClipboardVisibleRowReporter: View {
    let itemID: UUID
    let coordinateSpaceName: String

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(coordinateSpaceName))

            Color.clear.preference(
                key: ClipboardVisibleRowFramesPreferenceKey.self,
                value: [
                    ClipboardVisibleRowFrame(
                        id: itemID,
                        minY: frame.minY,
                        maxY: frame.maxY
                    )
                ]
            )
        }
    }
}

/// 观察 SwiftUI ScrollView 底层 NSScrollView 的滚动位置，让快捷编号能跟随真实滚动偏移更新。
private struct ClipboardScrollPositionObserver: NSViewRepresentable {
    let onScrollChange: (CGFloat, CGFloat) -> Void

    func makeNSView(context _: Context) -> ClipboardScrollPositionObserverView {
        let view = ClipboardScrollPositionObserverView()
        view.onScrollChange = onScrollChange
        return view
    }

    func updateNSView(_ nsView: ClipboardScrollPositionObserverView, context _: Context) {
        nsView.onScrollChange = onScrollChange
        DispatchQueue.main.async {
            nsView.attachToEnclosingScrollView()
        }
    }

    static func dismantleNSView(_ nsView: ClipboardScrollPositionObserverView, coordinator _: ()) {
        nsView.stopObserving()
    }
}

/// 放在滚动内容里的透明 NSView，负责监听 NSClipView 的 bounds 改变。
private final class ClipboardScrollPositionObserverView: NSView {
    var onScrollChange: (CGFloat, CGFloat) -> Void = { _, _ in }

    private weak var observedScrollView: NSScrollView?
    private var boundsObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.attachToEnclosingScrollView()
        }
    }

    deinit {
        stopObserving()
    }

    /// 找到 SwiftUI ScrollView 创建的 NSScrollView，并监听其可见区域变化。
    func attachToEnclosingScrollView() {
        guard let scrollView = enclosingScrollView ?? firstAncestor(of: NSScrollView.self) else { return }

        if observedScrollView === scrollView {
            reportScrollPosition()
            return
        }

        stopObserving()
        observedScrollView = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.reportScrollPosition()
        }
        reportScrollPosition()
    }

    /// 停止监听旧的滚动视图，避免窗口重建后继续收到过期通知。
    func stopObserving() {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
            self.boundsObserver = nil
        }
        observedScrollView = nil
    }

    /// 把 AppKit 的滚动偏移和视口高度回传给 SwiftUI 状态。
    private func reportScrollPosition() {
        guard let scrollView = observedScrollView else { return }
        let bounds = scrollView.contentView.bounds
        let offsetY = bounds.minY
        let viewportHeight = bounds.height

        DispatchQueue.main.async { [weak self] in
            self?.onScrollChange(offsetY, viewportHeight)
        }
    }
}

private extension NSView {
    /// 在 SwiftUI 包装层级变化时，兜底向上寻找指定类型的 AppKit 父视图。
    func firstAncestor<T: NSView>(of type: T.Type) -> T? {
        var currentView = superview
        while let view = currentView {
            if let match = view as? T {
                return match
            }
            currentView = view.superview
        }
        return nil
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
