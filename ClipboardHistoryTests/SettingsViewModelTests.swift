import XCTest
@testable import ClipboardHistory

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testSelectingShortcutPersistsAndNotifiesShortcutService() {
        var savedSettings: [AppSettings] = []
        var updatedShortcuts: [ShortcutDefinition] = []
        let viewModel = SettingsViewModel(
            settingsDidChange: { savedSettings.append($0) },
            shortcutDidChange: { updatedShortcuts.append($0) }
        )

        viewModel.selectedShortcutID = ShortcutDefinition.controlOptionV.id

        XCTAssertEqual(viewModel.settings.shortcutID, ShortcutDefinition.controlOptionV.id)
        XCTAssertEqual(savedSettings.last?.shortcutID, ShortcutDefinition.controlOptionV.id)
        XCTAssertEqual(updatedShortcuts.last, .controlOptionV)
    }
}

final class AppEnvironmentTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppEnvironmentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    @MainActor
    func testDeleteRemovesAssociatedImageFiles() throws {
        let imageURL = temporaryDirectory.appendingPathComponent("item.png")
        let thumbnailURL = temporaryDirectory.appendingPathComponent("item-thumb.png")
        try Data("image".utf8).write(to: imageURL)
        try Data("thumbnail".utf8).write(to: thumbnailURL)
        let item = ClipboardItem.image(imagePath: imageURL.path, thumbnailPath: thumbnailURL.path)
        let store = AppEnvironmentFakeStore(items: [item])
        let storage = try ImageStorage(directory: temporaryDirectory)
        let environment = AppEnvironment(store: store, imageStorage: storage)

        environment.delete(item)

        XCTAssertTrue(try store.fetchAll().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: imageURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbnailURL.path))
    }
}

private final class AppEnvironmentFakeStore: ClipboardStore {
    private var items: [ClipboardItem]

    init(items: [ClipboardItem]) {
        self.items = items
    }

    func insert(_ item: ClipboardItem) throws {
        items.removeAll { $0.id == item.id }
        items.append(item)
    }

    func fetchAll() throws -> [ClipboardItem] {
        items
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
