import AppKit
import Combine
import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    @Published var isRecordingPaused: Bool
    @Published var isSearchPresented: Bool
    @Published var historyViewModel: ClipboardHistoryViewModel
    @Published var settingsViewModel: SettingsViewModel

    private let pasteService: PasteService

    init(
        isRecordingPaused: Bool = false,
        isSearchPresented: Bool = false,
        store: ClipboardStore = InMemoryClipboardStore(),
        pasteService: PasteService = PasteService()
    ) {
        self.isRecordingPaused = isRecordingPaused
        self.isSearchPresented = isSearchPresented
        self.pasteService = pasteService

        let historyViewModel = ClipboardHistoryViewModel(store: store)
        self.historyViewModel = historyViewModel
        self.settingsViewModel = SettingsViewModel(
            clearNonFavorites: {
                try? store.deleteAll(includeFavorites: false)
                historyViewModel.reload()
            },
            clearAll: {
                try? store.deleteAll(includeFavorites: true)
                historyViewModel.reload()
            }
        )
    }

    static func live() -> AppEnvironment {
        AppEnvironment()
    }

    func openSearch() {
        isSearchPresented = true
        historyViewModel.reload()
    }

    func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func paste(_ item: ClipboardItem) {
        try? pasteService.copyAndPaste(item)
    }

    func copy(_ item: ClipboardItem) {
        try? pasteService.copy(item)
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
