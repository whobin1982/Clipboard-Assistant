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
