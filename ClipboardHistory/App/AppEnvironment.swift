import AppKit
import Combine
import Foundation
import SwiftUI

/// 应用的中心协调器，负责把剪贴板存储、窗口、设置、快捷键、自动清理和粘贴服务串起来。
///
/// 这个类型运行在主线程上，因为它会直接驱动 SwiftUI 状态、AppKit 窗口和系统菜单栏交互。
@MainActor
final class AppEnvironment: ObservableObject {
    /// 是否暂停自动记录剪贴板；修改后会同步到共享状态和设置模型。
    @Published var isRecordingPaused: Bool {
        didSet {
            syncRecordingPaused(isRecordingPaused)
        }
    }
    /// 历史记录列表的视图模型，供菜单栏、历史窗口共同使用。
    @Published var historyViewModel: ClipboardHistoryViewModel
    /// 设置页的视图模型，保存所有可配置项。
    @Published var settingsViewModel: SettingsViewModel
    /// 最近一次需要展示给用户的全局错误。
    @Published var lastErrorMessage: String?

    /// 历史记录的持久化抽象；生产环境使用 SQLite，测试环境可替换为内存实现。
    private let store: ClipboardStore
    /// 负责把某条历史记录写回系统剪贴板，并可发送系统粘贴快捷键。
    private let pasteService: PasteService
    /// 历史记录窗口展示器，单独抽象出来便于测试窗口调用参数。
    private let searchWindowPresenter: SearchWindowPresenting
    /// 设置窗口展示器。
    private let settingsWindowPresenter: SettingsWindowPresenting
    /// 图片文件存储器；为空时只处理文本或测试场景。
    private let imageStorage: ImageStorage?
    /// 自动记录开关的共享状态，让窗口中的开关能实时刷新。
    let recordingPauseState: RecordingPauseState
    /// 定期清理过期历史的服务。
    private var retentionCleaner: RetentionCleaner?
    /// 轮询系统剪贴板变化的服务。
    private var clipboardMonitor: ClipboardMonitor?
    /// 全局快捷键监听服务。
    private var shortcutService: ShortcutService?
    /// 定时执行过期清理，避免长期运行时旧数据一直留在库里。
    private var retentionCleanupTimer: Timer?

