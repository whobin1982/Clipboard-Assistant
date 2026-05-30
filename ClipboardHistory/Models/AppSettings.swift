import Foundation

struct ShortcutDefinition: Codable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let keyCode: UInt16
    let requiresCommand: Bool
    let requiresOption: Bool
    let requiresControl: Bool
    let requiresShift: Bool

    static let optionCommandV = ShortcutDefinition(
        id: "option-command-v",
        displayName: "Option + Command + V",
        keyCode: 9,
        requiresCommand: true,
        requiresOption: true,
        requiresControl: false,
        requiresShift: false
    )

    static let controlOptionV = ShortcutDefinition(
        id: "control-option-v",
        displayName: "Control + Option + V",
        keyCode: 9,
        requiresCommand: false,
        requiresOption: true,
        requiresControl: true,
        requiresShift: false
    )

    static let available: [ShortcutDefinition] = [
        .optionCommandV,
        .controlOptionV
    ]

    static func definition(for id: String) -> ShortcutDefinition {
        available.first { $0.id == id } ?? .optionCommandV
    }

    static func definition(displayName: String) -> ShortcutDefinition {
        available.first { $0.displayName == displayName } ?? .optionCommandV
    }
}

struct AppSettings: Codable, Equatable {
    var retentionDays: Int
    var launchAtLogin: Bool
    var shortcutID: String

    var shortcut: ShortcutDefinition {
        ShortcutDefinition.definition(for: shortcutID)
    }

    var shortcutDisplayName: String {
        shortcut.displayName
    }

    static let `default` = AppSettings(
        retentionDays: 30,
        launchAtLogin: false,
        shortcutID: ShortcutDefinition.optionCommandV.id
    )

    init(
        retentionDays: Int,
        launchAtLogin: Bool,
        shortcutID: String = ShortcutDefinition.optionCommandV.id
    ) {
        self.retentionDays = retentionDays
        self.launchAtLogin = launchAtLogin
        self.shortcutID = shortcutID
    }

    init(
        retentionDays: Int,
        launchAtLogin: Bool,
        shortcutDisplayName: String
    ) {
        self.retentionDays = retentionDays
        self.launchAtLogin = launchAtLogin
        shortcutID = ShortcutDefinition.definition(displayName: shortcutDisplayName).id
    }

    private enum CodingKeys: String, CodingKey {
        case retentionDays
        case launchAtLogin
        case shortcutID
        case shortcutDisplayName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        retentionDays = try container.decode(Int.self, forKey: .retentionDays)
        launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        if let shortcutID = try container.decodeIfPresent(String.self, forKey: .shortcutID) {
            self.shortcutID = shortcutID
        } else if let displayName = try container.decodeIfPresent(String.self, forKey: .shortcutDisplayName) {
            shortcutID = ShortcutDefinition.definition(displayName: displayName).id
        } else {
            shortcutID = ShortcutDefinition.optionCommandV.id
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(retentionDays, forKey: .retentionDays)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(shortcutID, forKey: .shortcutID)
        try container.encode(shortcutDisplayName, forKey: .shortcutDisplayName)
    }
}
