import Foundation
import XCTest
@testable import ClipboardHistory

final class RetentionCleanerTests: XCTestCase {
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
}

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
