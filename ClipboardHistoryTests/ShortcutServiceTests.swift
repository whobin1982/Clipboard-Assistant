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

        service.updateShortcut(.controlOptionV)

        XCTAssertEqual(service.shortcutDisplayName, "⌃ + ⌥ + V")
    }
}
