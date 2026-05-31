import XCTest
@testable import ClipboardHistory

final class ClipboardSelectionControllerTests: XCTestCase {
    func testStartsWithNoSelectionAndDownSelectsFirstItem() {
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")
        let controller = ClipboardSelectionController()

        controller.moveDown(in: [first, second])

        XCTAssertEqual(controller.selectedItemID, first.id)
    }

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

    func testSelectedItemClearsWhenFilteredOut() {
        let first = ClipboardItem.text("first")
        let controller = ClipboardSelectionController()
        controller.moveDown(in: [first])

        controller.reconcileSelection(with: [])

        XCTAssertNil(controller.selectedItemID)
    }
}
