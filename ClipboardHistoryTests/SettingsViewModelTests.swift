import AppKit
import SwiftUI
import XCTest
@testable import ClipboardHistory

/// 验证设置视图模型会正确保存设置，并通知相关服务。
@MainActor
final class SettingsViewModelTests: XCTestCase {
    /// 选择预设快捷键时应持久化并通知快捷键服务。
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

    /// 快捷键注册失败时不应保存失败设置，并应在设置页显示错误。
    func testSelectingShortcutRegistrationFailureKeepsPreviousSettingAndShowsError() {
        var savedSettings: [AppSettings] = []
        let viewModel = SettingsViewModel(
            settingsDidChange: { savedSettings.append($0) },
            shortcutDidChange: { _ in throw SettingsViewModelTestError.shortcutRegistrationFailed }
        )

        viewModel.selectedShortcutID = ShortcutDefinition.controlCommandV.id

        XCTAssertEqual(viewModel.settings.shortcutID, ShortcutDefinition.optionCommandV.id)
        XCTAssertTrue(savedSettings.isEmpty)
        XCTAssertEqual(viewModel.lastErrorMessage, SettingsViewModelTestError.shortcutRegistrationFailed.localizedDescription)
    }

    /// 应用自定义快捷键时应保存到 customShortcut，并通知快捷键服务。
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

    /// 已存在自定义快捷键时，再次选择 custom id 不应丢失录制结果。
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

    /// 改变“点击后动作”应写入设置。
    func testChangingSelectionActionPersistsSettings() {
        var savedSettings: [AppSettings] = []
        let viewModel = SettingsViewModel(settingsDidChange: { savedSettings.append($0) })

        viewModel.selectionAction = .copyOnly

        XCTAssertEqual(viewModel.settings.selectionAction, .copyOnly)
        XCTAssertEqual(savedSettings.last?.selectionAction, .copyOnly)
    }

    /// 改变关闭窗口和 Esc 行为应写入设置。
    func testChangingCloseAndEscapeSettingsPersistsSettings() {
        var savedSettings: [AppSettings] = []
        let viewModel = SettingsViewModel(settingsDidChange: { savedSettings.append($0) })

        viewModel.closeWindowAfterSelection = false
        viewModel.escapeClosesWindow = false

        XCTAssertFalse(viewModel.settings.closeWindowAfterSelection)
        XCTAssertFalse(viewModel.settings.escapeClosesWindow)
        XCTAssertEqual(savedSettings.last?.escapeClosesWindow, false)
    }

    /// 改变常驻和置顶行为应写入设置。
    func testChangingHistoryWindowBehaviorPersistsSettings() {
        var savedSettings: [AppSettings] = []
        let viewModel = SettingsViewModel(settingsDidChange: { savedSettings.append($0) })

        viewModel.historyWindowStaysOpen = true
        viewModel.historyWindowAlwaysOnTop = true

        XCTAssertTrue(viewModel.settings.historyWindowStaysOpen)
        XCTAssertTrue(viewModel.settings.historyWindowAlwaysOnTop)
        XCTAssertEqual(savedSettings.last?.historyWindowStaysOpen, true)
        XCTAssertEqual(savedSettings.last?.historyWindowAlwaysOnTop, true)
    }

    /// 保留策略支持永久保留和自定义天数，并触发清理回调。
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

    /// 非法自定义保留天数不应覆盖原设置。
    func testInvalidCustomRetentionDaysDoesNotOverwriteSetting() {
        let viewModel = SettingsViewModel()
        viewModel.customRetentionDaysText = "0"

        viewModel.applyCustomRetentionDays()

        XCTAssertEqual(viewModel.settings.retentionPolicy, .days(30))
        XCTAssertEqual(viewModel.lastErrorMessage, "请输入大于 0 的保留天数。")
    }
}

/// 验证 AppEnvironment 对窗口、设置、复制粘贴、删除和清理动作的编排。
final class AppEnvironmentTests: XCTestCase {
    private var temporaryDirectory: URL!

    /// 每个测试准备独立临时目录，供图片文件测试使用。
    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppEnvironmentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    /// 测试结束后清理临时目录。
    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    /// 删除图片历史时应同时删除对应的原图和缩略图文件。
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

    /// 右键菜单粘贴路径应直接复制并发送粘贴，不依赖历史窗口 presenter。
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

