import Carbon.HIToolbox
import XCTest
@testable import ClipboardHistory

/// 验证快捷键默认值和运行时更新逻辑。
final class ShortcutServiceTests: XCTestCase {
    /// 默认设置应使用 Option + Command + V。
    func testDefaultSettingsUseDefaultShortcutDefinition() {
        XCTAssertEqual(AppSettings.default.shortcutID, ShortcutDefinition.optionCommandV.id)
        XCTAssertEqual(AppSettings.default.shortcutDisplayName, "⌥ + ⌘ + V")
    }

    /// 更新快捷键后，展示名应同步变化。
    func testShortcutServiceUpdatesCurrentShortcut() {
        let service = ShortcutService(shortcut: .optionCommandV) {}

        XCTAssertNoThrow(try service.updateShortcut(.controlOptionV))

        XCTAssertEqual(service.shortcutDisplayName, "⌃ + ⌥ + V")
    }

    /// Carbon 返回注册失败时应抛出明确错误，而不是静默让快捷键失效。
    func testShortcutServiceThrowsWhenCarbonRegistrationFails() {
        let expectedStatus = OSStatus(eventHotKeyExistsErr)
        let service = ShortcutService(
            shortcut: .optionCommandV,
            openPopup: {},
            registerHotKeyHandler: { _, _, _ in expectedStatus }
        )

        XCTAssertThrowsError(try service.start()) { error in
            XCTAssertEqual(error as? ShortcutServiceError, .registrationFailed(expectedStatus))
        }
    }
}
