import AppKit
import SwiftUI
import XCTest
@testable import ClipboardHistory

/// 验证历史记录弹窗的视图结构，避免滚动可见行计算再次退回到原生表格实现。
@MainActor
final class ClipboardPopupViewTests: XCTestCase {
    /// 历史列表不能使用 macOS NSTableView，否则 SwiftUI 行位置偏好不会随滚动稳定刷新。
    func testHistoryListAvoidsNSTableViewSoVisibleShortcutGeometryCanTrackScrolling() throws {
        let store = try SQLiteClipboardStore.temporary()
        for index in 1...12 {
            try store.insert(.text("item \(index)"))
        }
        let viewModel = ClipboardHistoryViewModel(store: store)
        viewModel.reload()

        let rootView = ClipboardPopupView(
            viewModel: viewModel,
            recordingPauseState: RecordingPauseState(isPaused: false),
            escapeClosesWindow: true,
            isRecordingPaused: .constant(false),
            onClose: {},
            onOpenSettings: {},
            onClearNonFavorites: {},
            onClearAll: {},
            onPaste: { _ in },
            onCopy: { _ in },
            onDelete: { _ in }
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 620, height: 420)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView

        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertNil(
            hostingView.firstDescendant(of: NSTableView.self),
            "历史列表需要使用 SwiftUI ScrollView/LazyVStack，才能让可见行编号跟随滚动刷新。"
        )
    }

    /// 连续按下方向键选择下面的记录时，滚动视图应跟随选中项向下滚动。
    func testKeyboardSelectionScrollsHistoryListToSelectedRow() throws {
        let store = try SQLiteClipboardStore.temporary()
        for index in 1...40 {
            try store.insert(.text("item \(index)", copiedAt: Date(timeIntervalSince1970: TimeInterval(index))))
        }
        let viewModel = ClipboardHistoryViewModel(store: store)
        viewModel.reload()

        let rootView = ClipboardPopupView(
            viewModel: viewModel,
            recordingPauseState: RecordingPauseState(isPaused: false),
            escapeClosesWindow: true,
            isRecordingPaused: .constant(false),
            onClose: {},
            onOpenSettings: {},
            onClearNonFavorites: {},
            onClearAll: {},
            onPaste: { _ in },
            onCopy: { _ in },
            onDelete: { _ in }
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 620, height: 360)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        let scrollView = try XCTUnwrap(hostingView.firstDescendant(of: NSScrollView.self))
        let initialOffset = scrollView.contentView.bounds.minY

        for _ in 0..<24 {
            NSApp.sendEvent(try XCTUnwrap(keyDownEvent(keyCode: 125, window: window)))
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))

        XCTAssertGreaterThan(scrollView.contentView.bounds.minY, initialOffset + 10)
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        if let match = self as? T {
            return match
        }

        for subview in subviews {
            if let match = subview.firstDescendant(of: type) {
                return match
            }
        }

        return nil
    }
}

private func keyDownEvent(keyCode: UInt16, window: NSWindow) -> NSEvent? {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        characters: "",
        charactersIgnoringModifiers: "",
        isARepeat: false,
        keyCode: keyCode
    )
}
