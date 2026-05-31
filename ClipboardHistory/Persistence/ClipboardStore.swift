import Foundation

/// 剪贴板历史的存储接口，隐藏 SQLite 和测试内存存储的差异。
protocol ClipboardStore {
    /// 插入或更新一条记录。
    func insert(_ item: ClipboardItem) throws
    /// 按界面展示顺序取出所有记录：收藏优先，再按复制时间倒序。
    func fetchAll() throws -> [ClipboardItem]
    /// 修改收藏状态。
    func setFavorite(id: UUID, isFavorite: Bool) throws
    /// 删除单条记录。
    func delete(id: UUID) throws
    /// 删除早于指定时间的非收藏记录。
    func deleteNonFavorites(olderThan cutoff: Date) throws
    /// 清空历史；includeFavorites 为 false 时保留收藏记录。
    func deleteAll(includeFavorites: Bool) throws
}
