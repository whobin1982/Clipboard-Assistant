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

    func testPausedRecordingDoesNotInsertAndSkipsPausedChangeWhenResumed() {
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

        XCTAssertTrue(store.insertedItems.isEmpty)
    }

    func testResumedRecordingStillCapturesNewChangesAfterSkippedPausedChange() {
        let pasteboard = FakePasteboard(changeCount: 1, string: "paused")
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
        pasteboard.string = "after resume"
        pasteboard.changeCount = 3
        monitor.pollOnce()

        XCTAssertEqual(store.insertedItems.map(\.text), ["after resume"])
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

    func testSuccessfulInsertPostsHistoryChangedNotification() {
        let pasteboard = FakePasteboard(changeCount: 1, string: "hello")
        let store = FakeClipboardStore()
        let historyChanged = expectation(description: "history changed notification")
        let observer = NotificationCenter.default.addObserver(
            forName: .clipboardHistoryDidChange,
            object: nil,
            queue: nil
        ) { _ in
            historyChanged.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            store: store,
            imageStorage: FakeImageStorage(),
            isRecordingPaused: { false }
        )

        pasteboard.changeCount = 2
        monitor.pollOnce()

        wait(for: [historyChanged], timeout: 1)
    }

    func testClipboardHistoryMarkedChangeDoesNotInsertAndIsNotRetried() {
        let pasteboard = FakePasteboard(changeCount: 1, string: "from history", isMarkedByClipboardHistory: true)
        let store = FakeClipboardStore()
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            store: store,
            imageStorage: FakeImageStorage(),
            isRecordingPaused: { false }
        )

        pasteboard.changeCount = 2
        monitor.pollOnce()
        pasteboard.isMarkedByClipboardHistory = false
        monitor.pollOnce()

        XCTAssertTrue(store.insertedItems.isEmpty)
    }

    func testClipboardHistoryMarkedImageChangeDoesNotSaveImageAndIsNotRetried() {
        let pasteboard = FakePasteboard(changeCount: 1, image: makeImage(), isMarkedByClipboardHistory: true)
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
        pasteboard.isMarkedByClipboardHistory = false
        monitor.pollOnce()

        XCTAssertTrue(imageStorage.savedArchives.isEmpty)
        XCTAssertTrue(store.insertedItems.isEmpty)
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

    func testPasteboardWithTextAndImageRecordsImageCopy() {
        let pasteboard = FakePasteboard(changeCount: 1, string: "copy me", image: makeImage())
        let store = FakeClipboardStore()
        let imageStorage = FakeImageStorage(result: ("/tmp/copied-image.png", "/tmp/copied-image-thumb.png"))
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            store: store,
            imageStorage: imageStorage,
            isRecordingPaused: { false }
        )

        pasteboard.changeCount = 2
        monitor.pollOnce()

        XCTAssertEqual(store.insertedItems.count, 1)
        XCTAssertEqual(store.insertedItems[0].kind, .image)
        XCTAssertNil(store.insertedItems[0].text)
        XCTAssertEqual(store.insertedItems[0].imagePath, "/tmp/copied-image.png")
        XCTAssertEqual(store.insertedItems[0].thumbnailPath, "/tmp/copied-image-thumb.png")
        XCTAssertEqual(imageStorage.savedArchives.count, 1)
    }

    func testImagePasteboardSavesImageAndInsertsImageClipboardItemWithReturnedPaths() throws {
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

        XCTAssertEqual(imageStorage.savedArchives.count, 1)
        XCTAssertEqual(imageStorage.savedArchives[0].items.count, 1)
        XCTAssertEqual(imageStorage.savedArchives[0].items[0].count, 1)
        XCTAssertEqual(imageStorage.savedArchives[0].items[0][0].data, try XCTUnwrap(image.pngData))
        XCTAssertEqual(imageStorage.savedArchives[0].items[0][0].pasteboardType, .png)
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
        XCTAssertEqual(imageStorage.savedArchives.count, 1)
        XCTAssertTrue(monitor.lastError is CocoaError)

        monitor.pollOnce()
        XCTAssertEqual(imageStorage.savedArchives.count, 1)

        pasteboard.changeCount = 3
        pasteboard.string = "recovered"
        pasteboard.imageArchive = nil
        imageStorage.error = nil
        monitor.pollOnce()

        XCTAssertNil(monitor.lastError)
        XCTAssertEqual(store.insertedItems.count, 1)
        XCTAssertEqual(store.insertedItems[0].kind, .text)
        XCTAssertEqual(store.insertedItems[0].text, "recovered")
    }

    func testTextStoreInsertFailureRetriesSameChangeCountOnNextPoll() {
        let pasteboard = FakePasteboard(changeCount: 1, string: "retry me")
        let store = FakeClipboardStore(error: TestError.insertFailed)
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            store: store,
            imageStorage: FakeImageStorage(),
            isRecordingPaused: { false }
        )

        pasteboard.changeCount = 2
        monitor.pollOnce()
        XCTAssertTrue(monitor.lastError is TestError)

        store.error = nil
        monitor.pollOnce()

        XCTAssertNil(monitor.lastError)
        XCTAssertEqual(store.insertedItems.count, 1)
        XCTAssertEqual(store.insertedItems[0].kind, .text)
        XCTAssertEqual(store.insertedItems[0].text, "retry me")
    }

    func testImageStoreInsertFailureRetriesSameChangeCountOnNextPoll() {
        let pasteboard = FakePasteboard(changeCount: 1, image: makeImage())
        let store = FakeClipboardStore(error: TestError.insertFailed)
        let imageStorage = FakeImageStorage(result: ("/tmp/retry.png", "/tmp/retry-thumb.png"))
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            store: store,
            imageStorage: imageStorage,
            isRecordingPaused: { false }
        )

        pasteboard.changeCount = 2
        monitor.pollOnce()
        XCTAssertTrue(monitor.lastError is TestError)

        store.error = nil
        monitor.pollOnce()

        XCTAssertNil(monitor.lastError)
        XCTAssertEqual(imageStorage.savedArchives.count, 2)
        XCTAssertEqual(store.insertedItems.count, 1)
        XCTAssertEqual(store.insertedItems[0].kind, .image)
        XCTAssertEqual(store.insertedItems[0].imagePath, "/tmp/retry.png")
        XCTAssertEqual(store.insertedItems[0].thumbnailPath, "/tmp/retry-thumb.png")
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
    var imageArchive: ClipboardImageArchive?
    var isMarkedByClipboardHistory: Bool

    init(
        changeCount: Int,
        string: String? = nil,
        image: NSImage? = nil,
        isMarkedByClipboardHistory: Bool = false
    ) {
        self.changeCount = changeCount
        self.string = string
        self.imageArchive = image.flatMap { image in
            image.pngData.map {
                ClipboardImageArchive(items: [[ClipboardImagePayload(data: $0, pasteboardType: .png)]])
            }
        }
        self.isMarkedByClipboardHistory = isMarkedByClipboardHistory
    }

    func readString() -> String? {
        string
    }

    func readImageArchive() -> ClipboardImageArchive? {
        imageArchive
    }

    func wasWrittenByClipboardHistory() -> Bool {
        isMarkedByClipboardHistory
    }
}

private final class FakeImageStorage: ImageStoring {
    private let result: (imagePath: String, thumbnailPath: String)
    var error: Error?
    private(set) var savedArchives: [ClipboardImageArchive] = []

    init(result: (imagePath: String, thumbnailPath: String) = ("/tmp/default.png", "/tmp/default-thumb.png"), error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func save(_ archive: ClipboardImageArchive, id: UUID) throws -> (imagePath: String, thumbnailPath: String) {
        savedArchives.append(archive)
        if let error {
            throw error
        }
        return result
    }
}

private final class FakeClipboardStore: ClipboardStore {
    private(set) var insertedItems: [ClipboardItem] = []
    var error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func insert(_ item: ClipboardItem) throws {
        if let error {
            throw error
        }
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

private enum TestError: Error {
    case insertFailed
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