    /// 历史窗口粘贴路径应复制、标记使用、关闭窗口、消费粘贴目标并发送粘贴。
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

    /// 图片记录从历史窗口粘贴时应写入图片归档并发送粘贴。
    @MainActor
    func testPopupPasteImageCopiesImageMarksUsedAndSendsPaste() async throws {
        let pasteSent = expectation(description: "paste command sent")
        let recorder = AppEnvironmentCallRecorder()
        let imageURL = temporaryDirectory.appendingPathComponent("saved-image.png")
        try XCTUnwrap(makeTestImage().pngData).write(to: imageURL)
        let item = ClipboardItem.image(imagePath: imageURL.path, thumbnailPath: imageURL.path)
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
        XCTAssertNotNil(pasteboard.writtenImageArchive)
        XCTAssertNil(environment.lastErrorMessage)
        XCTAssertEqual(
            recorder.calls,
            [
                "writeImage",
                "insert",
                "fetchAll",
                "orderOut",
                "consumePreviousApplication",
                "sendPasteCommand"
            ]
        )
        XCTAssertNotNil(try store.fetchAll().first?.lastUsedAt)
    }

    /// 选择“只复制到剪贴板”时不发送自动粘贴快捷键。
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

    /// 关闭“选择后关闭窗口”时，只复制模式不应关闭历史窗口。
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

    /// 打开历史窗口时应把外部传入的前台应用交给 presenter。
    @MainActor
    func testOpenSearchPassesProvidedPreviousApplicationToPresenter() {
        let recorder = AppEnvironmentCallRecorder()
        let presenter = AppEnvironmentFakeSearchWindowPresenter(recorder: recorder)
        let environment = AppEnvironment(searchWindowPresenter: presenter)

        environment.openSearch(previousApplication: .current)

        XCTAssertEqual(recorder.calls, ["showWithPreviousApplication"])
    }

    /// 历史窗口工具栏按钮应连接到设置、清理非收藏和清理全部动作。
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

    /// 历史窗口中的自动记录开关应绑定到 AppEnvironment。
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

    /// 自动记录开关的共享状态应在环境和窗口之间双向同步。
    @MainActor
    func testOpenSearchPassesLiveRecordingPauseStateToPresenter() throws {
        let recorder = AppEnvironmentCallRecorder()
        let presenter = AppEnvironmentFakeSearchWindowPresenter(recorder: recorder)
        let environment = AppEnvironment(
            isRecordingPaused: false,
            searchWindowPresenter: presenter
        )

        environment.openSearch()
        let recordingPauseState = try XCTUnwrap(presenter.recordingPauseState)
        XCTAssertFalse(recordingPauseState.isPaused)

        environment.isRecordingPaused = true
        XCTAssertTrue(recordingPauseState.isPaused)

        try XCTUnwrap(presenter.isRecordingPaused).wrappedValue = false
        XCTAssertFalse(recordingPauseState.isPaused)
        XCTAssertFalse(environment.isRecordingPaused)
    }

    /// 改变暂停记录状态时应同步持久化到设置。
    @MainActor
    func testChangingRecordingPausePersistsToSettings() {
        var savedSettings: [AppSettings] = []
        let environment = AppEnvironment(
            isRecordingPaused: false,
            settingsDidChange: { savedSettings.append($0) }
        )

        environment.isRecordingPaused = true

        XCTAssertEqual(savedSettings.last?.isRecordingPaused, true)
        XCTAssertTrue(environment.settingsViewModel.settings.isRecordingPaused)
    }

    /// 历史窗口常驻和置顶绑定应透传到 presenter。
    @MainActor
    func testOpenSearchPassesHistoryWindowBehaviorBindingsToPresenter() throws {
        let recorder = AppEnvironmentCallRecorder()
        let presenter = AppEnvironmentFakeSearchWindowPresenter(recorder: recorder)
        let environment = AppEnvironment(searchWindowPresenter: presenter)

        environment.openSearch()
        XCTAssertEqual(presenter.historyWindowStaysOpen?.wrappedValue, false)
        XCTAssertEqual(presenter.historyWindowAlwaysOnTop?.wrappedValue, false)

        try XCTUnwrap(presenter.historyWindowStaysOpen).wrappedValue = true
        try XCTUnwrap(presenter.historyWindowAlwaysOnTop).wrappedValue = true

        XCTAssertTrue(environment.settingsViewModel.settings.historyWindowStaysOpen)
        XCTAssertTrue(environment.settingsViewModel.settings.historyWindowAlwaysOnTop)
    }

