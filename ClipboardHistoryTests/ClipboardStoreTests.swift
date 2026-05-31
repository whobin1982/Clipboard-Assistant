import XCTest
@testable import ClipboardHistory

/// 验证 SQLiteClipboardStore 的基本读写、收藏和删除能力。
final class ClipboardStoreTests: XCTestCase {
    /// 插入文本记录后应能按原内容取回。
    func testInsertAndFetchTextItem() throws {
        let store = try SQLiteClipboardStore.temporary()
        let item = ClipboardItem.text("hello world", copiedAt: Date(timeIntervalSince1970: 100))

        try store.insert(item)
        let items = try store.fetchAll()

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].kind, .text)
        XCTAssertEqual(items[0].text, "hello world")
    }

    /// 收藏状态可更新，删除后记录应从数据库中移除。
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
