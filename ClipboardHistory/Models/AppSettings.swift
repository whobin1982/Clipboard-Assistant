import Foundation

enum ClipboardSelectionAction: String, Codable, Equatable, CaseIterable, Identifiable {
    case paste
    case copyOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paste:
            return "自动粘贴"
        case .copyOnly:
            return "只复制到剪贴板"
        }
    }
}

enum RetentionPolicy: Equatable, Hashable {
    case days(Int)
    case forever
}

struct ShortcutDefinition: Codable, Equatable, Identifiable {
    static let customID = "custom"

    let id: String
    let displayName: String
    let keyCode: UInt16
    let requiresCommand: Bool
    let requiresOption: Bool
    let requiresControl: Bool
    let requiresShift: Bool

    static let optionCommandV = ShortcutDefinition(
        id: "option-command-v",
        displayName: "⌥ + ⌘ + V",
        keyCode: 9,
        requiresCommand: true,
        requiresOption: true,
        requiresControl: false,
        requiresShift: false
    )

    static let controlCommandV = ShortcutDefinition(
        id: "control-command-v",
        displayName: "⌃ + ⌘ + V",
        keyCode: 9,
        requiresCommand: true,
        requiresOption: false,
        requiresControl: true,
        requiresShift: false
    )

    static let shiftCommandV = ShortcutDefinition(
        id: "shift-command-v",
        displayName: "⇧ + ⌘ + V",
        keyCode: 9,
        requiresCommand: true,
        requiresOption: false,
        requiresControl: false,
        requiresShift: true
    )

    static let controlOptionV = ShortcutDefinition(
        id: "control-option-v",
        displayName: "⌃ + ⌥ + V",
        keyCode: 9,
        requiresCommand: false,
        requiresOption: true,
        requiresControl: true,
        requiresShift: false
    )

    static let available: [ShortcutDefinition] = [
        .optionCommandV,
        .controlCommandV,
        .shiftCommandV
    ]

    static func definition(for id: String) -> ShortcutDefinition {
        if id == controlOptionV.id {
            return .controlOptionV
        }
        return available.first { $0.id == id } ?? .optionCommandV
    }

    static func custom(
        displayName: String,
        keyCode: UInt16,
        requiresCommand: Bool,
        requiresOption: Bool,
        requiresControl: Bool,
        requiresShift: Bool
    ) -> ShortcutDefinition {
        ShortcutDefinition(
            id: customID,
            displayName: displayName,
            keyCode: keyCode,
            requiresCommand: requiresCommand,
            requiresOption: requiresOption,
            requiresControl: requiresControl,
            requiresShift: requiresShift
        )
    }

    static func definition(displayName: String) -> ShortcutDefinition {
        switch displayName {
        case "Option + Command + V":
            return .optionCommandV
        case "Control + Option + V":
            return .controlOptionV
        case "Control + Command + V":
            return .controlCommandV
        case "Shift + Command + V":
            return .shiftCommandV
        default:
            break
        }
        return available.first { $0.displayName == displayName } ?? .optionCommandV
    }
}

struct AppSettings: Codable, Equatable {
    var retentionDays: Int
    var launchAtLogin: Bool
    var shortcutID: String
    var customShortcut: ShortcutDefinition?
    var selectionAction: ClipboardSelectionAction
    var closeWindowAfterSelection: Bool
    var escapeClosesWindow: Bool
    var historyWindowStaysOpen: Bool
    var historyWindowAlwaysOnTop: Bool

    var retentionPolicy: RetentionPolicy {
        get {
            retentionDays <= 0 ? .forever : .days(retentionDays)
        }
        set {
            switch newValue {
            case .days(let days):
                retentionDays = max(1, days)
            case .forever:
                retentionDays = 0
            }
        }
    }

    var shortcut: ShortcutDefinition {
        if shortcutID == ShortcutDefinition.customID, let customShortcut {
            return customShortcut
        }
        return ShortcutDefinition.definition(for: shortcutID)
    }

