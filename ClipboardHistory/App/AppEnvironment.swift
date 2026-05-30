import AppKit
import Combine
import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    @Published var isRecordingPaused: Bool {
        didSet {
            recordingState.isPaused = isRecordingPaused
        }
    }
    @Published var isSearchPresented: Bool
    @Published var historyViewModel: ClipboardHistoryViewModel
    @Published var settingsViewModel: SettingsViewModel
    @Published var lastErrorMessage: String?

    private let store: ClipboardStore
    private let pasteService: PasteService
    private let recordingState: RecordingState
    private var retentionCleaner: RetentionCleaner?
    private var clipboardMonitor: ClipboardMonitor?
    private var shortcutService: ShortcutService?

    init(
        isRecordingPaused: Bool = false,
        isSearchPresented: Bool = false,
        store: ClipboardStore = InMemoryClipboardStore(),
        pasteService: PasteService = PasteService(),
        settings: AppSettings = .default,
        storageUsageProvider: @escaping () -> Int64 = { 0 },
        settingsDidChange: @escaping (AppSettings) -> Void = { _ in },
        launchAtLoginDidChange: @escaping (Bool) throws -> Void = { _ in },
        startupErrorMessage: String? = nil
    ) {
        self.isRecordingPaused = isRecordingPaused
        self.isSearchPresented = isSearchPresented
        self.store = store
        self.pasteService = pasteService
        recordingState = RecordingState(isPaused: isRecordingPaused)
        lastErrorMessage = startupErrorMessage

        let historyViewModel = ClipboardHistoryViewModel(store: store)
        self.historyViewModel = historyViewModel
        settingsViewModel = SettingsViewModel(
            settings: settings,
            storageUsageBytes: storageUsageProvider(),
            storageUsageProvider: storageUsageProvider,
            settingsDidChange: settingsDidChange,
            launchAtLoginDidChange: launchAtLoginDidChange,
            clearNonFavorites: {
                try store.deleteAll(includeFavorites: false)
                historyViewModel.reload()
            },
            clearAll: {
                try store.deleteAll(includeFavorites: true)
                historyViewModel.reload()
            }
        )
    }

    static func live() -> AppEnvironment {
        do {
            let appSupportRoot = try productionAppSupportRoot()
            let databaseURL = appSupportRoot.appendingPathComponent("clipboard-history.sqlite")
            let imageDirectory = appSupportRoot.appendingPathComponent("Images")

            let store = try SQLiteClipboardStore(databaseURL: databaseURL)
            let imageStorage = try ImageStorage(directory: imageDirectory)
            let pasteService = PasteService()
            let settingsStore = AppSettingsStore()
            let loginItemService = LoginItemService()
            var settings = settingsStore.load()
            if let launchAtLogin = try? loginItemService.isEnabled() {
                settings.launchAtLogin = launchAtLogin
            }

            let environment = AppEnvironment(
                store: store,
                pasteService: pasteService,
                settings: settings,
                storageUsageProvider: {
                    imageStorage.storageUsageBytes()
                },
                settingsDidChange: { settings in
                    settingsStore.save(settings)
                },
                launchAtLoginDidChange: { isEnabled in
                    try loginItemService.setEnabled(isEnabled)
                }
            )

            let retentionCleaner = RetentionCleaner(store: store)
            environment.retentionCleaner = retentionCleaner
            do {
                try retentionCleaner.run(settings: settings)
                environment.historyViewModel.reload()
            } catch {
                environment.lastErrorMessage = "Retention cleanup failed: \(error.localizedDescription)"
            }

            let monitor = ClipboardMonitor(
                store: store,
                imageStorage: imageStorage,
                isRecordingPaused: { [weak recordingState = environment.recordingState] in
                    recordingState?.isPaused ?? true
                }
            )
            environment.clipboardMonitor = monitor
            monitor.start()

            let shortcutService = ShortcutService { [weak environment] in
                environment?.openSearch()
            }
            environment.shortcutService = shortcutService
            shortcutService.start()

            return environment
        } catch {
            return AppEnvironment(
                startupErrorMessage: "Clipboard History could not start live services: \(error.localizedDescription)"
            )
        }
    }

    func openSearch() {
        isSearchPresented = true
        historyViewModel.reload()
    }

    func openSettings() {
        settingsViewModel.refreshStorageUsage()
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func paste(_ item: ClipboardItem) {
        do {
            try pasteService.copyAndPaste(item)
            try markUsed(item)
            historyViewModel.reload()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func copy(_ item: ClipboardItem) {
        do {
            try pasteService.copy(item)
            try markUsed(item)
            historyViewModel.reload()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private static func productionAppSupportRoot() throws -> URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("ClipboardHistory", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func markUsed(_ item: ClipboardItem) throws {
        var updatedItem = item
        updatedItem.lastUsedAt = Date()
        try store.insert(updatedItem)
        lastErrorMessage = nil
    }
}

private final class RecordingState {
    var isPaused: Bool

    init(isPaused: Bool) {
        self.isPaused = isPaused
    }
}

private final class AppSettingsStore {
    private let defaults: UserDefaults
    private let key = "ClipboardHistory.settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

private final class InMemoryClipboardStore: ClipboardStore {
    private var items: [ClipboardItem] = []

    func insert(_ item: ClipboardItem) throws {
        items.removeAll { $0.id == item.id }
        items.append(item)
    }

    func fetchAll() throws -> [ClipboardItem] {
        items.sorted {
            if $0.isFavorite != $1.isFavorite {
                return $0.isFavorite && !$1.isFavorite
            }
            return $0.copiedAt > $1.copiedAt
        }
    }

    func setFavorite(id: UUID, isFavorite: Bool) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isFavorite = isFavorite
    }

    func delete(id: UUID) throws {
        items.removeAll { $0.id == id }
    }

    func deleteNonFavorites(olderThan cutoff: Date) throws {
        items.removeAll { !$0.isFavorite && $0.copiedAt < cutoff }
    }

    func deleteAll(includeFavorites: Bool) throws {
        items.removeAll { includeFavorites || !$0.isFavorite }
    }
}
