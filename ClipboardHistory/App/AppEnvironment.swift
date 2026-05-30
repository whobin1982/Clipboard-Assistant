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
    @Published var historyViewModel: ClipboardHistoryViewModel
    @Published var settingsViewModel: SettingsViewModel
    @Published var lastErrorMessage: String?

    private let store: ClipboardStore
    private let pasteService: PasteService
    private let searchWindowPresenter: SearchWindowPresenting
    private let imageStorage: ImageStorage?
    private let recordingState: RecordingState
    private var retentionCleaner: RetentionCleaner?
    private var clipboardMonitor: ClipboardMonitor?
    private var shortcutService: ShortcutService?
    private var retentionCleanupTimer: Timer?

    init(
        isRecordingPaused: Bool = false,
        store: ClipboardStore = InMemoryClipboardStore(),
        pasteService: PasteService = PasteService(),
        searchWindowPresenter: SearchWindowPresenting? = nil,
        imageStorage: ImageStorage? = nil,
        settings: AppSettings = .default,
        storageUsageProvider: @escaping () -> Int64 = { 0 },
        settingsDidChange: @escaping (AppSettings) -> Void = { _ in },
        launchAtLoginDidChange: @escaping (Bool) throws -> Void = { _ in },
        startupErrorMessage: String? = nil
    ) {
        self.isRecordingPaused = isRecordingPaused
        self.store = store
        self.pasteService = pasteService
        self.searchWindowPresenter = searchWindowPresenter ?? SearchWindowPresenter()
        self.imageStorage = imageStorage
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
            retentionDaysDidChange: { settings in
                defer { historyViewModel.reload() }
                try Self.runRetentionCleanup(store: store, imageStorage: imageStorage, settings: settings)
            },
            shortcutDidChange: { _ in },
            clearNonFavorites: {
                let affectedItems = try store.fetchAll().filter { !$0.isFavorite }
                defer { historyViewModel.reload() }
                try store.deleteAll(includeFavorites: false)
                try Self.cleanupImageFiles(
                    imageStorage: imageStorage,
                    deletedItems: affectedItems,
                    remainingItems: try store.fetchAll()
                )
            },
            clearAll: {
                let affectedItems = try store.fetchAll()
                defer { historyViewModel.reload() }
                try store.deleteAll(includeFavorites: true)
                try Self.cleanupImageFiles(
                    imageStorage: imageStorage,
                    deletedItems: affectedItems,
                    remainingItems: []
                )
            }
        )
    }

    deinit {
        retentionCleanupTimer?.invalidate()
        shortcutService?.stop()
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
                imageStorage: imageStorage,
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
                try environment.runRetentionCleanup(settings: settings)
                environment.historyViewModel.reload()
            } catch {
                environment.lastErrorMessage = "Retention cleanup failed: \(error.localizedDescription)"
            }
            environment.startPeriodicRetentionCleanup()

            let monitor = ClipboardMonitor(
                store: store,
                imageStorage: imageStorage,
                isRecordingPaused: { [weak recordingState = environment.recordingState] in
                    recordingState?.isPaused ?? true
                }
            )
            environment.clipboardMonitor = monitor
            monitor.start()

            let shortcutService = ShortcutService(shortcut: settings.shortcut) { [weak environment] in
                environment?.openSearch()
            }
            environment.shortcutService = shortcutService
            environment.settingsViewModel.setShortcutDidChange { [weak shortcutService] shortcut in
                shortcutService?.updateShortcut(shortcut)
            }
            shortcutService.start()

            return environment
        } catch {
            return AppEnvironment(
                startupErrorMessage: "Clipboard History could not start live services: \(error.localizedDescription)"
            )
        }
    }

    func openSearch() {
        historyViewModel.reload()
        searchWindowPresenter.show(
            viewModel: historyViewModel,
            onPaste: paste,
            onCopy: copy,
            onDelete: delete
        )
    }

    func openSettings() {
        settingsViewModel.refreshStorageUsage()
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func paste(_ item: ClipboardItem) {
        do {
            try pasteService.copy(item)
            try markUsed(item)
            historyViewModel.reload()
            searchWindowPresenter.orderOut()
            searchWindowPresenter.reactivatePreviousApplication()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                Task { @MainActor in
                    self?.sendPasteCommand()
                }
            }
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

    func delete(_ item: ClipboardItem) {
        do {
            try store.delete(id: item.id)
            try Self.cleanupImageFiles(
                imageStorage: imageStorage,
                deletedItems: [item],
                remainingItems: try store.fetchAll()
            )
            historyViewModel.reload()
            settingsViewModel.refreshStorageUsage()
            lastErrorMessage = nil
        } catch {
            historyViewModel.reload()
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

    private func sendPasteCommand() {
        do {
            try pasteService.sendPasteCommand()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func startPeriodicRetentionCleanup() {
        retentionCleanupTimer?.invalidate()
        retentionCleanupTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.runScheduledRetentionCleanup()
            }
        }
    }

    private func runScheduledRetentionCleanup() {
        do {
            try runRetentionCleanup(settings: settingsViewModel.settings)
            historyViewModel.reload()
            settingsViewModel.refreshStorageUsage()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Retention cleanup failed: \(error.localizedDescription)"
        }
    }

    private func runRetentionCleanup(settings: AppSettings) throws {
        try Self.runRetentionCleanup(store: store, imageStorage: imageStorage, settings: settings)
    }

    private static func runRetentionCleanup(
        store: ClipboardStore,
        imageStorage: ImageStorage?,
        settings: AppSettings,
        now: Date = Date()
    ) throws {
        let cutoff = now.addingTimeInterval(TimeInterval(-settings.retentionDays * 24 * 60 * 60))
        let affectedItems = try store.fetchAll().filter { !$0.isFavorite && $0.copiedAt < cutoff }
        try store.deleteNonFavorites(olderThan: cutoff)
        try cleanupImageFiles(
            imageStorage: imageStorage,
            deletedItems: affectedItems,
            remainingItems: try store.fetchAll()
        )
    }

    private static func cleanupImageFiles(
        imageStorage: ImageStorage?,
        deletedItems: [ClipboardItem],
        remainingItems: [ClipboardItem]
    ) throws {
        guard let imageStorage else { return }
        try imageStorage.deleteFiles(for: deletedItems)
        try imageStorage.removeOrphanedFiles(referencedBy: remainingItems)
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
