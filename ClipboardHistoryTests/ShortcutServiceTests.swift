import XCTest
@testable import ClipboardHistory

final class ShortcutServiceTests: XCTestCase {
    func testDefaultSettingsUseDefaultShortcutDefinition() {
        XCTAssertEqual(AppSettings.default.shortcutID, ShortcutDefinition.optionCommandV.id)
        XCTAssertEqual(AppSettings.default.shortcutDisplayName, "Option + Command + V")
    }

    func testShortcutServiceUpdatesCurrentShortcut() {
        let service = ShortcutService(shortcut: .optionCommandV) {}

        service.updateShortcut(.controlOptionV)

        XCTAssertEqual(service.shortcutDisplayName, "Control + Option + V")
    }
}
