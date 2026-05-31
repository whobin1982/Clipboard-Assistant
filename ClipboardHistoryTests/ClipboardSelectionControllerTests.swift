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

    /// 搜索框为空时，即使焦点在搜索框里，数字键也应优先作为快速选择。
    func testKeyboardShortcutUsesNumberWhenSearchFieldIsEmpty() {
        let shortcut = ClipboardKeyboardShortcut.numberShortcut(
            keyCode: 18,
            modifierFlags: [],
            searchQuery: "",
            isTextEditing: true
        )

        XCTAssertEqual(shortcut, 1)
    }

    /// 搜索框已有内容时，数字键应继续交给搜索框输入，方便搜索含数字的内容。
    func testKeyboardShortcutLetsSearchFieldKeepNumbersWhenQueryIsNotEmpty() {
        let shortcut = ClipboardKeyboardShortcut.numberShortcut(
            keyCode: 19,
            modifierFlags: [],
            searchQuery: "订单",
            isTextEditing: true
        )

        XCTAssertNil(shortcut)
    }

    /// 只要不在文本输入状态，数字键应始终作为快速选择。
    func testKeyboardShortcutUsesNumberWhenNotEditingText() {
        let shortcut = ClipboardKeyboardShortcut.numberShortcut(
            keyCode: 84,
            modifierFlags: [],
            searchQuery: "订单",
            isTextEditing: false
        )

        XCTAssertEqual(shortcut, 2)
    }
}
