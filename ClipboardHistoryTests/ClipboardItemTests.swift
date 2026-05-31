import XCTest
@testable import ClipboardHistory

/// 验证剪贴板记录模型、默认设置、旧设置兼容和快捷键定义。
final class ClipboardItemTests: XCTestCase {
    /// 文本记录搜索应忽略大小写。
    func testTextItemSearchesCaseInsensitively() {
        let item = ClipboardItem.text("Project Quote", copiedAt: Date(timeIntervalSince1970: 10))
        XCTAssertTrue(item.matches(query: "quote"))
        XCTAssertTrue(item.matches(query: "PROJECT"))
        XCTAssertFalse(item.matches(query: "invoice"))
    }

    /// 图片记录不参与文本搜索。
    func testImageItemDoesNotMatchTextQuery() {
        let item = ClipboardItem.image(
            imagePath: "/tmp/original.png",
            thumbnailPath: "/tmp/thumb.png",
            copiedAt: Date(timeIntervalSince1970: 10)
        )
        XCTAssertFalse(item.matches(query: "png"))
    }

    /// 默认设置保留 30 天、不开机启动，并使用默认快捷键。
    func testDefaultSettingsUseThirtyDayRetentionAndStartupOff() {
        let settings = AppSettings.default
        XCTAssertEqual(settings.retentionDays, 30)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertEqual(settings.shortcutDisplayName, "⌥ + ⌘ + V")
    }

    /// 默认粘贴行为和历史窗口行为应符合初始方案。
    func testDefaultSettingsUseKeyboardPasteDefaults() {
        XCTAssertEqual(AppSettings.default.selectionAction, .paste)
        XCTAssertTrue(AppSettings.default.closeWindowAfterSelection)
        XCTAssertTrue(AppSettings.default.escapeClosesWindow)
        XCTAssertEqual(AppSettings.default.retentionPolicy, .days(30))
        XCTAssertEqual(AppSettings.default.shortcut.id, ShortcutDefinition.optionCommandV.id)
        XCTAssertFalse(AppSettings.default.historyWindowStaysOpen)
        XCTAssertFalse(AppSettings.default.historyWindowAlwaysOnTop)
    }

    /// 旧设置缺少历史窗口行为字段时，应解码为关闭状态。
    func testMissingHistoryWindowSettingsDecodeToOff() throws {
        let json = """
        {
          "retentionDays": 30,
          "launchAtLogin": false,
          "shortcutID": "option-command-v",
          "selectionAction": "paste",
          "closeWindowAfterSelection": true,
          "escapeClosesWindow": true
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertFalse(settings.historyWindowStaysOpen)
        XCTAssertFalse(settings.historyWindowAlwaysOnTop)
    }

    /// 永久保留策略用 retentionDays = 0 存储，兼容旧数字字段。
    func testPermanentRetentionPolicyStoresZeroRetentionDaysForCompatibility() {
        var settings = AppSettings.default
        settings.retentionPolicy = .forever

        XCTAssertEqual(settings.retentionDays, 0)
    }

    /// 预设快捷键列表包含固定选项。
    func testAvailableShortcutsContainFixedOptions() {
        XCTAssertEqual(
            ShortcutDefinition.available.map(\.id),
            [
                ShortcutDefinition.optionCommandV.id,
                ShortcutDefinition.controlCommandV.id,
                ShortcutDefinition.shiftCommandV.id
            ]
        )
    }

    /// 选择自定义快捷键 id 时应使用保存过的自定义组合。
    func testCustomShortcutIsUsedWhenSelected() {
        let shortcut = ShortcutDefinition.custom(
            displayName: "⌃ + ⌥ + P",
            keyCode: 35,
            requiresCommand: false,
            requiresOption: true,
            requiresControl: true,
            requiresShift: false
        )
        let settings = AppSettings(
            retentionDays: 30,
            launchAtLogin: false,
            shortcutID: ShortcutDefinition.customID,
            customShortcut: shortcut
        )

        XCTAssertEqual(settings.shortcut, shortcut)
        XCTAssertEqual(settings.shortcutDisplayName, "⌃ + ⌥ + P")
    }
}
