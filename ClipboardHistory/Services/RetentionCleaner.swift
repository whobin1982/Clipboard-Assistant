import Foundation

/// 按设置中的保留天数清理过期非收藏记录。
final class RetentionCleaner {
    private let store: ClipboardStore

    init(store: ClipboardStore) {
        self.store = store
    }

    /// 执行一次清理；retentionDays 为 0 时代表永久保留。
    func run(now: Date = Date(), settings: AppSettings) throws {
        guard settings.retentionDays > 0 else { return }
        let cutoff = now.addingTimeInterval(TimeInterval(-settings.retentionDays * 24 * 60 * 60))
        try store.deleteNonFavorites(olderThan: cutoff)
    }
}
