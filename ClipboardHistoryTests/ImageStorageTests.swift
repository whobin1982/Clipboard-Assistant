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
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
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

    /// 图片导出服务应把新版图片归档导出为可读取的 PNG。
    @MainActor
    func testImageExportServiceWritesArchiveImageAsPNG() throws {
        let imageData = try XCTUnwrap(makeImage(size: NSSize(width: 16, height: 16)).pngData)
        let archive = ClipboardImageArchive(items: [[
            ClipboardImagePayload(data: imageData, pasteboardType: .png)
        ]])
        let archiveURL = temporaryDirectory.appendingPathComponent("saved.\(ClipboardImageArchive.fileExtension)")
        let destinationURL = temporaryDirectory.appendingPathComponent("exported.png")
        try archive.write(to: archiveURL)
        let item = ClipboardItem.image(imagePath: archiveURL.path, thumbnailPath: archiveURL.path)
        let service = ImageExportService(destinationChooser: FakeImageExportDestinationChooser(destination: destinationURL))

        let result = try service.export(item)

        XCTAssertEqual(result, .exported(destinationURL))
        XCTAssertNotNil(NSImage(contentsOf: destinationURL))
    }

    /// 用户取消保存面板时，导出服务应返回取消，不显示错误。
    @MainActor
    func testImageExportServiceReturnsCancelledWhenDestinationIsNil() throws {
        let imageURL = temporaryDirectory.appendingPathComponent("image.png")
        try XCTUnwrap(makeImage(size: NSSize(width: 16, height: 16)).pngData).write(to: imageURL)
        let item = ClipboardItem.image(imagePath: imageURL.path, thumbnailPath: imageURL.path)
        let service = ImageExportService(destinationChooser: FakeImageExportDestinationChooser(destination: nil))

        let result = try service.export(item)

        XCTAssertEqual(result, .cancelled)
    }

    /// 图片路径不可读时，导出服务应抛出带路径的中文错误。
    @MainActor
    func testImageExportServiceThrowsForUnreadableImagePath() {
        let item = ClipboardItem.image(imagePath: "/definitely/missing/image.png", thumbnailPath: "/tmp/thumb.png")
        let service = ImageExportService(
            destinationChooser: FakeImageExportDestinationChooser(
                destination: temporaryDirectory.appendingPathComponent("exported.png")
            )
        )

        XCTAssertThrowsError(try service.export(item)) { error in
            XCTAssertEqual(error as? ImageExportServiceError, .unreadableImage("/definitely/missing/image.png"))
            XCTAssertEqual(error.localizedDescription, "无法读取图片文件：/definitely/missing/image.png。")
        }
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

private struct FakeImageExportDestinationChooser: ImageExportDestinationChoosing {
    let destination: URL?

    func exportDestination(defaultFilename: String) -> URL? {
        destination
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
