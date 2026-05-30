import XCTest
@testable import ClipboardHistory

final class ClipboardHistorySmokeTests: XCTestCase {
    @MainActor
    func testEnvironmentStartsRecordingEnabled() {
        let environment = AppEnvironment.live()
        XCTAssertFalse(environment.isRecordingPaused)
    }
}