    /// 打开设置前应刷新存储占用。
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

    /// 自动粘贴失败时，记录仍应已复制并标记使用，同时向用户展示错误。
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

/// 验证历史窗口 presenter 的 AppKit 窗口行为。
@MainActor
final class SearchWindowPresenterTests: XCTestCase {
    private let autosaveDefaultsKey = "NSWindow Frame ClipboardHistorySearchWindow"

    /// 测试前关闭遗留窗口并清空 frame autosave。
    override func setUp() {
        super.setUp()
        closeSearchWindows()
        UserDefaults.standard.removeObject(forKey: autosaveDefaultsKey)
    }

    /// 测试后清理窗口和保存的 frame，避免影响其他用例。
    override func tearDown() {
        closeSearchWindows()
        UserDefaults.standard.removeObject(forKey: autosaveDefaultsKey)
        super.tearDown()
    }

    /// 关闭标题为“剪贴板历史”的测试窗口。
    private func closeSearchWindows() {
        NSApp.windows
            .compactMap { $0 as? NSPanel }
            .filter { $0.title == "剪贴板历史" }
            .forEach { $0.close() }
    }

    /// 历史窗口应保持可见控制、最小尺寸和 frame 自动保存行为。
    func testSearchWindowHidesWhenInactiveAndAutosavesFrame() {
        let presenter = SearchWindowPresenter()
        let viewModel = ClipboardHistoryViewModel(store: AppEnvironmentFakeStore(items: []))

        presenter.show(
            viewModel: viewModel,
            previousApplication: nil,
            escapeClosesWindow: true,
            isRecordingPaused: .constant(false),
            recordingPauseState: RecordingPauseState(isPaused: false),
            historyWindowStaysOpen: .constant(false),
            historyWindowAlwaysOnTop: .constant(false),
            onClose: {},
            onWindowBehaviorChanged: { _ in },
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
            .first { $0.title == "剪贴板历史" && $0.isVisible }

        XCTAssertNotNil(panel)
        XCTAssertEqual(panel?.hidesOnDeactivate, false)
        XCTAssertGreaterThanOrEqual(panel?.minSize.width ?? 0, 520)
        XCTAssertGreaterThanOrEqual(panel?.minSize.height ?? 0, 360)
    }

    /// 历史窗口应禁用最大化和全屏相关行为。
    func testSearchWindowDisablesZoomAndFullscreen() throws {
        let presenter = SearchWindowPresenter()
        let viewModel = ClipboardHistoryViewModel(store: AppEnvironmentFakeStore(items: []))

        presenter.show(
            viewModel: viewModel,
            previousApplication: nil,
            escapeClosesWindow: true,
            isRecordingPaused: .constant(false),
            recordingPauseState: RecordingPauseState(isPaused: false),
            historyWindowStaysOpen: .constant(false),
            historyWindowAlwaysOnTop: .constant(false),
            onClose: {},
            onWindowBehaviorChanged: { _ in },
            onOpenSettings: {},
            onClearNonFavorites: {},
            onClearAll: {},
            onPaste: { _ in },
            onCopy: { _ in },
            onDelete: { _ in }
        )
        defer { presenter.orderOut() }

        let panel = try XCTUnwrap(
            NSApp.windows
                .compactMap { $0 as? NSPanel }
                .first { $0.title == "剪贴板历史" && $0.isVisible }
        )

        XCTAssertEqual(panel.standardWindowButton(.zoomButton)?.isEnabled, false)
        XCTAssertFalse(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(panel.collectionBehavior.contains(.fullScreenPrimary))
    }

    /// 标题栏三个模式按钮应更新绑定、窗口层级和选中状态。
    func testWindowModeTitlebarIconButtonsSetBindingsAndPanelLevel() throws {
        let presenter = SearchWindowPresenter()
        let viewModel = ClipboardHistoryViewModel(store: AppEnvironmentFakeStore(items: []))
        var staysOpen = false
        var alwaysOnTop = false
        var levelChanges: [Bool] = []

        presenter.show(
            viewModel: viewModel,
            previousApplication: nil,
            escapeClosesWindow: true,
            isRecordingPaused: .constant(false),
            recordingPauseState: RecordingPauseState(isPaused: false),
            historyWindowStaysOpen: Binding(
                get: { staysOpen },
                set: { staysOpen = $0 }
            ),
            historyWindowAlwaysOnTop: Binding(
                get: { alwaysOnTop },
                set: { alwaysOnTop = $0 }
            ),
            onClose: {},
            onWindowBehaviorChanged: { levelChanges.append($0) },
            onOpenSettings: {},
            onClearNonFavorites: {},
            onClearAll: {},
            onPaste: { _ in },
            onCopy: { _ in },
            onDelete: { _ in }
        )
        defer { presenter.orderOut() }

        let panel = try XCTUnwrap(
            NSApp.windows
                .compactMap { $0 as? NSPanel }
                .first { $0.title == "剪贴板历史" && $0.isVisible }
        )
        let modeButtons = panel.titlebarAccessoryViewControllers
            .compactMap { $0.view as? NSStackView }
            .flatMap(\.arrangedSubviews)
            .compactMap { $0 as? NSButton }
        let buttonsByIdentifier = Dictionary(uniqueKeysWithValues: modeButtons.compactMap { button in
            button.identifier.map { ($0.rawValue, button) }
        })
        let normalButton = try XCTUnwrap(buttonsByIdentifier["history-window-mode-normal"])
        let staysOpenButton = try XCTUnwrap(buttonsByIdentifier["history-window-mode-stays-open"])
        let alwaysOnTopButton = try XCTUnwrap(buttonsByIdentifier["history-window-mode-always-on-top"])

        XCTAssertEqual(modeButtons.count, 3)
        XCTAssertTrue(modeButtons.allSatisfy { $0.title.isEmpty && $0.image != nil })
        XCTAssertEqual(normalButton.toolTip, "普通窗口")
        XCTAssertEqual(staysOpenButton.toolTip, "常驻窗口")
        XCTAssertEqual(alwaysOnTopButton.toolTip, "置顶窗口")
        XCTAssertEqual(normalButton.state, .on)
        XCTAssertEqual(staysOpenButton.state, .off)
        XCTAssertEqual(alwaysOnTopButton.state, .off)
        XCTAssertEqual(normalButton.image?.accessibilityDescription, "普通（已选中）")
        XCTAssertEqual(staysOpenButton.image?.accessibilityDescription, "常驻")
        XCTAssertEqual(alwaysOnTopButton.image?.accessibilityDescription, "置顶")
        XCTAssertEqual(normalButton.contentTintColor, .controlAccentColor)
        XCTAssertEqual(staysOpenButton.contentTintColor, .secondaryLabelColor)
        XCTAssertEqual(alwaysOnTopButton.contentTintColor, .secondaryLabelColor)
        XCTAssertTrue(
            panel.titlebarAccessoryViewControllers
                .compactMap { $0.view as? NSPopUpButton }
                .isEmpty
        )

        _ = staysOpenButton.target?.perform(staysOpenButton.action, with: staysOpenButton)

        XCTAssertTrue(staysOpen)
        XCTAssertFalse(alwaysOnTop)
        XCTAssertEqual(panel.level, .normal)
        XCTAssertEqual(levelChanges, [false])
        XCTAssertEqual(normalButton.state, .off)
        XCTAssertEqual(staysOpenButton.state, .on)
        XCTAssertEqual(alwaysOnTopButton.state, .off)
        XCTAssertEqual(normalButton.image?.accessibilityDescription, "普通")
        XCTAssertEqual(staysOpenButton.image?.accessibilityDescription, "常驻（已选中）")
        XCTAssertEqual(alwaysOnTopButton.image?.accessibilityDescription, "置顶")
        XCTAssertEqual(normalButton.contentTintColor, .secondaryLabelColor)
        XCTAssertEqual(staysOpenButton.contentTintColor, .controlAccentColor)
        XCTAssertEqual(alwaysOnTopButton.contentTintColor, .secondaryLabelColor)

        _ = alwaysOnTopButton.target?.perform(alwaysOnTopButton.action, with: alwaysOnTopButton)

        XCTAssertTrue(staysOpen)
        XCTAssertTrue(alwaysOnTop)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertEqual(levelChanges, [false, true])
        XCTAssertEqual(normalButton.state, .off)
        XCTAssertEqual(staysOpenButton.state, .off)
        XCTAssertEqual(alwaysOnTopButton.state, .on)
        XCTAssertEqual(normalButton.image?.accessibilityDescription, "普通")
        XCTAssertEqual(staysOpenButton.image?.accessibilityDescription, "常驻")
        XCTAssertEqual(alwaysOnTopButton.image?.accessibilityDescription, "置顶（已选中）")
        XCTAssertEqual(normalButton.contentTintColor, .secondaryLabelColor)
        XCTAssertEqual(staysOpenButton.contentTintColor, .secondaryLabelColor)
        XCTAssertEqual(alwaysOnTopButton.contentTintColor, .controlAccentColor)

        _ = normalButton.target?.perform(normalButton.action, with: normalButton)

        XCTAssertFalse(staysOpen)
        XCTAssertFalse(alwaysOnTop)
        XCTAssertEqual(panel.level, .normal)
        XCTAssertEqual(levelChanges, [false, true, false])
        XCTAssertEqual(normalButton.state, .on)
        XCTAssertEqual(staysOpenButton.state, .off)
        XCTAssertEqual(alwaysOnTopButton.state, .off)
    }

    /// 置顶绑定应控制 NSPanel 的 level。
    func testAlwaysOnTopControlsPanelLevel() throws {
        let presenter = SearchWindowPresenter()
        let viewModel = ClipboardHistoryViewModel(store: AppEnvironmentFakeStore(items: []))

        presenter.show(
            viewModel: viewModel,
            previousApplication: nil,
            escapeClosesWindow: true,
            isRecordingPaused: .constant(false),
            recordingPauseState: RecordingPauseState(isPaused: false),
            historyWindowStaysOpen: .constant(false),
            historyWindowAlwaysOnTop: .constant(true),
            onClose: {},
            onWindowBehaviorChanged: { _ in },
            onOpenSettings: {},
            onClearNonFavorites: {},
            onClearAll: {},
            onPaste: { _ in },
            onCopy: { _ in },
            onDelete: { _ in }
        )
        defer { presenter.orderOut() }

        let panel = try XCTUnwrap(
            NSApp.windows
                .compactMap { $0 as? NSPanel }
                .first { $0.title == "剪贴板历史" && $0.isVisible }
        )

        XCTAssertEqual(panel.level, .floating)
        presenter.applyWindowBehavior(alwaysOnTop: false)
        XCTAssertEqual(panel.level, .normal)
    }

    /// 隐藏窗口时应保存当前 frame。
    func testOrderOutSavesCurrentWindowFrame() throws {
        let presenter = SearchWindowPresenter()
        let viewModel = ClipboardHistoryViewModel(store: AppEnvironmentFakeStore(items: []))

        presenter.show(
            viewModel: viewModel,
            previousApplication: nil,
            escapeClosesWindow: true,
            isRecordingPaused: .constant(false),
            recordingPauseState: RecordingPauseState(isPaused: false),
            historyWindowStaysOpen: .constant(false),
            historyWindowAlwaysOnTop: .constant(false),
            onClose: {},
            onWindowBehaviorChanged: { _ in },
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
                .first { $0.title == "剪贴板历史" && $0.isVisible }
        )
        panel.setFrame(NSRect(x: 120, y: 140, width: 620, height: 520), display: false)

        presenter.orderOut()

        XCTAssertNotNil(UserDefaults.standard.string(forKey: autosaveDefaultsKey))
    }

    /// 新建 presenter 时应恢复上一次保存的窗口尺寸。
    func testNewSearchWindowRestoresSavedSize() throws {
        let firstPresenter = SearchWindowPresenter()
        let firstViewModel = ClipboardHistoryViewModel(store: AppEnvironmentFakeStore(items: []))

        firstPresenter.show(
            viewModel: firstViewModel,
            previousApplication: nil,
            escapeClosesWindow: true,
            isRecordingPaused: .constant(false),
            recordingPauseState: RecordingPauseState(isPaused: false),
            historyWindowStaysOpen: .constant(false),
            historyWindowAlwaysOnTop: .constant(false),
            onClose: {},
            onWindowBehaviorChanged: { _ in },
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
                .first { $0.title == "剪贴板历史" && $0.isVisible }
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
            recordingPauseState: RecordingPauseState(isPaused: false),
            historyWindowStaysOpen: .constant(false),
            historyWindowAlwaysOnTop: .constant(false),
            onClose: {},
            onWindowBehaviorChanged: { _ in },
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

/// 验证设置窗口 presenter 的尺寸配置。
@MainActor
final class SettingsWindowPresenterTests: XCTestCase {
    /// 设置窗口应保持比历史窗口更窄的紧凑宽度。
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

/// AppEnvironment 测试用存储，记录关键调用顺序并模拟内存数据变化。
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

/// AppEnvironment 测试用历史窗口 presenter，捕获传入绑定和回调。
@MainActor
private final class AppEnvironmentFakeSearchWindowPresenter: SearchWindowPresenting {
    private let recorder: AppEnvironmentCallRecorder
    private(set) var onPaste: ((ClipboardItem) -> Void)?
    private(set) var onOpenSettings: (() -> Void)?
    private(set) var onClearNonFavorites: (() -> Void)?
    private(set) var onClearAll: (() -> Void)?
    private(set) var isRecordingPaused: Binding<Bool>?
    private(set) var recordingPauseState: RecordingPauseState?
    private(set) var historyWindowStaysOpen: Binding<Bool>?
    private(set) var historyWindowAlwaysOnTop: Binding<Bool>?

    init(recorder: AppEnvironmentCallRecorder) {
        self.recorder = recorder
    }

    func show(
        viewModel: ClipboardHistoryViewModel,
        previousApplication: NSRunningApplication?,
        escapeClosesWindow: Bool,
        isRecordingPaused: Binding<Bool>,
        recordingPauseState: RecordingPauseState,
        historyWindowStaysOpen: Binding<Bool>,
        historyWindowAlwaysOnTop: Binding<Bool>,
        onClose: @escaping () -> Void,
        onWindowBehaviorChanged: @escaping (Bool) -> Void,
        onOpenSettings: @escaping () -> Void,
        onClearNonFavorites: @escaping () -> Void,
        onClearAll: @escaping () -> Void,
        onPaste: @escaping (ClipboardItem) -> Void,
        onCopy: @escaping (ClipboardItem) -> Void,
        onDelete: @escaping (ClipboardItem) -> Void
    ) {
        recorder.record(previousApplication == nil ? "show" : "showWithPreviousApplication")
        self.isRecordingPaused = isRecordingPaused
        self.recordingPauseState = recordingPauseState
        self.historyWindowStaysOpen = historyWindowStaysOpen
        self.historyWindowAlwaysOnTop = historyWindowAlwaysOnTop
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

    func applyWindowBehavior(alwaysOnTop: Bool) {
        recorder.record(alwaysOnTop ? "applyAlwaysOnTop" : "applyNormalLevel")
    }
}

/// AppEnvironment 测试用设置窗口 presenter。
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

/// AppEnvironment 测试用剪贴板写入器。
private final class AppEnvironmentFakePasteboardWriter: PasteboardWriting {
    private let recorder: AppEnvironmentCallRecorder
    private(set) var writtenText: String?
    private(set) var writtenImageArchive: ClipboardImageArchive?

    init(recorder: AppEnvironmentCallRecorder) {
        self.recorder = recorder
    }

    func writeText(_ text: String) throws {
        writtenText = text
        recorder.record("writeText:\(text)")
    }

    func writeImageArchive(_ archive: ClipboardImageArchive) throws {
        writtenImageArchive = archive
        recorder.record("writeImage")
    }
}

/// AppEnvironment 测试用粘贴事件发送器。
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

/// 记录测试中的调用顺序。
private final class AppEnvironmentCallRecorder {
    var calls: [String] = []

    func record(_ call: String) {
        calls.append(call)
    }
}

/// 创建测试用图片。
private func makeTestImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 4, height: 4))
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: 4, height: 4).fill()
    image.unlockFocus()
    return image
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

/// SettingsViewModel 测试中使用的模拟错误。
private enum SettingsViewModelTestError: LocalizedError {
    case shortcutRegistrationFailed

    var errorDescription: String? {
        switch self {
        case .shortcutRegistrationFailed:
            return "快捷键注册失败"
        }
    }
}

/// AppEnvironment 测试中使用的模拟错误。
private enum AppEnvironmentTestError: Error {
    case pasteFailed
}
