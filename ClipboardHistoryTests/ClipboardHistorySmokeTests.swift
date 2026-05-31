import XCTest
@testable import ClipboardHistory

/// 基础冒烟测试，确认真实应用环境能创建且默认状态合理。
final class ClipboardHistorySmokeTests: XCTestCase {
    /// 默认启动后自动记录不应处于暂停状态。
    @MainActor
    func testEnvironmentStartsRecordingEnabled() {
        let environment = AppEnvironment.live()
        XCTAssertFalse(environment.isRecordingPaused)
    }
}
