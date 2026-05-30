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

    init(
        settings: AppSettings = .default,
        storageUsageBytes: Int64 = 0,
        storageUsageProvider: @escaping () -> Int64 = { 0 },
        settingsDidChange: @escaping (AppSettings) -> Void = { _ in },
        launchAtLoginDidChange: @escaping (Bool) throws -> Void = { _ in },
        clearNonFavorites: @escaping () throws -> Void = {},
        clearAll: @escaping () throws -> Void = {}
    ) {
        self.settings = settings
        self.storageUsageBytes = storageUsageBytes
        self.storageUsageProvider = storageUsageProvider
        self.settingsDidChange = settingsDidChange
        self.launchAtLoginDidChange = launchAtLoginDidChange
        clearNonFavoritesAction = clearNonFavorites
        clearAllAction = clearAll
    }

    var retentionDays: Int {
        get { settings.retentionDays }
        set {
            settings.retentionDays = max(1, newValue)
            settingsDidChange(settings)
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
}
