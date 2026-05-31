import AppKit
import XCTest
@testable import ClipboardHistory

final class ImageStorageTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageStorageTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    func testSaveWritesOriginalThumbnailAndReportsUsage() throws {
        let storage = try ImageStorage(directory: temporaryDirectory)
        let imageData = try XCTUnwrap(makeImage(size: NSSize(width: 100, height: 100)).pngData)
        let payload = ClipboardImagePayload(data: imageData, pasteboardType: .png)

        let paths = try storage.save(payload, id: UUID())

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.imagePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.thumbnailPath))
        XCTAssertEqual(URL(fileURLWithPath: paths.imagePath).pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: paths.imagePath)), imageData)
        XCTAssertNotNil(NSImage(contentsOfFile: paths.thumbnailPath))
        XCTAssertGreaterThan(storage.storageUsageBytes(), 0)
    }

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
