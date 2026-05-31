import Foundation
import XCTest
@testable import ClipboardHistory

/// 验证历史列表视图模型的搜索、收藏、删除和重新加载行为。
@MainActor
final class ClipboardHistoryViewModelTests: XCTestCase {
    /// 空搜索返回全部记录，文本搜索只匹配文本内容。
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

    /// 切换收藏状态后应写入存储并刷新列表。
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

    /// 删除记录后应刷新列表。
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

/// ViewModel 测试用内存存储，模拟 ClipboardStore 的核心行为。
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
