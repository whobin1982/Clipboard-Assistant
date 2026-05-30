import AppKit
import XCTest
@testable import ClipboardHistory

final class ClipboardMonitorTests: XCTestCase {
    func testUnchangedChangeCountDoesNotInsert() {
        let pasteboard = FakePasteboard(changeCount: 1, string: "same")
        let store = FakeClipboardStore()
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            store: store,
            imageStorage: FakeImageStorage(),
            isRecordingPaused: { false }
        )

        monitor.pollOnce()

        XCTAssertTrue(store.insertedItems.isEmpty)
    }

    func testPausedRecordingDoesNotInsertAndDoesNotAdvanceLastProcessedChangeCount() {
        let pasteboard = FakePasteboard(changeCount: 1, string: "deferred")
        let store = FakeClipboardStore()
        var isPaused = true
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            store: store,
            imageStorage: FakeImageStorage(),
            isRecordingPaused: { isPaused }
        )

        pasteboard.changeCount = 2
        monitor.pollOnce()
        isPaused = false
        monitor.pollOnce()

        XCTAssertEqual(store.insertedItems.map(\.text), ["deferred"])
    }

    func testNewNonEmptyTextInsertsTextClipboardItem() {
        let pasteboard = FakePasteboard(changeCount: 1, string: "hello")
        let store = FakeClipboardStore()
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            store: store,
            imageStorage: FakeImageStorage(),
            isRecordingPaused: { false }
        )

        pasteboard.changeCount = 2
        monitor.pollOnce()

        XCTAssertEqual(store.insertedItems.count, 1)
        XCTAssertEqual(store.insertedItems[0].kind, .text)
        XCTAssertEqual(store.insertedItems[0].text, "hello")
    }

    func testWhitespaceOnlyTextDoesNotInsert() {
        let pasteboard = FakePasteboard(changeCount: 1, string: " \n\t ")
        let store = FakeClipboardStore()
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            store: store,
            imageStorage: FakeImageStorage(),
            isRecordingPaused: { false }
        )

        pasteboard.changeCount = 2
        monitor.pollOnce()

        XCTAssertTrue(store.insertedItems.isEmpty)
    }

    func testPasteboardWithTextAndImagePrefersText() {
        let pasteboard = FakePasteboard(changeCount: 1, string: "copy me", image: makeImage())
        let store = FakeClipboardStore()
        let imageStorage = FakeImageStorage()
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            store: store,
            imageStorage: imageStorage,
            isRecordingPaused: { false }
        )

        pasteboard.changeCount = 2
        monitor.pollOnce()

        XCTAssertEqual(store.insertedItems.count, 1)
        XCTAssertEqual(store.insertedItems[0].kind, .text)
        XCTAssertEqual(store.insertedItems[0].text, "copy me")
        XCTAssertTrue(imageStorage.savedImages.isEmpty)
    }

    func testImagePasteboardSavesImageAndInsertsImageClipboardItemWithReturnedPaths() {
        let image = makeImage()
        let pasteboard = FakePasteboard(changeCount: 1, image: image)
        let store = FakeClipboardStore()
        let imageStorage = FakeImageStorage(result: ("/tmp/image.png", "/tmp/image-thumb.png"))
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            store: store,
            imageStorage: imageStorage,
            isRecordingPaused: { false }
        )

        pasteboard.changeCount = 2
        monitor.pollOnce()

        XCTAssertEqual(imageStorage.savedImages.count, 1)
        XCTAssertTrue(imageStorage.savedImages[0] === image)
        XCTAssertEqual(store.insertedItems.count, 1)
        XCTAssertEqual(store.insertedItems[0].kind, .image)
        XCTAssertEqual(store.insertedItems[0].imagePath, "/tmp/image.png")
        XCTAssertEqual(store.insertedItems[0].thumbnailPath, "/tmp/image-thumb.png")
    }

    func testImageSaveFailureDoesNotThrowOutOfPollOnceAndLaterValidChangeCanStillInsert() {
        let pasteboard = FakePasteboard(changeCount: 1, image: makeImage())
        let store = FakeClipboardStore()
        let imageStorage = FakeImageStorage(error: CocoaError(.fileWriteUnknown))
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            store: store,
            imageStorage: imageStorage,
            isRecordingPaused: { false }
        )

        pasteboard.changeCount = 2
        monitor.pollOnce()
        pasteboard.changeCount = 3
        pasteboard.string = "recovered"
        pasteboard.image = nil
        imageStorage.error = nil
        monitor.pollOnce()

        XCTAssertEqual(store.insertedItems.count, 1)
        XCTAssertEqual(store.insertedItems[0].kind, .text)
        XCTAssertEqual(store.insertedItems[0].text, "recovered")
    }

    private func makeImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.systemGreen.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()
        return image
    }
}

private final class FakePasteboard: PasteboardReading {
    var changeCount: Int
    var string: String?
    var image: NSImage?

    init(changeCount: Int, string: String? = nil, image: NSImage? = nil) {
        self.changeCount = changeCount
        self.string = string
        self.image = image
    }

    func readString() -> String? {
        string
    }

    func readImage() -> NSImage? {
        image
    }
}

private final class FakeImageStorage: ImageStoring {
    private let result: (imagePath: String, thumbnailPath: String)
    var error: Error?
    private(set) var savedImages: [NSImage] = []

    init(result: (imagePath: String, thumbnailPath: String) = ("/tmp/default.png", "/tmp/default-thumb.png"), error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func save(_ image: NSImage, id: UUID) throws -> (imagePath: String, thumbnailPath: String) {
        savedImages.append(image)
        if let error {
            throw error
        }
        return result
    }
}

private final class FakeClipboardStore: ClipboardStore {
    private(set) var insertedItems: [ClipboardItem] = []

    func insert(_ item: ClipboardItem) throws {
        insertedItems.append(item)
    }

    func fetchAll() throws -> [ClipboardItem] {
        insertedItems
    }

    func setFavorite(id: UUID, isFavorite: Bool) throws {}

    func delete(id: UUID) throws {}

    func deleteNonFavorites(olderThan cutoff: Date) throws {}

    func deleteAll(includeFavorites: Bool) throws {
        insertedItems.removeAll()
    }
}
