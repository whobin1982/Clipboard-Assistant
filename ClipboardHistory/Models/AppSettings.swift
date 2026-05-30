import Foundation

struct AppSettings: Codable, Equatable {
    var retentionDays: Int
    var launchAtLogin: Bool
    var shortcutDisplayName: String

    static let `default` = AppSettings(
        retentionDays: 30,
        launchAtLogin: false,
        shortcutDisplayName: "Option + Command + V"
    )
}
