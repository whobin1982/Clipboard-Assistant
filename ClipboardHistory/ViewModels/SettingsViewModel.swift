import Foundation

/// 设置页的状态和业务操作，负责把 UI 修改同步到 AppSettings。
@MainActor
final class SettingsViewModel: ObservableObject {
    /// 当前完整设置。
    @Published var settings: AppSettings
    /// 图片历史文件占用空间。
    @Published var storageUsageBytes: Int64
    /// 自定义保留天数输入框文本。
    @Published var customRetentionDaysText: String
    /// 设置操作失败时展示的错误。
    @Published private(set) var lastErrorMessage: String?

    private let clearNonFavoritesAction: () throws -> Void
    private let clearAllAction: () throws -> Void
    private let storageUsageProvider: () -> Int64
    private let settingsDidChange: (AppSettings) -> Void
    private let launchAtLoginDidChange: (Bool) throws -> Void
    private let retentionDaysDidChange: (AppSettings) throws -> Void
    private var shortcutDidChange: (ShortcutDefinition) throws -> Void

    init(
        settings: AppSettings = .default,
        storageUsageBytes: Int64 = 0,
        storageUsageProvider: @escaping () -> Int64 = { 0 },
        settingsDidChange: @escaping (AppSettings) -> Void = { _ in },
        launchAtLoginDidChange: @escaping (Bool) throws -> Void = { _ in },
        retentionDaysDidChange: @escaping (AppSettings) throws -> Void = { _ in },
        shortcutDidChange: @escaping (ShortcutDefinition) throws -> Void = { _ in },
        clearNonFavorites: @escaping () throws -> Void = {},
        clearAll: @escaping () throws -> Void = {}
    ) {
        self.settings = settings
        self.storageUsageBytes = storageUsageBytes
        customRetentionDaysText = settings.retentionDays > 0 ? "\(settings.retentionDays)" : ""
        self.storageUsageProvider = storageUsageProvider
        self.settingsDidChange = settingsDidChange
        self.launchAtLoginDidChange = launchAtLoginDidChange
        self.retentionDaysDidChange = retentionDaysDidChange
        self.shortcutDidChange = shortcutDidChange
        clearNonFavoritesAction = clearNonFavorites
        clearAllAction = clearAll
    }

