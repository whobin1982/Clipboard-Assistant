import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var storageUsageBytes: Int64

    private let clearNonFavoritesAction: () -> Void
    private let clearAllAction: () -> Void

    init(
        settings: AppSettings = .default,
        storageUsageBytes: Int64 = 0,
        clearNonFavorites: @escaping () -> Void = {},
        clearAll: @escaping () -> Void = {}
    ) {
        self.settings = settings
        self.storageUsageBytes = storageUsageBytes
        clearNonFavoritesAction = clearNonFavorites
        clearAllAction = clearAll
    }

    var retentionDays: Int {
        get { settings.retentionDays }
        set { settings.retentionDays = max(1, newValue) }
    }

    var launchAtLogin: Bool {
        get { settings.launchAtLogin }
        set { settings.launchAtLogin = newValue }
    }

    var shortcutDisplayName: String {
        settings.shortcutDisplayName
    }

    var storageUsageDescription: String {
        ByteCountFormatter.string(fromByteCount: storageUsageBytes, countStyle: .file)
    }

    func clearNonFavorites() {
        clearNonFavoritesAction()
    }

    func clearAll() {
        clearAllAction()
    }
}
