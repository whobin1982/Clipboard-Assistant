import Foundation

final class RetentionCleaner {
    private let store: ClipboardStore

    init(store: ClipboardStore) {
        self.store = store
    }

    func run(now: Date = Date(), settings: AppSettings) throws {
        guard settings.retentionDays > 0 else { return }
        let cutoff = now.addingTimeInterval(TimeInterval(-settings.retentionDays * 24 * 60 * 60))
        try store.deleteNonFavorites(olderThan: cutoff)
    }
}
