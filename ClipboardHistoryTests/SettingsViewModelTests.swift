import AppKit
import SwiftUI
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

    func testApplyingCustomShortcutPersistsAndNotifiesShortcutService() {
        var savedSettings: [AppSettings] = []
        var updatedShortcuts: [ShortcutDefinition] = []
        let shortcut = ShortcutDefinition.custom(
            displayName: "⌃ + ⌥ + P",
            keyCode: 35,
            requiresCommand: false,
            requiresOption: true,
            requiresControl: true,
            requiresShift: false
        )
        let viewModel = SettingsViewModel(
            settingsDidChange: { savedSettings.append($0) },
            shortcutDidChange: { updatedShortcuts.append($0) }
        )

        viewModel.applyCustomShortcut(shortcut)

        XCTAssertEqual(viewModel.settings.shortcutID, ShortcutDefinition.customID)
        XCTAssertEqual(viewModel.settings.customShortcut, shortcut)
        XCTAssertEqual(savedSettings.last?.shortcut, shortcut)
        XCTAssertEqual(updatedShortcuts.last, shortcut)
    }

    func testSelectingExistingCustomShortcutKeepsRecordedShortcut() {
        var updatedShortcuts: [ShortcutDefinition] = []
        let shortcut = ShortcutDefinition.custom(
            displayName: "⌃ + ⌥ + P",
            keyCode: 35,
            requiresCommand: false,
            requiresOption: true,
            requiresControl: true,
            requiresShift: false
        )
        let viewModel = SettingsViewModel(
            settings: AppSettings(
                retentionDays: 30,
                launchAtLogin: false,
                shortcutID: ShortcutDefinition.customID,
                customShortcut: shortcut
            ),
            shortcutDidChange: { updatedShortcuts.append($0) }
        )

        viewModel.selectedShortcutID = ShortcutDefinition.customID

        XCTAssertEqual(viewModel.settings.shortcut, shortcut)
        XCTAssertEqual(updatedShortcuts.last, shortcut)
    }

    func testChangingSelectionActionPersistsSettings() {
        var savedSettings: [AppSettings] = []
        let viewModel = SettingsViewModel(settingsDidChange: { savedSettings.append($0) })

        viewModel.selectionAction = .copyOnly

        XCTAssertEqual(viewModel.settings.selectionAction, .copyOnly)
        XCTAssertEqual(savedSettings.last?.selectionAction, .copyOnly)
    }

    func testChangingCloseAndEscapeSettingsPersistsSettings() {
        var savedSettings: [AppSettings] = []
        let viewModel = SettingsViewModel(settingsDidChange: { savedSettings.append($0) })

        viewModel.closeWindowAfterSelection = false
        viewModel.escapeClosesWindow = false

        XCTAssertFalse(viewModel.settings.closeWindowAfterSelection)
        XCTAssertFalse(viewModel.settings.escapeClosesWindow)
        XCTAssertEqual(savedSettings.last?.escapeClosesWindow, false)
    }

    func testRetentionPolicySupportsForeverAndCustomDays() {
        var cleanupCalls = 0
        let viewModel = SettingsViewModel(retentionDaysDidChange: { _ in cleanupCalls += 1 })

        viewModel.retentionPolicy = .forever
        XCTAssertEqual(viewModel.settings.retentionPolicy, .forever)

        viewModel.customRetentionDaysText = "90"
        viewModel.applyCustomRetentionDays()

        XCTAssertEqual(viewModel.settings.retentionPolicy, .days(90))
        XCTAssertEqual(cleanupCalls, 2)
        XCTAssertNil(viewModel.lastErrorMessage)
    }

    func testInvalidCustomRetentionDaysDoesNotOverwriteSetting() {
        let viewModel = SettingsViewModel()
        viewModel.customRetentionDaysText = "0"

        viewModel.applyCustomRetentionDays()

        XCTAssertEqual(viewModel.settings.retentionPolicy, .days(30))
        XCTAssertEqual(viewModel.lastErrorMessage, "请输入大于 0 的保留天数。")
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
    func testPopupSelectionCopyOnlyDoesNotSendPasteCommand() throws {
        let recorder = AppEnvironmentCallRecorder()
        let item = ClipboardItem.text("Saved text")
        let store = AppEnvironmentFakeStore(items: [item], recorder: recorder)
        let pasteboard = AppEnvironmentFakePasteboardWriter(recorder: recorder)
        let sender = AppEnvironmentFakePasteEventSender(recorder: recorder, onSend: {})
        let pasteService = PasteService(pasteboard: pasteboard, pasteEventSender: sender)
        let presenter = AppEnvironmentFakeSearchWindowPresenter(recorder: recorder)
        var settings = AppSettings.default
        settings.selectionAction = .copyOnly
        let environment = AppEnvironment(
            store: store,
            pasteService: pasteService,
            searchWindowPresenter: presenter,
            settings: settings
        )

        environment.openSearch()
        recorder.calls.removeAll()
        try XCTUnwrap(presenter.onPaste)(item)

        XCTAssertEqual(pasteboard.writtenText, "Saved text")
        XCTAssertFalse(recorder.calls.contains("sendPasteCommand"))
        XCTAssertTrue(recorder.calls.contains("orderOut"))
        XCTAssertNotNil(try store.fetchAll().first?.lastUsedAt)
    }

    @MainActor
    func testPopupSelectionCanKeepWindowOpenAfterCopyOnly() throws {
        let recorder = AppEnvironmentCallRecorder()
        let item = ClipboardItem.text("Saved text")
        let store = AppEnvironmentFakeStore(items: [item], recorder: recorder)
        let pasteboard = AppEnvironmentFakePasteboardWriter(recorder: recorder)
        let sender = AppEnvironmentFakePasteEventSender(recorder: recorder, onSend: {})
        let pasteService = PasteService(pasteboard: pasteboard, pasteEventSender: sender)
        let presenter = AppEnvironmentFakeSearchWindowPresenter(recorder: recorder)
        var settings = AppSettings.default
        settings.selectionAction = .copyOnly
        settings.closeWindowAfterSelection = false
        let environment = AppEnvironment(
            store: store,
            pasteService: pasteService,
            searchWindowPresenter: presenter,
            settings: settings
        )

        environment.openSearch()
        recorder.calls.removeAll()
        try XCTUnwrap(presenter.onPaste)(item)

        XCTAssertEqual(pasteboard.writtenText, "Saved text")
        XCTAssertFalse(recorder.calls.contains("sendPasteCommand"))
        XCTAssertFalse(recorder.calls.contains("orderOut"))
        XCTAssertNotNil(try store.fetchAll().first?.lastUsedAt)
    }

    @MainActor
    func testOpenSearchPassesProvidedPreviousApplicationToPresenter() {
        let recorder = AppEnvironmentCallRecorder()
        let presenter = AppEnvironmentFakeSearchWindowPresenter(recorder: recorder)
        let environment = AppEnvironment(searchWindowPresenter: presenter)

        environment.openSearch(previousApplication: .current)

        XCTAssertEqual(recorder.calls, ["showWithPreviousApplication"])
    }

    @MainActor
    func testOpenSearchPassesToolbarActionsToPresenter() throws {
        let recorder = AppEnvironmentCallRecorder()
        let item = ClipboardItem.text("Saved text")
        let store = AppEnvironmentFakeStore(items: [item], recorder: recorder)
        let searchPresenter = AppEnvironmentFakeSearchWindowPresenter(recorder: recorder)
        let settingsPresenter = AppEnvironmentFakeSettingsWindowPresenter(recorder: recorder)
        let environment = AppEnvironment(
            store: store,
            searchWindowPresenter: searchPresenter,
            settingsWindowPresenter: settingsPresenter,
            storageUsageProvider: {
                recorder.record("storageUsage")
                return 0
            }
        )

        environment.openSearch()
        recorder.calls.removeAll()
        try XCTUnwrap(searchPresenter.onOpenSettings)()
        try XCTUnwrap(searchPresenter.onClearNonFavorites)()
        try XCTUnwrap(searchPresenter.onClearAll)()

        XCTAssertEqual(
            recorder.calls,
            [
                "storageUsage",
                "showSettings",
                "fetchAll",
                "fetchAll",
                "fetchAll",
                "storageUsage",
                "fetchAll",
                "fetchAll",
                "storageUsage"
            ]
        )
        XCTAssertTrue(try store.fetchAll().isEmpty)
    }

    @MainActor
    func testOpenSearchPassesRecordingPauseBindingToPresenter() throws {
        let recorder = AppEnvironmentCallRecorder()
        let presenter = AppEnvironmentFakeSearchWindowPresenter(recorder: recorder)
        let environment = AppEnvironment(
            isRecordingPaused: false,
            searchWindowPresenter: presenter
        )

        environment.openSearch()
        XCTAssertEqual(presenter.isRecordingPaused?.wrappedValue, false)

        try XCTUnwrap(presenter.isRecordingPaused).wrappedValue = true

        XCTAssertTrue(environment.isRecordingPaused)
    }

    @MainActor
    func testOpenSettingsRefreshesStorageUsageAndShowsSettingsPresenter() {
        let recorder = AppEnvironmentCallRecorder()
        let presenter = AppEnvironmentFakeSettingsWindowPresenter(recorder: recorder)
        let environment = AppEnvironment(
            settingsWindowPresenter: presenter,
            storageUsageProvider: {
                recorder.record("storageUsage")
                return 42
            }
        )
        recorder.calls.removeAll()

        environment.openSettings()

        XCTAssertEqual(environment.settingsViewModel.storageUsageBytes, 42)
        XCTAssertEqual(recorder.calls, ["storageUsage", "showSettings"])
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

@MainActor
final class SearchWindowPresenterTests: XCTestCase {
    private let autosaveDefaultsKey = "NSWindow Frame ClipboardHistorySearchWindow"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: autosaveDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: autosaveDefaultsKey)
        super.tearDown()
    }

    func testSearchWindowHidesWhenInactiveAndAutosavesFrame() {
        let presenter = SearchWindowPresenter()
        let viewModel = ClipboardHistoryViewModel(store: AppEnvironmentFakeStore(items: []))

        presenter.show(
            viewModel: viewModel,
            previousApplication: nil,
            escapeClosesWindow: true,
            isRecordingPaused: .constant(false),
            onClose: {},
            onOpenSettings: {},
            onClearNonFavorites: {},
            onClearAll: {},
            onPaste: { _ in },
            onCopy: { _ in },
            onDelete: { _ in }
        )
        defer { presenter.orderOut() }

        let panel = NSApp.windows
            .compactMap { $0 as? NSPanel }
            .first { $0.title == "剪贴板历史" }

        XCTAssertNotNil(panel)
        XCTAssertEqual(panel?.frameAutosaveName, NSWindow.FrameAutosaveName("ClipboardHistorySearchWindow"))
        XCTAssertEqual(panel?.hidesOnDeactivate, false)
        XCTAssertGreaterThanOrEqual(panel?.minSize.width ?? 0, 520)
        XCTAssertGreaterThanOrEqual(panel?.minSize.height ?? 0, 360)
    }

    func testOrderOutSavesCurrentWindowFrame() throws {
        let presenter = SearchWindowPresenter()
        let viewModel = ClipboardHistoryViewModel(store: AppEnvironmentFakeStore(items: []))

        presenter.show(
            viewModel: viewModel,
            previousApplication: nil,
            escapeClosesWindow: true,
            isRecordingPaused: .constant(false),
            onClose: {},
            onOpenSettings: {},
            onClearNonFavorites: {},
            onClearAll: {},
            onPaste: { _ in },
            onCopy: { _ in },
            onDelete: { _ in }
        )

        let panel = try XCTUnwrap(
            NSApp.windows
                .compactMap { $0 as? NSPanel }
                .first { $0.title == "剪贴板历史" }
        )
        panel.setFrame(NSRect(x: 120, y: 140, width: 620, height: 520), display: false)

        presenter.orderOut()

        XCTAssertNotNil(UserDefaults.standard.string(forKey: autosaveDefaultsKey))
    }

    func testNewSearchWindowRestoresSavedSize() throws {
        let firstPresenter = SearchWindowPresenter()
        let firstViewModel = ClipboardHistoryViewModel(store: AppEnvironmentFakeStore(items: []))

        firstPresenter.show(
            viewModel: firstViewModel,
            previousApplication: nil,
            escapeClosesWindow: true,
            isRecordingPaused: .constant(false),
            onClose: {},
            onOpenSettings: {},
            onClearNonFavorites: {},
            onClearAll: {},
            onPaste: { _ in },
            onCopy: { _ in },
            onDelete: { _ in }
        )

        let firstPanel = try XCTUnwrap(
            NSApp.windows
                .compactMap { $0 as? NSPanel }
                .first { $0.title == "剪贴板历史" }
        )
        firstPanel.setFrame(NSRect(x: 120, y: 140, width: 640, height: 560), display: false)
        firstPresenter.orderOut()

        let secondPresenter = SearchWindowPresenter()
        let secondViewModel = ClipboardHistoryViewModel(store: AppEnvironmentFakeStore(items: []))
        secondPresenter.show(
            viewModel: secondViewModel,
            previousApplication: nil,
            escapeClosesWindow: true,
            isRecordingPaused: .constant(false),
            onClose: {},
            onOpenSettings: {},
            onClearNonFavorites: {},
            onClearAll: {},
            onPaste: { _ in },
            onCopy: { _ in },
            onDelete: { _ in }
        )
        defer { secondPresenter.orderOut() }

        let secondPanel = try XCTUnwrap(
            NSApp.windows
                .compactMap { $0 as? NSPanel }
                .first { $0.title == "剪贴板历史" && $0.isVisible }
        )

        XCTAssertEqual(secondPanel.frame.width, 640, accuracy: 1)
        XCTAssertEqual(secondPanel.frame.height, 560, accuracy: 1)
    }
}

