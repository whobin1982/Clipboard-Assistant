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
        let image = makeImage(size: NSSize(width: 100, height: 100))

        let paths = try storage.save(image, id: UUID())

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.imagePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.thumbnailPath))
        XCTAssertGreaterThan(storage.storageUsageBytes(), 0)
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