    /// 直接设置保留天数，并触发过期清理。
    var retentionDays: Int {
        get { settings.retentionDays }
        set {
            settings.retentionDays = max(1, newValue)
            settingsDidChange(settings)
            do {
                try retentionDaysDidChange(settings)
                refreshStorageUsage()
                lastErrorMessage = nil
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    /// 选择记录后的动作。
    var selectionAction: ClipboardSelectionAction {
        get { settings.selectionAction }
        set {
            settings.selectionAction = newValue
            settingsDidChange(settings)
            lastErrorMessage = nil
        }
    }

    /// 选中记录后是否关闭历史窗口。
    var closeWindowAfterSelection: Bool {
        get { settings.closeWindowAfterSelection }
        set {
            settings.closeWindowAfterSelection = newValue
            settingsDidChange(settings)
            lastErrorMessage = nil
        }
    }

    /// 是否允许 Esc 关闭历史窗口。
    var escapeClosesWindow: Bool {
        get { settings.escapeClosesWindow }
        set {
            settings.escapeClosesWindow = newValue
            settingsDidChange(settings)
            lastErrorMessage = nil
        }
    }

    /// 历史窗口是否常驻不因外部点击关闭。
    var historyWindowStaysOpen: Bool {
        get { settings.historyWindowStaysOpen }
        set {
            settings.historyWindowStaysOpen = newValue
            settingsDidChange(settings)
            lastErrorMessage = nil
        }
    }

    /// 历史窗口是否总在最前。
    var historyWindowAlwaysOnTop: Bool {
        get { settings.historyWindowAlwaysOnTop }
        set {
            settings.historyWindowAlwaysOnTop = newValue
            settingsDidChange(settings)
            lastErrorMessage = nil
        }
    }

    /// 是否暂停自动记录剪贴板。
    var isRecordingPaused: Bool {
        get { settings.isRecordingPaused }
        set {
            settings.isRecordingPaused = newValue
            settingsDidChange(settings)
            lastErrorMessage = nil
        }
    }

    /// 面向设置页 picker 的保留策略。
    var retentionPolicy: RetentionPolicy {
        get { settings.retentionPolicy }
        set {
            settings.retentionPolicy = newValue
            customRetentionDaysText = settings.retentionDays > 0 ? "\(settings.retentionDays)" : ""
            settingsDidChange(settings)
            do {
                try retentionDaysDidChange(settings)
                refreshStorageUsage()
                lastErrorMessage = nil
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    /// 开机自启动状态，写入时调用系统登录项服务。
    var launchAtLogin: Bool {
        get { settings.launchAtLogin }
        set {
            do {
                try launchAtLoginDidChange(newValue)
                settings.launchAtLogin = newValue
                settingsDidChange(settings)
                lastErrorMessage = nil
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    /// 当前快捷键展示名。
    var shortcutDisplayName: String {
        settings.shortcutDisplayName
    }

    /// 设置页可选的预设快捷键。
    var availableShortcuts: [ShortcutDefinition] {
        ShortcutDefinition.available
    }

    /// 快捷键 picker 的选中 id，写入时同步通知 ShortcutService。
    var selectedShortcutID: String {
        get { settings.shortcutID }
        set {
            if newValue == ShortcutDefinition.customID, let shortcut = settings.customShortcut {
                applyShortcut(shortcut) {
                    settings.shortcutID = shortcut.id
                }
                return
            }

            let shortcut = ShortcutDefinition.definition(for: newValue)
            applyShortcut(shortcut) {
                settings.shortcutID = shortcut.id
            }
        }
    }

    /// 用户已经录制过的自定义快捷键。
    var recordedShortcut: ShortcutDefinition? {
        settings.customShortcut
    }

    /// 图片历史占用空间的本地化展示文本。
    var storageUsageDescription: String {
        ByteCountFormatter.string(fromByteCount: storageUsageBytes, countStyle: .file)
    }

    /// 应用自定义保留天数输入。
    func applyCustomRetentionDays() {
        guard
            let days = Int(customRetentionDaysText.trimmingCharacters(in: .whitespacesAndNewlines)),
            days > 0
        else {
            lastErrorMessage = "请输入大于 0 的保留天数。"
            return
        }

        retentionPolicy = .days(days)
    }

    /// 保存用户录制的自定义快捷键。
    func applyCustomShortcut(_ shortcut: ShortcutDefinition) {
        applyShortcut(shortcut) {
            settings.customShortcut = shortcut
            settings.shortcutID = shortcut.id
        }
    }

    /// 清空非收藏记录，并刷新存储占用。
    func clearNonFavorites() {
        do {
            try clearNonFavoritesAction()
            refreshStorageUsage()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// 清空全部历史记录，并刷新存储占用。
    func clearAll() {
        do {
            try clearAllAction()
            refreshStorageUsage()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// 重新读取图片存储占用。
    func refreshStorageUsage() {
        storageUsageBytes = storageUsageProvider()
    }

    /// AppEnvironment 在 ShortcutService 创建后注入更新回调。
    func setShortcutDidChange(_ handler: @escaping (ShortcutDefinition) throws -> Void) {
        shortcutDidChange = handler
    }

    /// 先尝试让系统快捷键生效，成功后再保存设置，避免界面显示一个实际无效的组合。
    private func applyShortcut(_ shortcut: ShortcutDefinition, updateSettings: () -> Void) {
        do {
            try shortcutDidChange(shortcut)
            updateSettings()
            settingsDidChange(settings)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