@MainActor
final class SettingsWindowPresenterTests: XCTestCase {
    func testSettingsWindowUsesCompactWidth() throws {
        let presenter = SettingsWindowPresenter()
        let environment = AppEnvironment()

        presenter.show(environment: environment)
        defer {
            NSApp.windows
                .first { $0.title == "剪贴板助手设置" }?
                .close()
        }

        let window = try XCTUnwrap(
            NSApp.windows.first { $0.title == "剪贴板助手设置" }
        )

        XCTAssertLessThanOrEqual(window.frame.width, 548)
        XCTAssertEqual(window.minSize.width, 480, accuracy: 1)
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
    private(set) var onOpenSettings: (() -> Void)?
    private(set) var onClearNonFavorites: (() -> Void)?
    private(set) var onClearAll: (() -> Void)?
    private(set) var isRecordingPaused: Binding<Bool>?

    init(recorder: AppEnvironmentCallRecorder) {
        self.recorder = recorder
    }

    func show(
        viewModel: ClipboardHistoryViewModel,
        previousApplication: NSRunningApplication?,
        escapeClosesWindow: Bool,
        isRecordingPaused: Binding<Bool>,
        onClose: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onClearNonFavorites: @escaping () -> Void,
        onClearAll: @escaping () -> Void,
        onPaste: @escaping (ClipboardItem) -> Void,
        onCopy: @escaping (ClipboardItem) -> Void,
        onDelete: @escaping (ClipboardItem) -> Void
    ) {
        recorder.record(previousApplication == nil ? "show" : "showWithPreviousApplication")
        self.isRecordingPaused = isRecordingPaused
        self.onOpenSettings = onOpenSettings
        self.onClearNonFavorites = onClearNonFavorites
        self.onClearAll = onClearAll
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

@MainActor
private final class AppEnvironmentFakeSettingsWindowPresenter: SettingsWindowPresenting {
    private let recorder: AppEnvironmentCallRecorder

    init(recorder: AppEnvironmentCallRecorder) {
        self.recorder = recorder
    }

    func show(environment: AppEnvironment) {
        recorder.record("showSettings")
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
