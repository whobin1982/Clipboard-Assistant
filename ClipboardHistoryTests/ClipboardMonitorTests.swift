import AppKit
import XCTest
@testable import ClipboardHistory

/// 验证剪贴板监听器对文本、图片、文件引用、暂停状态和失败重试的处理。
final class ClipboardMonitorTests: XCTestCase {
    /// changeCount 没变化时不应重复插入。
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

    /// 暂停记录期间复制的内容恢复后也不应补记。
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

    /// 恢复记录后新的 changeCount 仍应被正常捕获。
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

    /// 新的非空文本应写入文本历史。
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

    /// 成功插入历史后应发送刷新通知。
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

    /// 本应用写回剪贴板的文本不应再次进入历史，也不应在下一轮重试。
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

    /// 本应用写回剪贴板的图片不应再次保存，也不应在下一轮重试。
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

    /// 非图片文件引用不应被记录成文本或图片。
    func testFilePasteboardDoesNotInsertTextOrImageAndIsNotRetried() {
        let pasteboard = FakePasteboard(
            changeCount: 1,
            string: "copied-file.png",
            containsFileReference: true
        )
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
        pasteboard.containsFileReference = false
        monitor.pollOnce()

        XCTAssertTrue(imageStorage.savedArchives.isEmpty)
        XCTAssertTrue(store.insertedItems.isEmpty)
    }

    /// 图片文件引用应记录真实图片内容，而不是文件名文本。
    func testImageFilePasteboardRecordsImageAndDoesNotInsertFileNameText() throws {
        let image = makeImage()
        let pasteboard = FakePasteboard(
            changeCount: 1,
            string: "copied-file.png",
            image: image,
            containsFileReference: true
        )
        let store = FakeClipboardStore()
        let imageStorage = FakeImageStorage(result: ("/tmp/file-image.clipboardimage", "/tmp/file-image-thumb.png"))
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            store: store,
            imageStorage: imageStorage,
            isRecordingPaused: { false }
        )

        pasteboard.changeCount = 2
        monitor.pollOnce()

        XCTAssertEqual(imageStorage.savedArchives.count, 1)
        XCTAssertEqual(imageStorage.savedArchives[0].items[0][0].data, try XCTUnwrap(image.pngData))
        XCTAssertEqual(store.insertedItems.count, 1)
        XCTAssertEqual(store.insertedItems[0].kind, .image)
        XCTAssertNil(store.insertedItems[0].text)
    }

    /// 空白文本不应进入历史。
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

    /// 同时包含文本和图片时优先记录图片，避免图片复制被降级成文本。
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

    /// 直接图片复制应保存图片归档并插入图片历史。
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

    /// 图片保存失败只影响本次内容，之后新的剪贴板变化仍可继续记录。
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

    /// 文本插入失败时不推进 changeCount，下次轮询会重试同一内容。
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

    /// 图片记录写入数据库失败时会重试同一 changeCount。
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

    /// 创建测试用图片。
    private func makeImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.systemGreen.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()
        return image
    }
}

/// 测试用剪贴板读取器，可控制文本、图片、文件引用和内部 marker。
private final class FakePasteboard: PasteboardReading {
    var changeCount: Int
    var string: String?
    var imageArchive: ClipboardImageArchive?
    var isMarkedByClipboardHistory: Bool
    var containsFileReference: Bool

    init(
        changeCount: Int,
        string: String? = nil,
        image: NSImage? = nil,
        isMarkedByClipboardHistory: Bool = false,
        containsFileReference: Bool = false
    ) {
        self.changeCount = changeCount
        self.string = string
        self.imageArchive = image.flatMap { image in
            image.pngData.map {
                ClipboardImageArchive(items: [[ClipboardImagePayload(data: $0, pasteboardType: .png)]])
            }
        }
        self.isMarkedByClipboardHistory = isMarkedByClipboardHistory
        self.containsFileReference = containsFileReference
    }

    func readString() -> String? {
        string
    }

    func readImageArchive() -> ClipboardImageArchive? {
        imageArchive
    }

    func hasFileReference() -> Bool {
        containsFileReference
    }

    func wasWrittenByClipboardHistory() -> Bool {
        isMarkedByClipboardHistory
    }
}

/// 测试用图片存储器，记录保存过的归档并可模拟保存失败。
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

/// 测试用历史存储，可记录插入项并模拟插入失败。
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

/// 测试中用于模拟写入失败的错误。
private enum TestError: Error {
    case insertFailed
}

/// 为测试图片生成 PNG 数据。
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
