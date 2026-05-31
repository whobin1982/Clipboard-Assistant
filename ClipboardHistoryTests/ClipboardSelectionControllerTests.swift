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

    /// 普通数字键必须交给搜索输入，不再作为快速选择。
    func testKeyboardShortcutLetsPlainNumbersStayInSearchInput() {
        let shortcut = ClipboardKeyboardShortcut.numberShortcut(
            keyCode: 18,
            modifierFlags: [],
            searchQuery: "",
            isTextEditing: true
        )

        XCTAssertNil(shortcut)
    }

    /// 不在文本输入状态时，普通数字也不应触发快速选择，避免和搜索输入规则不一致。
    func testKeyboardShortcutIgnoresPlainNumbersWhenNotEditingText() {
        let shortcut = ClipboardKeyboardShortcut.numberShortcut(
            keyCode: 19,
            modifierFlags: [],
            searchQuery: "订单",
            isTextEditing: false
        )

        XCTAssertNil(shortcut)
    }

    /// Command + 数字键才是快速选择快捷键，搜索框已有内容时也应生效。
    func testKeyboardShortcutUsesCommandNumberShortcut() {
        let shortcut = ClipboardKeyboardShortcut.numberShortcut(
            keyCode: 84,
            modifierFlags: [.command],
            searchQuery: "订单",
            isTextEditing: true
        )

        XCTAssertEqual(shortcut, 2)
    }

    /// Command + 小键盘数字同样可以快速选择对应记录。
    func testKeyboardShortcutUsesCommandNumberPadShortcut() {
        let shortcut = ClipboardKeyboardShortcut.numberShortcut(
            keyCode: 92,
            modifierFlags: [.command, .numericPad],
            searchQuery: "",
            isTextEditing: true
        )

        XCTAssertEqual(shortcut, 9)
    }

    /// 滚动后快捷编号应跟随当前可见行，而不是固定绑定列表最前面的 9 条。
    func testVisibleShortcutResolverUsesCurrentVisibleRows() {
        let offscreen = ClipboardItem.text("offscreen")
        let firstVisible = ClipboardItem.text("first visible")
        let secondVisible = ClipboardItem.text("second visible")
        let thirdVisible = ClipboardItem.text("third visible")
        let belowViewport = ClipboardItem.text("below")
        let items = [offscreen, firstVisible, secondVisible, thirdVisible, belowViewport]
        let frames = [
            ClipboardVisibleRowFrame(id: offscreen.id, minY: -90, maxY: -12),
            ClipboardVisibleRowFrame(id: firstVisible.id, minY: -8, maxY: 36),
            ClipboardVisibleRowFrame(id: secondVisible.id, minY: 38, maxY: 82),
            ClipboardVisibleRowFrame(id: thirdVisible.id, minY: 84, maxY: 128),
            ClipboardVisibleRowFrame(id: belowViewport.id, minY: 132, maxY: 176)
        ]

        let visibleIDs = ClipboardVisibleShortcutResolver.visibleIDs(
            rowFrames: frames,
            viewportHeight: 120,
            itemIDs: items.map(\.id)
        )
        let shortcutItems = ClipboardVisibleShortcutResolver.shortcutItems(visibleIDs: visibleIDs, items: items)

        XCTAssertEqual(visibleIDs, [firstVisible.id, secondVisible.id, thirdVisible.id])
        XCTAssertEqual(shortcutItems.map(\.id), [firstVisible.id, secondVisible.id, thirdVisible.id])
    }

    /// 视图刚打开、还没收到滚动位置信息时，快捷选择先退回当前列表前 9 条。
    func testVisibleShortcutResolverFallsBackBeforeGeometryUpdates() {
        let items = (1...12).map { ClipboardItem.text("item \($0)") }

        let shortcutItems = ClipboardVisibleShortcutResolver.shortcutItems(visibleIDs: [], items: items)

        XCTAssertEqual(shortcutItems.map(\.id), items.prefix(9).map(\.id))
    }
}
