import Combine
import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    @Published var isRecordingPaused: Bool

    init(isRecordingPaused: Bool = false) {
        self.isRecordingPaused = isRecordingPaused
    }

    static func live() -> AppEnvironment {
        AppEnvironment()
    }
}
