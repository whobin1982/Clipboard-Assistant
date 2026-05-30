import Foundation

enum ClipboardItemKind: String, Codable, Equatable {
    case text
    case image
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ClipboardItemKind
    var copiedAt: Date
    var lastUsedAt: Date?
    var isFavorite: Bool
    var text: String?
    var imagePath: String?
    var thumbnailPath: String?

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

    func matches(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard kind == .text, let text else { return false }
        return text.localizedCaseInsensitiveContains(trimmed)
    }
}
