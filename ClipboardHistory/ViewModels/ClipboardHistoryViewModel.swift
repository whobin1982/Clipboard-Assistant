import Combine
import Foundation

@MainActor
final class ClipboardHistoryViewModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var lastErrorMessage: String?

    private let store: ClipboardStore

    init(store: ClipboardStore) {
        self.store = store
    }

    var filteredItems: [ClipboardItem] {
        items.filter { $0.matches(query: query) }
    }

    func reload() {
        do {
            items = try store.fetchAll()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func toggleFavorite(_ item: ClipboardItem) {
        do {
            try store.setFavorite(id: item.id, isFavorite: !item.isFavorite)
            reload()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func delete(_ item: ClipboardItem) {
        do {
            try store.delete(id: item.id)
            reload()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
