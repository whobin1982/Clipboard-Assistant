import Foundation
import XCTest
@testable import ClipboardHistory

/// 验证保留期清理只删除过期且未收藏的记录。
final class RetentionCleanerTests: XCTestCase {
    /// 超过保留期的非收藏记录会被删除，收藏和近期记录会保留。
    func testRunDeletesOnlyNonFavoritesOlderThanRetentionCutoff() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let oldDate = now.addingTimeInterval(-31 * 24 * 60 * 60)
        let recentDate = now.addingTimeInterval(-5 * 24 * 60 * 60)
        var oldFavorite = ClipboardItem.text("favorite", copiedAt: oldDate)
        oldFavorite.isFavorite = true
        let oldRegular = ClipboardItem.text("old", copiedAt: oldDate)
        let recentRegular = ClipboardItem.text("recent", copiedAt: recentDate)
        let store = RetentionCleanerFakeStore(items: [oldFavorite, oldRegular, recentRegular])
        let cleaner = RetentionCleaner(store: store)

        try cleaner.run(
            now: now,
            settings: AppSettings(retentionDays: 30, launchAtLogin: false, shortcutDisplayName: "")
        )

        let remainingIDs = try store.fetchAll().map(\.id)
        XCTAssertEqual(store.deletedOlderThan, now.addingTimeInterval(-30 * 24 * 60 * 60))
        XCTAssertEqual(remainingIDs, [oldFavorite.id, recentRegular.id])
    }

    /// 永久保留策略不会触发删除。
    func testRunKeepsAllItemsWhenRetentionIsForever() throws {
        let oldItem = ClipboardItem.text("old", copiedAt: Date(timeIntervalSince1970: 0))
        let store = RetentionCleanerFakeStore(items: [oldItem])
        let cleaner = RetentionCleaner(store: store)
        var settings = AppSettings.default
        settings.retentionPolicy = .forever

        try cleaner.run(now: Date(timeIntervalSince1970: 10_000_000), settings: settings)

        XCTAssertNil(store.deletedOlderThan)
        XCTAssertEqual(try store.fetchAll().map(\.id), [oldItem.id])
    }
}

/// RetentionCleaner 测试用存储，记录删除 cutoff 并模拟删除结果。
private final class RetentionCleanerFakeStore: ClipboardStore {
    private var items: [ClipboardItem]
    private(set) var deletedOlderThan: Date?

    init(items: [ClipboardItem]) {
        self.items = items
    }

    func insert(_ item: ClipboardItem) throws {
        items.append(item)
    }

    func fetchAll() throws -> [ClipboardItem] {
        items
    }

    func setFavorite(id: UUID, isFavorite: Bool) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isFavorite = isFavorite
    }

    func delete(id: UUID) throws {
        items.removeAll { $0.id == id }
    }

    func deleteNonFavorites(olderThan cutoff: Date) throws {
        deletedOlderThan = cutoff
        items.removeAll { !$0.isFavorite && $0.copiedAt < cutoff }
    }

    func deleteAll(includeFavorites: Bool) throws {
        items.removeAll { includeFavorites || !$0.isFavorite }
    }
}
