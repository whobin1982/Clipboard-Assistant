import XCTest
@testable import ClipboardHistory

final class ClipboardItemTests: XCTestCase {
    func testTextItemSearchesCaseInsensitively() {
        let item = ClipboardItem.text("Project Quote", copiedAt: Date(timeIntervalSince1970: 10))
        XCTAssertTrue(item.matches(query: "quote"))
        XCTAssertTrue(item.matches(query: "PROJECT"))
        XCTAssertFalse(item.matches(query: "invoice"))
    }

    func testImageItemDoesNotMatchTextQuery() {
        let item = ClipboardItem.image(
            imagePath: "/tmp/original.png",
            thumbnailPath: "/tmp/thumb.png",
            copiedAt: Date(timeIntervalSince1970: 10)
        )
        XCTAssertFalse(item.matches(query: "png"))
    }

    func testDefaultSettingsUseThirtyDayRetentionAndStartupOff() {
        let settings = AppSettings.default
        XCTAssertEqual(settings.retentionDays, 30)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertEqual(settings.shortcutDisplayName, "⌥ + ⌘ + V")
    }

    func testDefaultSettingsUseKeyboardPasteDefaults() {
        XCTAssertEqual(AppSettings.default.selectionAction, .paste)
        XCTAssertTrue(AppSettings.default.closeWindowAfterSelection)
        XCTAssertTrue(AppSettings.default.escapeClosesWindow)
        XCTAssertEqual(AppSettings.default.retentionPolicy, .days(30))
        XCTAssertEqual(AppSettings.default.shortcut.id, ShortcutDefinition.optionCommandV.id)
        XCTAssertFalse(AppSettings.default.historyWindowStaysOpen)
        XCTAssertFalse(AppSettings.default.historyWindowAlwaysOnTop)
    }

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

    func testPermanentRetentionPolicyStoresZeroRetentionDaysForCompatibility() {
        var settings = AppSettings.default
        settings.retentionPolicy = .forever

        XCTAssertEqual(settings.retentionDays, 0)
    }

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