    var shortcutDisplayName: String {
        shortcut.displayName
    }

    static let `default` = AppSettings(
        retentionDays: 30,
        launchAtLogin: false,
        shortcutID: ShortcutDefinition.optionCommandV.id,
        customShortcut: nil,
        selectionAction: .paste,
        closeWindowAfterSelection: true,
        escapeClosesWindow: true,
        historyWindowStaysOpen: false,
        historyWindowAlwaysOnTop: false
    )

    init(
        retentionDays: Int,
        launchAtLogin: Bool,
        shortcutID: String = ShortcutDefinition.optionCommandV.id,
        customShortcut: ShortcutDefinition? = nil,
        selectionAction: ClipboardSelectionAction = .paste,
        closeWindowAfterSelection: Bool = true,
        escapeClosesWindow: Bool = true,
        historyWindowStaysOpen: Bool = false,
        historyWindowAlwaysOnTop: Bool = false
    ) {
        self.retentionDays = retentionDays
        self.launchAtLogin = launchAtLogin
        self.shortcutID = shortcutID
        self.customShortcut = customShortcut
        self.selectionAction = selectionAction
        self.closeWindowAfterSelection = closeWindowAfterSelection
        self.escapeClosesWindow = escapeClosesWindow
        self.historyWindowStaysOpen = historyWindowStaysOpen
        self.historyWindowAlwaysOnTop = historyWindowAlwaysOnTop
    }

    init(
        retentionDays: Int,
        launchAtLogin: Bool,
        shortcutDisplayName: String
    ) {
        self.retentionDays = retentionDays
        self.launchAtLogin = launchAtLogin
        shortcutID = ShortcutDefinition.definition(displayName: shortcutDisplayName).id
        customShortcut = nil
        selectionAction = .paste
        closeWindowAfterSelection = true
        escapeClosesWindow = true
        historyWindowStaysOpen = false
        historyWindowAlwaysOnTop = false
    }

    private enum CodingKeys: String, CodingKey {
        case retentionDays
        case launchAtLogin
        case shortcutID
        case customShortcut
        case shortcutDisplayName
        case selectionAction
        case closeWindowAfterSelection
        case escapeClosesWindow
        case historyWindowStaysOpen
        case historyWindowAlwaysOnTop
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
        customShortcut = try container.decodeIfPresent(ShortcutDefinition.self, forKey: .customShortcut)
        if shortcutID == ShortcutDefinition.customID, customShortcut == nil {
            shortcutID = ShortcutDefinition.optionCommandV.id
        }
        selectionAction = try container.decodeIfPresent(ClipboardSelectionAction.self, forKey: .selectionAction) ?? .paste
        closeWindowAfterSelection = try container.decodeIfPresent(Bool.self, forKey: .closeWindowAfterSelection) ?? true
        escapeClosesWindow = try container.decodeIfPresent(Bool.self, forKey: .escapeClosesWindow) ?? true
        historyWindowStaysOpen = try container.decodeIfPresent(Bool.self, forKey: .historyWindowStaysOpen) ?? false
        historyWindowAlwaysOnTop = try container.decodeIfPresent(Bool.self, forKey: .historyWindowAlwaysOnTop) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(retentionDays, forKey: .retentionDays)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(shortcutID, forKey: .shortcutID)
        try container.encodeIfPresent(customShortcut, forKey: .customShortcut)
        try container.encode(shortcutDisplayName, forKey: .shortcutDisplayName)
        try container.encode(selectionAction, forKey: .selectionAction)
        try container.encode(closeWindowAfterSelection, forKey: .closeWindowAfterSelection)
        try container.encode(escapeClosesWindow, forKey: .escapeClosesWindow)
        try container.encode(historyWindowStaysOpen, forKey: .historyWindowStaysOpen)
        try container.encode(historyWindowAlwaysOnTop, forKey: .historyWindowAlwaysOnTop)
    }
}
