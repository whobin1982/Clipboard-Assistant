import AppKit
import XCTest
@testable import ClipboardHistory

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testSelectingShortcutPersistsAndNotifiesShortcutService() {
        var savedSettings: [AppSettings] = []
        var updatedShortcuts: [ShortcutDefinition] = []
        let viewModel = SettingsViewModel(
            settingsDidChange: { savedSettings.append($0) },
            shortcutDidChange: { updatedShortcuts.append($0) }
        )

        viewModel.selectedShortcutID = ShortcutDefinition.controlOptionV.id

        XCTAssertEqual(viewModel.settings.shortcutID, ShortcutDefinition.controlOptionV.id)
        XCTAssertEqual(savedSettings.last?.shortcutID, ShortcutDefinition.controlOptionV.id)
        XCTAssertEqual(updatedShortcuts.last, .controlOptionV)
    }
}

final class AppEnvironmentTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppEnvironmentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    @MainActor
    func testDeleteRemovesAssociatedImageFiles() throws {
        let imageURL = temporaryDirectory.appendingPathComponent("item.png")
        let thumbnailURL = temporaryDirectory.appendingPathComponent("item-thumb.png")
        try Data("image".utf8).write(to: imageURL)
        try Data("thumbnail".utf8).write(to: thumbnailURL)
        let item = ClipboardItem.image(imagePath: imageURL.path, thumbnailPath: thumbnailURL.path)
        let store = AppEnvironmentFakeStore(items: [item])
        let storage = try ImageStorage(directory: temporaryDirectory)
        let environment = AppEnvironment(store: store, imageStorage: storage)

        environment.delete(item)

        XCTAssertTrue(try store.fetchAll().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: imageURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbnailURL.path))
    }

    @MainActor
    func testMenuPasteCopiesAndSendsWithoutUsingSearchPresenter() async throws {
        let pasteSent = expectation(description: "paste command sent")
        let recorder = AppEnvironmentCallRecorder()
        let item = ClipboardItem.text("Saved text")
        let store = AppEnvironmentFakeStore(items: [item], recorder: recorder)
        let pasteboard = AppEnvironmentFakePasteboardWriter(recorder: recorder)
        let sender = AppEnvironmentFakePasteEventSender(recorder: recorder) {
            pasteSent.fulfill()
        }
        let pasteService = PasteService(pasteboard: pasteboard, pasteEventSender: sender)
        let presenter = AppEnvironmentFakeSearchWindowPresenter(recorder: recorder)
        let environment = AppEnvironment(
            store: store,
            pasteService: pasteService,
            searchWindowPresenter: presenter
        )

        environment.paste(item)

        await fulfillment(of: [pasteSent], timeout: 1)
        XCTAssertEqual(pasteboard.writtenText, "Saved text")
        XCTAssertNil(environment.lastErrorMessage)
        XCTAssertEqual(
            recorder.calls,
            [
                "writeText:Saved text",
                "insert",
                "fetchAll",
                "sendPasteCommand"
            ]
        )
        XCTAssertNotNil(try store.fetchAll().first?.lastUsedAt)
    }

    @MainActor
    func testPopupPasteCopiesMarksUsedClosesConsumesTargetThenSendsPaste() async throws {
        let pasteSent = expectation(description: "paste command sent")
        let recorder = AppEnvironmentCallRecorder()
        let item = ClipboardItem.text("Saved text")
        let store = AppEnvironmentFakeStore(items: [item], recorder: recorder)
        let pasteboard = AppEnvironmentFakePasteboardWriter(recorder: recorder)
        let sender = AppEnvironmentFakePasteEventSender(recorder: recorder) {
            pasteSent.fulfill()
        }
        let pasteService = PasteService(pasteboard: pasteboard, pasteEventSender: sender)
        let presenter = AppEnvironmentFakeSearchWindowPresenter(recorder: recorder)
        let environment = AppEnvironment(
            store: store,
            pasteService: pasteService,
            searchWindowPresenter: presenter
        )

        environment.openSearch()
        recorder.calls.removeAll()
        try XCTUnwrap(presenter.onPaste)(item)

        await fulfillment(of: [pasteSent], timeout: 1)
        XCTAssertEqual(pasteboard.writtenText, "Saved text")
        XCTAssertNil(environment.lastErrorMessage)
        XCTAssertEqual(
            recorder.calls,
            [
                "writeText:Saved text",
                "insert",
                "fetchAll",
                "orderOut",
                "consumePreviousApplication",
                "sendPasteCommand"
            ]
        )
        XCTAssertNotNil(try store.fetchAll().first?.lastUsedAt)
    }

    @MainActor
    func testPasteSenderFailureLeavesItemCopiedAndSurfacesError() async throws {
        let pasteSent = expectation(description: "paste command attempted")
        let recorder = AppEnvironmentCallRecorder()
        let item = ClipboardItem.text("Saved text")
        let store = AppEnvironmentFakeStore(items: [item], recorder: recorder)
        let pasteboard = AppEnvironmentFakePasteboardWriter(recorder: recorder)
        let sender = AppEnvironmentFakePasteEventSender(
            recorder: recorder,
            error: AppEnvironmentTestError.pasteFailed
        ) {
            pasteSent.fulfill()
        }
        let pasteService = PasteService(pasteboard: pasteboard, pasteEventSender: sender)
        let presenter = AppEnvironmentFakeSearchWindowPresenter(recorder: recorder)
        let environment = AppEnvironment(
            store: store,
            pasteService: pasteService,
            searchWindowPresenter: presenter
        )

        environment.paste(item)

        await fulfillment(of: [pasteSent], timeout: 1)
        XCTAssertEqual(pasteboard.writtenText, "Saved text")
        XCTAssertEqual(environment.lastErrorMessage, AppEnvironmentTestError.pasteFailed.localizedDescription)
        XCTAssertNotNil(try store.fetchAll().first?.lastUsedAt)
    }
}

