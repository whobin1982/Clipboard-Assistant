import Foundation

/// 用户选中历史记录后的动作：自动粘贴，或只复制到系统剪贴板。
enum ClipboardSelectionAction: String, Codable, Equatable, CaseIterable, Identifiable {
    case paste
    case copyOnly

    var id: String { rawValue }

    /// 设置页面展示用标题。
    var title: String {
        switch self {
        case .paste:
            return "自动粘贴"
        case .copyOnly:
            return "只复制到剪贴板"
        }
    }
}

/// 历史记录保留策略，永久保留用独立枚举表达，避免用魔法数字暴露给界面层。
enum RetentionPolicy: Equatable, Hashable {
    case days(Int)
    case forever
}

/// 全局快捷键定义，保存 Carbon 注册需要的 keyCode 和修饰键组合。
struct ShortcutDefinition: Codable, Equatable, Identifiable {
    /// 自定义快捷键的固定 id，真实按键组合存放在 customShortcut 中。
    static let customID = "custom"

    let id: String
    let displayName: String
    let keyCode: UInt16
    let requiresCommand: Bool
    let requiresOption: Bool
    let requiresControl: Bool
    let requiresShift: Bool

    /// 默认快捷键：Option + Command + V。
    static let optionCommandV = ShortcutDefinition(
        id: "option-command-v",
        displayName: "⌥ + ⌘ + V",
        keyCode: 9,
        requiresCommand: true,
        requiresOption: true,
        requiresControl: false,
        requiresShift: false
    )

    /// 备选快捷键：Control + Command + V。
    static let controlCommandV = ShortcutDefinition(
        id: "control-command-v",
        displayName: "⌃ + ⌘ + V",
        keyCode: 9,
        requiresCommand: true,
        requiresOption: false,
        requiresControl: true,
        requiresShift: false
    )

    /// 备选快捷键：Shift + Command + V。
    static let shiftCommandV = ShortcutDefinition(
        id: "shift-command-v",
        displayName: "⇧ + ⌘ + V",
        keyCode: 9,
        requiresCommand: true,
        requiresOption: false,
        requiresControl: false,
        requiresShift: true
    )

    /// 历史兼容和测试使用的快捷键：Control + Option + V。
    static let controlOptionV = ShortcutDefinition(
        id: "control-option-v",
        displayName: "⌃ + ⌥ + V",
        keyCode: 9,
        requiresCommand: false,
        requiresOption: true,
        requiresControl: true,
        requiresShift: false
    )

    /// 设置页直接展示的预设快捷键。
    static let available: [ShortcutDefinition] = [
        .optionCommandV,
        .controlCommandV,
        .shiftCommandV
    ]

    /// 根据保存的 id 找到快捷键定义；未知 id 回退到默认快捷键。
    static func definition(for id: String) -> ShortcutDefinition {
        if id == controlOptionV.id {
            return .controlOptionV
        }
        return available.first { $0.id == id } ?? .optionCommandV
    }

    /// 构造用户录制的自定义快捷键。
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

    /// 从旧版本保存的显示名迁移到结构化快捷键定义。
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

/// 所有用户可配置项的持久化模型。
struct AppSettings: Codable, Equatable {
    /// 历史记录保留天数；0 表示永久保留，用于兼容旧存储格式。
    var retentionDays: Int
    var launchAtLogin: Bool
    var shortcutID: String
    var customShortcut: ShortcutDefinition?
    var selectionAction: ClipboardSelectionAction
    var closeWindowAfterSelection: Bool
    var escapeClosesWindow: Bool
    var historyWindowStaysOpen: Bool
    var historyWindowAlwaysOnTop: Bool
    var isRecordingPaused: Bool

    /// 界面层使用的保留策略，将 0 天转换成永久保留。
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

    /// 当前实际生效的快捷键；如果自定义数据缺失则回退预设。
    var shortcut: ShortcutDefinition {
        if shortcutID == ShortcutDefinition.customID, let customShortcut {
            return customShortcut
        }
        return ShortcutDefinition.definition(for: shortcutID)
    }

    /// 当前快捷键的展示文本。
    var shortcutDisplayName: String {
        shortcut.displayName
    }

    /// 新用户和损坏设置的默认值。
    static let `default` = AppSettings(
        retentionDays: 30,
        launchAtLogin: false,
        shortcutID: ShortcutDefinition.optionCommandV.id,
        customShortcut: nil,
        selectionAction: .paste,
        closeWindowAfterSelection: true,
        escapeClosesWindow: true,
        historyWindowStaysOpen: false,
        historyWindowAlwaysOnTop: false,
        isRecordingPaused: false
    )

    /// 当前版本使用的完整初始化方法。
    init(
        retentionDays: Int,
        launchAtLogin: Bool,
        shortcutID: String = ShortcutDefinition.optionCommandV.id,
        customShortcut: ShortcutDefinition? = nil,
        selectionAction: ClipboardSelectionAction = .paste,
        closeWindowAfterSelection: Bool = true,
        escapeClosesWindow: Bool = true,
        historyWindowStaysOpen: Bool = false,
        historyWindowAlwaysOnTop: Bool = false,
        isRecordingPaused: Bool = false
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
        self.isRecordingPaused = isRecordingPaused
    }

    /// 旧版本兼容初始化：只保存快捷键展示名时使用。
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
        isRecordingPaused = false
    }

    /// 同时保留新旧字段，保证旧版本升级后能平滑解码。
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
        case isRecordingPaused
    }

    /// 自定义解码用于兼容旧设置文件，并为新增字段提供默认值。
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
        isRecordingPaused = try container.decodeIfPresent(Bool.self, forKey: .isRecordingPaused) ?? false
    }

    /// 编码时同时写入 shortcutID 和 shortcutDisplayName，便于旧版本或人工查看。
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
        try container.encode(isRecordingPaused, forKey: .isRecordingPaused)
    }
}
