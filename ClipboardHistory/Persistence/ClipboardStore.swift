import Foundation

protocol ClipboardStore {
    func insert(_ item: ClipboardItem) throws
    func fetchAll() throws -> [ClipboardItem]
    func setFavorite(id: UUID, isFavorite: Bool) throws
    func delete(id: UUID) throws
    func deleteNonFavorites(olderThan cutoff: Date) throws
    func deleteAll(includeFavorites: Bool) throws
}
