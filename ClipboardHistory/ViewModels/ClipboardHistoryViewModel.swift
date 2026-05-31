import Combine
import Foundation

/// 历史记录窗口的列表状态和操作逻辑。
@MainActor
final class ClipboardHistoryViewModel: ObservableObject {
    /// 搜索框输入。
    @Published var query: String = ""
    /// 从存储读取到的完整记录列表。
    @Published private(set) var items: [ClipboardItem] = []
    /// 最近一次列表操作失败时的错误。
    @Published private(set) var lastErrorMessage: String?

    private let store: ClipboardStore

    init(store: ClipboardStore) {
        self.store = store
    }

    /// 根据搜索关键词过滤后的列表。
    var filteredItems: [ClipboardItem] {
        items.filter { $0.matches(query: query) }
    }

    /// 从存储重新加载历史记录。
    func reload() {
        do {
            items = try store.fetchAll()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// 切换收藏状态并刷新列表。
    func toggleFavorite(_ item: ClipboardItem) {
        do {
            try store.setFavorite(id: item.id, isFavorite: !item.isFavorite)
            reload()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// 删除单条记录并刷新列表；图片文件清理由 AppEnvironment 负责。
    func delete(_ item: ClipboardItem) {
        do {
            try store.delete(id: item.id)
            reload()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
