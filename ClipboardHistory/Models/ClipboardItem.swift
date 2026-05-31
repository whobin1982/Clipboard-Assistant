import Foundation

/// 剪贴板记录类型，目前只记录文本和图片。
enum ClipboardItemKind: String, Codable, Equatable {
    case text
    case image
}

/// 单条剪贴板历史记录。
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ClipboardItemKind
    /// 第一次复制进历史的时间，用于排序和保留期清理。
    var copiedAt: Date
    /// 最近一次从历史中使用的时间。
    var lastUsedAt: Date?
    var isFavorite: Bool
    /// 文本记录内容；图片记录为空。
    var text: String?
    /// 图片归档文件路径；文本记录为空。
    var imagePath: String?
    /// 图片缩略图路径，用于列表预览。
    var thumbnailPath: String?

    /// 创建文本记录的便捷方法。
    static func text(_ value: String, copiedAt: Date = Date()) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .text,
            copiedAt: copiedAt,
            lastUsedAt: nil,
            isFavorite: false,
            text: value,
            imagePath: nil,
            thumbnailPath: nil
        )
    }

    /// 创建图片记录的便捷方法。
    static func image(imagePath: String, thumbnailPath: String, copiedAt: Date = Date()) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .image,
            copiedAt: copiedAt,
            lastUsedAt: nil,
            isFavorite: false,
            text: nil,
            imagePath: imagePath,
            thumbnailPath: thumbnailPath
        )
    }

    /// 判断记录是否匹配搜索关键词；图片记录暂不参与文本搜索。
    func matches(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard kind == .text, let text else { return false }
        return text.localizedCaseInsensitiveContains(trimmed)
    }
}
