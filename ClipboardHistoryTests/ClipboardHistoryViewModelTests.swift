import Foundation
import XCTest
@testable import ClipboardHistory

@MainActor
final class ClipboardHistoryViewModelTests: XCTestCase {
    func testFilteredItemsSearchesTextAndKeepsEmptyQueryAsAllItems() throws {
        let matchingText = ClipboardItem.text("Project Quote", copiedAt: Date(timeIntervalSince1970: 30))
        let nonmatchingText = ClipboardItem.text("Invoice", copiedAt: Date(timeIntervalSince1970: 20))
        let image = ClipboardItem.image(
            imagePath: "/tmp/project.png",
            thumbnailPath: "/tmp/project-thumb.png",
            copiedAt: Date(timeIntervalSince1970: 10)
        )
        let store = ClipboardHistoryViewModelFakeStore(items: [matchingText, image, nonmatchingText])
        let viewModel = ClipboardHistoryViewModel(store: store)

        viewModel.reload()
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [matchingText.id, image.id, nonmatchingText.id])

        viewModel.query = "project"
        XCTAssertEqual(viewModel.filteredItems.map(\.id), [matchingText.id])
    }

    func testToggleFavoriteUpdatesStoreAndReloadsItemsInFetchOrder() throws {
        let first = ClipboardItem.text("first", copiedAt: Date(timeIntervalSince1970: 30))
        let second = ClipboardItem.text("second", copiedAt: Date(timeIntervalSince1970: 20))
        let store = ClipboardHistoryViewModelFakeStore(items: [first, second])
        let viewModel = ClipboardHistoryViewModel(store: store)

        viewModel.reload()
        viewModel.toggleFavorite(second)

        XCTAssertEqual(store.favoriteUpdates.count, 1)
        XCTAssertEqual(store.favoriteUpdates.first?.id, second.id)
        XCTAssertEqual(store.favoriteUpdates.first?.isFavorite, true)
        XCTAssertEqual(viewModel.items.map(\.id), [first.id, second.id])
        XCTAssertEqual(viewModel.items.first(where: { $0.id == second.id })?.isFavorite, true)
    }

    func testDeleteRemovesRecordAndReloadsItems() throws {
        let first = ClipboardItem.text("first", copiedAt: Date(timeIntervalSince1970: 30))
        let second = ClipboardItem.text("second", copiedAt: Date(timeIntervalSince1970: 20))
        let store = ClipboardHistoryViewModelFakeStore(items: [first, second])
        let viewModel = ClipboardHistoryViewModel(store: store)

        viewModel.reload()
        viewModel.delete(first)

        XCTAssertEqual(store.deletedIDs, [first.id])
        XCTAssertEqual(viewModel.items.map(\.id), [second.id])
    }
}

private final class ClipboardHistoryViewModelFakeStore: ClipboardStore {
    private var storedItems: [ClipboardItem]
    private(set) var favoriteUpdates: [(id: UUID, isFavorite: Bool)] = []
    private(set) var deletedIDs: [UUID] = []

    init(items: [ClipboardItem]) {
        storedItems = items
    }

    func insert(_ item: ClipboardItem) throws {
        storedItems.append(item)
    }

    func fetchAll() throws -> [ClipboardItem] {
        storedItems
    }

    func setFavorite(id: UUID, isFavorite: Bool) throws {
        favoriteUpdates.append((id, isFavorite))
        guard let index = storedItems.firstIndex(where: { $0.id == id }) else { return }
        storedItems[index].isFavorite = isFavorite
    }

    func delete(id: UUID) throws {
        deletedIDs.append(id)
        storedItems.removeAll { $0.id == id }
    }

    func deleteNonFavorites(olderThan cutoff: Date) throws {
        storedItems.removeAll { !$0.isFavorite && $0.copiedAt < cutoff }
    }

    func deleteAll(includeFavorites: Bool) throws {
        storedItems.removeAll { includeFavorites || !$0.isFavorite }
    }
}