    /// 创建应用环境。
    ///
    /// 默认参数让测试可以只替换自己关心的依赖，同时复用真实的业务编排逻辑。
    init(
        isRecordingPaused: Bool = false,
        store: ClipboardStore = InMemoryClipboardStore(),
        pasteService: PasteService = PasteService(),
        searchWindowPresenter: SearchWindowPresenting? = nil,
        settingsWindowPresenter: SettingsWindowPresenting? = nil,
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
        self.settingsWindowPresenter = settingsWindowPresenter ?? SettingsWindowPresenter()
        self.imageStorage = imageStorage
        recordingPauseState = RecordingPauseState(isPaused: isRecordingPaused)
        lastErrorMessage = startupErrorMessage

        let historyViewModel = ClipboardHistoryViewModel(store: store)
        self.historyViewModel = historyViewModel
        var initialSettings = settings
        initialSettings.isRecordingPaused = isRecordingPaused
        settingsViewModel = SettingsViewModel(
            settings: initialSettings,
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

    /// 生产环境入口：初始化真实数据库、图片目录、系统剪贴板监听、全局快捷键和设置持久化。
    static func live() -> AppEnvironment {
        do {
            // 所有用户数据统一放进 Application Support，便于备份、升级和卸载时定位。
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

            // SettingsViewModel 会在设置变化时回调保存逻辑，避免 UI 层直接接触 UserDefaults。
            let environment = AppEnvironment(
                isRecordingPaused: settings.isRecordingPaused,
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
                environment.lastErrorMessage = "清理过期记录失败：\(error.localizedDescription)"
            }
            environment.startPeriodicRetentionCleanup()

            let monitor = ClipboardMonitor(
                store: store,
                imageStorage: imageStorage,
                isRecordingPaused: { [weak recordingPauseState = environment.recordingPauseState] in
                    recordingPauseState?.isPaused ?? true
                }
            )
            environment.clipboardMonitor = monitor
            monitor.start()

            // 快捷键回调统一走 openSearch，保证菜单栏点击和快捷键呼出使用同一套窗口逻辑。
            let shortcutService = ShortcutService(shortcut: settings.shortcut) { [weak environment] in
                environment?.openSearch(previousApplication: nil)
            }
            environment.shortcutService = shortcutService
            environment.settingsViewModel.setShortcutDidChange { [weak shortcutService] shortcut in
                guard let shortcutService else { return }
                try shortcutService.updateShortcut(shortcut)
            }
            do {
                try shortcutService.start()
            } catch {
                environment.lastErrorMessage = error.localizedDescription
            }

            return environment
        } catch {
            return AppEnvironment(
                startupErrorMessage: "剪贴板历史无法启动核心服务：\(error.localizedDescription)"
            )
        }
    }

    /// 使用当前前台应用自动推断粘贴目标，打开历史记录窗口。
    func openSearch() {
        openSearch(previousApplication: nil)
    }

    /// 打开历史记录窗口，并记录呼出前的前台应用，后续自动粘贴时会切回该应用。
    func openSearch(previousApplication: NSRunningApplication?) {
        historyViewModel.reload()
        searchWindowPresenter.show(
            viewModel: historyViewModel,
            previousApplication: previousApplication,
            escapeClosesWindow: settingsViewModel.settings.escapeClosesWindow,
            isRecordingPaused: Binding(
                get: { self.isRecordingPaused },
                set: { self.isRecordingPaused = $0 }
            ),
            recordingPauseState: recordingPauseState,
            historyWindowStaysOpen: Binding(
                get: { self.settingsViewModel.historyWindowStaysOpen },
                set: { self.settingsViewModel.historyWindowStaysOpen = $0 }
            ),
            historyWindowAlwaysOnTop: Binding(
                get: { self.settingsViewModel.historyWindowAlwaysOnTop },
                set: { self.settingsViewModel.historyWindowAlwaysOnTop = $0 }
            ),
            onClose: { [weak self] in
                self?.searchWindowPresenter.orderOut()
            },
            onWindowBehaviorChanged: { [weak self] alwaysOnTop in
                self?.searchWindowPresenter.applyWindowBehavior(alwaysOnTop: alwaysOnTop)
            },
            onOpenSettings: { [weak self] in
                self?.openSettings()
            },
            onClearNonFavorites: { [weak self] in
                self?.settingsViewModel.clearNonFavorites()
            },
            onClearAll: { [weak self] in
                self?.settingsViewModel.clearAll()
            },
            onPaste: pasteFromSearchWindow,
            onCopy: copy,
            onDelete: delete
        )
    }

    /// 打开设置页前刷新一次图片存储占用，保证界面数据是最新的。
    func openSettings() {
        settingsViewModel.refreshStorageUsage()
        settingsWindowPresenter.show(environment: self)
    }

    /// 从右键菜单选择记录时使用：复制记录、更新使用时间，并立即向当前焦点发送粘贴快捷键。
    func paste(_ item: ClipboardItem) {
        do {
            try pasteService.copy(item)
            try markUsed(item)
            historyViewModel.reload()
            try pasteService.sendPasteCommand()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// 从历史窗口选择记录时使用，额外遵守“是否关闭窗口”和“是否自动粘贴”的设置。
    private func pasteFromSearchWindow(_ item: ClipboardItem) {
        let settings = settingsViewModel.settings
        do {
            try pasteService.copy(item)
            try markUsed(item)
            historyViewModel.reload()

            if settings.closeWindowAfterSelection {
                searchWindowPresenter.orderOut()
            }

            guard settings.selectionAction == .paste else { return }

            let previousApplication = searchWindowPresenter.consumePreviousApplication()
            reactivate(previousApplication)
            // 切回目标应用后稍等一小段时间，避免 Cmd+V 抢在目标输入框恢复焦点前发出。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                Task { @MainActor in
                    self?.sendPasteCommand()
                }
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// 将焦点切回呼出历史窗口前的应用，为自动粘贴做准备。
    private func reactivate(_ application: NSRunningApplication?) {
        guard let application else { return }
        if #available(macOS 14.0, *) {
            application.activate()
        } else {
            application.activate(options: [.activateIgnoringOtherApps])
        }
    }

    /// 只把记录放回系统剪贴板，不发送粘贴快捷键。
    func copy(_ item: ClipboardItem) {
        do {
            try pasteService.copy(item)
            try markUsed(item)
            historyViewModel.reload()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// 删除单条历史，并同步清理该记录独占的图片文件。
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

    /// 返回并创建应用私有数据目录。
    private static func productionAppSupportRoot() throws -> URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("ClipboardHistory", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// 更新某条记录的最近使用时间；SQLite 的 insert 是 INSERT OR REPLACE，所以可用于覆盖同一 id。
    private func markUsed(_ item: ClipboardItem) throws {
        var updatedItem = item
        updatedItem.lastUsedAt = Date()
        try store.insert(updatedItem)
        lastErrorMessage = nil
    }

    /// 单独封装发送粘贴快捷键，便于统一处理辅助功能权限等错误。
    private func sendPasteCommand() {
        do {
            try pasteService.sendPasteCommand()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// 把菜单栏/历史窗口/设置页看到的“暂停记录”状态保持一致。
    private func syncRecordingPaused(_ isPaused: Bool) {
        if recordingPauseState.isPaused != isPaused {
            recordingPauseState.isPaused = isPaused
        }
        if settingsViewModel.settings.isRecordingPaused != isPaused {
            settingsViewModel.isRecordingPaused = isPaused
        }
    }

    /// 启动每小时一次的过期记录清理。
    private func startPeriodicRetentionCleanup() {
        retentionCleanupTimer?.invalidate()
        retentionCleanupTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.runScheduledRetentionCleanup()
            }
        }
    }

    /// 定时器触发的清理入口，会刷新历史列表和存储占用。
    private func runScheduledRetentionCleanup() {
        do {
            try runRetentionCleanup(settings: settingsViewModel.settings)
            historyViewModel.reload()
            settingsViewModel.refreshStorageUsage()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "清理过期记录失败：\(error.localizedDescription)"
        }
    }

    /// 使用当前环境的真实依赖执行一次过期清理。
    private func runRetentionCleanup(settings: AppSettings) throws {
        try Self.runRetentionCleanup(store: store, imageStorage: imageStorage, settings: settings)
    }

    /// 删除超过保留天数的非收藏记录，并清理不再被引用的图片文件。
    private static func runRetentionCleanup(
        store: ClipboardStore,
        imageStorage: ImageStorage?,
        settings: AppSettings,
        now: Date = Date()
    ) throws {
        guard settings.retentionDays > 0 else { return }
        let cutoff = now.addingTimeInterval(TimeInterval(-settings.retentionDays * 24 * 60 * 60))
        let affectedItems = try store.fetchAll().filter { !$0.isFavorite && $0.copiedAt < cutoff }
        try store.deleteNonFavorites(olderThan: cutoff)
        try cleanupImageFiles(
            imageStorage: imageStorage,
            deletedItems: affectedItems,
            remainingItems: try store.fetchAll()
        )
    }

    /// 图片历史由数据库记录和磁盘文件共同组成，删除数据库记录后必须同步清理磁盘侧数据。
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

/// 自动记录开关的引用类型状态，供多个 SwiftUI 视图实时观察同一个值。
final class RecordingPauseState: ObservableObject {
    @Published var isPaused: Bool

    init(isPaused: Bool) {
        self.isPaused = isPaused
    }
}

/// 使用 UserDefaults 存取应用设置，外部只需要关心 AppSettings 本身。
private final class AppSettingsStore {
    private let defaults: UserDefaults
    private let key = "ClipboardHistory.settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 读取设置；如果旧数据损坏或不存在，回退到默认设置。
    func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    /// 保存设置；编码失败时不覆盖已有设置。
    func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

/// 测试和启动失败降级时使用的内存存储，实现与 SQLite 存储相同的排序语义。
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
