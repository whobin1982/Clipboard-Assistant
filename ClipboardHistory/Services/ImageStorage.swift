import AppKit
import Foundation

final class ImageStorage {
    let directory: URL

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func save(_ image: NSImage, id: UUID) throws -> (imagePath: String, thumbnailPath: String) {
        let imageURL = directory.appendingPathComponent("\(id.uuidString).png")
        let thumbnailURL = directory.appendingPathComponent("\(id.uuidString)-thumb.png")
        try writePNG(image, to: imageURL)
        try writePNG(thumbnail(from: image), to: thumbnailURL)
        return (imageURL.path, thumbnailURL.path)
    }

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

    func deleteFiles(for items: [ClipboardItem]) throws {
        try imageFileURLs(for: items).forEach(removeFileIfPresent)
    }

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

private extension ImageStorage {
    func imageFileURLs(for items: [ClipboardItem]) -> [URL] {
        items.flatMap { item in
            [item.imagePath, item.thumbnailPath].compactMap { path in
                guard let path, !path.isEmpty else { return nil }
                return URL(fileURLWithPath: path)
            }
        }
    }

    func removeFileIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

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