private final class AppEnvironmentFakeStore: ClipboardStore {
    private var items: [ClipboardItem]
    private let recorder: AppEnvironmentCallRecorder?

    init(items: [ClipboardItem], recorder: AppEnvironmentCallRecorder? = nil) {
        self.items = items
        self.recorder = recorder
    }

    func insert(_ item: ClipboardItem) throws {
        recorder?.record("insert")
        items.removeAll { $0.id == item.id }
        items.append(item)
    }

    func fetchAll() throws -> [ClipboardItem] {
        recorder?.record("fetchAll")
        return items
    }

    func setFavorite(id: UUID, isFavorite: Bool) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isFavorite = isFavorite
    }

    func delete(id: UUID) throws {
        items.removeAll { $0.id == id }
    }

    func deleteNonFavorites(olderThan cutoff: Date) throws {
        items.removeAll { !$0.isFavorite && $0.copiedAt < cutoff }
    }

    func deleteAll(includeFavorites: Bool) throws {
        items.removeAll { includeFavorites || !$0.isFavorite }
    }
}

@MainActor
private final class AppEnvironmentFakeSearchWindowPresenter: SearchWindowPresenting {
    private let recorder: AppEnvironmentCallRecorder
    private(set) var onPaste: ((ClipboardItem) -> Void)?

    init(recorder: AppEnvironmentCallRecorder) {
        self.recorder = recorder
    }

    func show(
        viewModel: ClipboardHistoryViewModel,
        onPaste: @escaping (ClipboardItem) -> Void,
        onCopy: @escaping (ClipboardItem) -> Void,
        onDelete: @escaping (ClipboardItem) -> Void
    ) {
        self.onPaste = onPaste
    }

    func orderOut() {
        recorder.record("orderOut")
    }

    func consumePreviousApplication() -> NSRunningApplication? {
        recorder.record("consumePreviousApplication")
        return nil
    }
}

private final class AppEnvironmentFakePasteboardWriter: PasteboardWriting {
    private let recorder: AppEnvironmentCallRecorder
    private(set) var writtenText: String?
    private(set) var writtenImage: NSImage?

    init(recorder: AppEnvironmentCallRecorder) {
        self.recorder = recorder
    }

    func writeText(_ text: String) throws {
        writtenText = text
        recorder.record("writeText:\(text)")
    }

    func writeImage(_ image: NSImage) throws {
        writtenImage = image
        recorder.record("writeImage")
    }
}

private final class AppEnvironmentFakePasteEventSender: PasteEventSending {
    private let recorder: AppEnvironmentCallRecorder
    private let error: Error?
    private let onSend: () -> Void

    init(
        recorder: AppEnvironmentCallRecorder,
        error: Error? = nil,
        onSend: @escaping () -> Void
    ) {
        self.recorder = recorder
        self.error = error
        self.onSend = onSend
    }

    func sendPasteCommand() throws {
        recorder.record("sendPasteCommand")
        onSend()
        if let error {
            throw error
        }
    }
}

private final class AppEnvironmentCallRecorder {
    var calls: [String] = []

    func record(_ call: String) {
        calls.append(call)
    }
}

private enum AppEnvironmentTestError: Error {
    case pasteFailed
}
