import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var storageUsageBytes: Int64
    @Published private(set) var lastErrorMessage: String?

    private let clearNonFavoritesAction: () throws -> Void
    private let clearAllAction: () throws -> Void
    private let storageUsageProvider: () -> Int64
    private let settingsDidChange: (AppSettings) -> Void
    private let launchAtLoginDidChange: (Bool) throws -> Void
    private let retentionDaysDidChange: (AppSettings) throws -> Void
    private var shortcutDidChange: (ShortcutDefinition) -> Void

    init(
        settings: AppSettings = .default,
        storageUsageBytes: Int64 = 0,
        storageUsageProvider: @escaping () -> Int64 = { 0 },
        settingsDidChange: @escaping (AppSettings) -> Void = { _ in },
        launchAtLoginDidChange: @escaping (Bool) throws -> Void = { _ in },
        retentionDaysDidChange: @escaping (AppSettings) throws -> Void = { _ in },
        shortcutDidChange: @escaping (ShortcutDefinition) -> Void = { _ in },
        clearNonFavorites: @escaping () throws -> Void = {},
        clearAll: @escaping () throws -> Void = {}
    ) {
        self.settings = settings
        self.storageUsageBytes = storageUsageBytes
        self.storageUsageProvider = storageUsageProvider
        self.settingsDidChange = settingsDidChange
        self.launchAtLoginDidChange = launchAtLoginDidChange
        self.retentionDaysDidChange = retentionDaysDidChange
        self.shortcutDidChange = shortcutDidChange
        clearNonFavoritesAction = clearNonFavorites
        clearAllAction = clearAll
    }

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

    var shortcutDisplayName: String {
        settings.shortcutDisplayName
    }

    var availableShortcuts: [ShortcutDefinition] {
        ShortcutDefinition.available
    }

    var selectedShortcutID: String {
        get { settings.shortcutID }
        set {
            let shortcut = ShortcutDefinition.definition(for: newValue)
            settings.shortcutID = shortcut.id
            settingsDidChange(settings)
            shortcutDidChange(shortcut)
            lastErrorMessage = nil
        }
    }

    var storageUsageDescription: String {
        ByteCountFormatter.string(fromByteCount: storageUsageBytes, countStyle: .file)
    }

    func clearNonFavorites() {
        do {
            try clearNonFavoritesAction()
            refreshStorageUsage()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func clearAll() {
        do {
            try clearAllAction()
            refreshStorageUsage()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func refreshStorageUsage() {
        storageUsageBytes = storageUsageProvider()
    }

    func setShortcutDidChange(_ handler: @escaping (ShortcutDefinition) -> Void) {
        shortcutDidChange = handler
    }
}
