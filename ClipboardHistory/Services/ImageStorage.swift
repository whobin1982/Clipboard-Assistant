import AppKit
import Foundation

/// 负责把图片剪贴板归档和缩略图保存到应用私有目录。
final class ImageStorage {
    let directory: URL

    /// 初始化图片目录，不存在时自动创建。
    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 保存完整图片归档和列表缩略图，返回两者的磁盘路径。
    func save(_ archive: ClipboardImageArchive, id: UUID) throws -> (imagePath: String, thumbnailPath: String) {
        guard let image = archive.firstImage else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let imageURL = directory.appendingPathComponent("\(id.uuidString).\(ClipboardImageArchive.fileExtension)")
        let thumbnailURL = directory.appendingPathComponent("\(id.uuidString)-thumb.png")
        try archive.write(to: imageURL)
        try writePNG(thumbnail(from: image), to: thumbnailURL)
        return (imageURL.path, thumbnailURL.path)
    }

    /// 统计图片目录占用空间，用于设置页展示。
    func storageUsageBytes() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return 0
        }
        return files.reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            return total + size
        }
    }

    /// 删除指定历史记录关联的原图归档和缩略图。
    func deleteFiles(for items: [ClipboardItem]) throws {
        try imageFileURLs(for: items).forEach(removeFileIfPresent)
    }

    /// 删除目录中已经没有数据库记录引用的孤儿文件。
    func removeOrphanedFiles(referencedBy items: [ClipboardItem]) throws {
        let referencedPaths = Set(imageFileURLs(for: items).map(\.standardizedFileURL.path))
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )

        for file in files where !referencedPaths.contains(file.standardizedFileURL.path) {
            try removeFileIfPresent(file)
        }
    }
}

/// ImageStorage 的文件路径、缩略图和 PNG 编码辅助方法。
private extension ImageStorage {
    /// 收集记录中所有图片相关路径。
    func imageFileURLs(for items: [ClipboardItem]) -> [URL] {
        items.flatMap { item in
            [item.imagePath, item.thumbnailPath].compactMap { path in
                guard let path, !path.isEmpty else { return nil }
                return URL(fileURLWithPath: path)
            }
        }
    }

    /// 文件存在时删除，不存在时静默跳过。
    func removeFileIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// 生成固定尺寸缩略图，用于历史列表快速预览。
    func thumbnail(from image: NSImage) -> NSImage {
        let targetSize = NSSize(width: 96, height: 96)
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: targetSize).fill()
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        thumbnail.unlockFocus()
        return thumbnail
    }

    /// 将 NSImage 编码为 PNG 文件。
    func writePNG(_ image: NSImage, to url: URL) throws {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        try pngData.write(to: url, options: .atomic)
    }
}
