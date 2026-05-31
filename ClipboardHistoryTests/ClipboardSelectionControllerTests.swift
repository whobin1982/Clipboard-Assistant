import XCTest
@testable import ClipboardHistory

/// 验证历史窗口键盘选择控制器的上下移动和过滤后修正逻辑。
final class ClipboardSelectionControllerTests: XCTestCase {
    /// 初始没有选择时，按向下键应选中第一条。
    func testStartsWithNoSelectionAndDownSelectsFirstItem() {
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")
        let controller = ClipboardSelectionController()

        controller.moveDown(in: [first, second])

        XCTAssertEqual(controller.selectedItemID, first.id)
    }

    /// 上下移动应被限制在列表边界内。
    func testUpAndDownMoveWithinBounds() {
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")
        let controller = ClipboardSelectionController()

        controller.moveDown(in: [first, second])
        controller.moveDown(in: [first, second])
        controller.moveDown(in: [first, second])
        XCTAssertEqual(controller.selectedItemID, second.id)

        controller.moveUp(in: [first, second])
        controller.moveUp(in: [first, second])
        XCTAssertEqual(controller.selectedItemID, first.id)
    }

    /// 搜索过滤导致选中项消失时，应清空选择。
    func testSelectedItemClearsWhenFilteredOut() {
        let first = ClipboardItem.text("first")
        let controller = ClipboardSelectionController()
        controller.moveDown(in: [first])

        controller.reconcileSelection(with: [])

        XCTAssertNil(controller.selectedItemID)
    }

    /// 数字键快捷选择使用当前可见列表的 1-9 顺序，并返回被选中的记录。
    func testNumberShortcutSelectsVisibleItemByOneBasedIndex() {
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")
        let third = ClipboardItem.text("third")
        let controller = ClipboardSelectionController()

        let selected = controller.selectNumberShortcut(2, in: [first, second, third])

        XCTAssertEqual(selected?.id, second.id)
        XCTAssertEqual(controller.selectedItemID, second.id)
    }

    /// 超出当前列表范围的数字键不应改变已有选择。
    func testNumberShortcutIgnoresOutOfRangeNumbers() {
        let first = ClipboardItem.text("first")
        let controller = ClipboardSelectionController()
        controller.moveDown(in: [first])

        let selected = controller.selectNumberShortcut(9, in: [first])

        XCTAssertNil(selected)
        XCTAssertEqual(controller.selectedItemID, first.id)
    }
}
