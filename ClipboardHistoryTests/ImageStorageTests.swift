import AppKit
import XCTest
@testable import ClipboardHistory

/// 验证图片归档、缩略图、空间统计和孤儿文件清理。
final class ImageStorageTests: XCTestCase {
    private var temporaryDirectory: URL!

    /// 每个测试使用独立临时目录，避免相互污染。
    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageStorageTests-\(UUID().uuidString)", isDirectory: true)
    }

    /// 测试结束后删除临时目录。
    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    /// 保存图片时应写入完整归档、缩略图并能统计空间。
    func testSaveWritesArchiveThumbnailAndReportsUsage() throws {
        let storage = try ImageStorage(directory: temporaryDirectory)
        let imageData = try XCTUnwrap(makeImage(size: NSSize(width: 100, height: 100)).pngData)
        let archive = ClipboardImageArchive(items: [[
            ClipboardImagePayload(data: imageData, pasteboardType: .png),
            ClipboardImagePayload(data: try XCTUnwrap(makeImage(size: NSSize(width: 100, height: 100)).tiffRepresentation), pasteboardType: .tiff)
        ]])

        let paths = try storage.save(archive, id: UUID())

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.imagePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.thumbnailPath))
        XCTAssertEqual(URL(fileURLWithPath: paths.imagePath).pathExtension, ClipboardImageArchive.fileExtension)
        let savedArchive = try ClipboardImageArchive.load(from: URL(fileURLWithPath: paths.imagePath))
        XCTAssertEqual(savedArchive, archive)
        XCTAssertNotNil(NSImage(contentsOfFile: paths.thumbnailPath))
        XCTAssertGreaterThan(storage.storageUsageBytes(), 0)
    }

    /// 删除图片记录时应移除原图归档和缩略图。
    func testDeleteFilesRemovesOriginalAndThumbnail() throws {
        let storage = try ImageStorage(directory: temporaryDirectory)
        let imageURL = temporaryDirectory.appendingPathComponent("item.png")
        let thumbnailURL = temporaryDirectory.appendingPathComponent("item-thumb.png")
        try Data("image".utf8).write(to: imageURL)
        try Data("thumbnail".utf8).write(to: thumbnailURL)
        let item = ClipboardItem.image(imagePath: imageURL.path, thumbnailPath: thumbnailURL.path)

        try storage.deleteFiles(for: [item])

        XCTAssertFalse(FileManager.default.fileExists(atPath: imageURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbnailURL.path))
    }

    /// 清理孤儿文件时应保留仍被记录引用的文件。
    func testRemoveOrphanedFilesKeepsReferencedFiles() throws {
        let storage = try ImageStorage(directory: temporaryDirectory)
        let referencedURL = temporaryDirectory.appendingPathComponent("referenced.png")
        let referencedThumbnailURL = temporaryDirectory.appendingPathComponent("referenced-thumb.png")
        let orphanURL = temporaryDirectory.appendingPathComponent("orphan.png")
        try Data("image".utf8).write(to: referencedURL)
        try Data("thumbnail".utf8).write(to: referencedThumbnailURL)
        try Data("orphan".utf8).write(to: orphanURL)
        let item = ClipboardItem.image(
            imagePath: referencedURL.path,
            thumbnailPath: referencedThumbnailURL.path
        )

        try storage.removeOrphanedFiles(referencedBy: [item])

        XCTAssertTrue(FileManager.default.fileExists(atPath: referencedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: referencedThumbnailURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanURL.path))
    }

    /// 创建测试用纯色图片。
    private func makeImage(size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }
}

private extension NSImage {
    var pngData: Data? {
        guard
            let tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffRepresentation)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
