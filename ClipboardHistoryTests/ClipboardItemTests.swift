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
        XCTAssertEqual(settings.shortcutDisplayName, "Option + Command + V")
    }
}
