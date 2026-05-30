import XCTest
@testable import ClipboardHistory

final class ClipboardStoreTests: XCTestCase {
    func testInsertAndFetchTextItem() throws {
        let store = try SQLiteClipboardStore.temporary()
        let item = ClipboardItem.text("hello world", copiedAt: Date(timeIntervalSince1970: 100))

        try store.insert(item)
        let items = try store.fetchAll()

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].kind, .text)
        XCTAssertEqual(items[0].text, "hello world")
    }

    func testFavoriteAndDeleteItem() throws {
        let store = try SQLiteClipboardStore.temporary()
        let item = ClipboardItem.text("keep me")

        try store.insert(item)
        try store.setFavorite(id: item.id, isFavorite: true)
        XCTAssertEqual(try store.fetchAll()[0].isFavorite, true)

        try store.delete(id: item.id)
        XCTAssertTrue(try store.fetchAll().isEmpty)
    }
}
