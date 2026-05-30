# Mac Clipboard History App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build version 1 of a native macOS clipboard history utility with text/image history, search, favorites, retention cleanup, menu bar controls, settings, shortcut popup, and local-only persistence.

**Architecture:** Use a native Swift/SwiftUI macOS app with focused service objects for clipboard monitoring, persistence, image storage, cleanup, shortcut handling, and paste automation. Keep domain logic independent from UI so most behavior can be covered with unit tests before wiring AppKit/SwiftUI surfaces.

**Tech Stack:** Swift 5.10+, SwiftUI, AppKit, XCTest, SQLite through a small local wrapper using `sqlite3`, macOS Launch Services for login item settings, Carbon/AppKit event monitoring for global shortcut, and `NSPasteboard`/accessibility events for clipboard and paste behavior.

---

## Scope Check

The design describes one coherent macOS app. It has multiple components, but they are tightly coupled around a single user workflow, so one implementation plan is appropriate.

## File Structure

Create this structure:

- `project.yml`: XcodeGen project definition used to generate `ClipboardHistory.xcodeproj`.
- `ClipboardHistory.xcodeproj`: generated macOS app project.
- `ClipboardHistory/App/ClipboardHistoryApp.swift`: app entry point, dependency wiring, menu bar scene.
- `ClipboardHistory/App/AppEnvironment.swift`: shared service container for production dependencies.
- `ClipboardHistory/Models/ClipboardItem.swift`: domain model for text and image records.
- `ClipboardHistory/Models/AppSettings.swift`: retention, launch-at-login, shortcut, and recording settings.
- `ClipboardHistory/Persistence/ClipboardStore.swift`: persistence protocol.
- `ClipboardHistory/Persistence/SQLiteClipboardStore.swift`: SQLite-backed implementation.
- `ClipboardHistory/Persistence/DatabaseMigrator.swift`: schema creation and migrations.
- `ClipboardHistory/Services/ClipboardMonitor.swift`: polls `NSPasteboard` and records text/images.
- `ClipboardHistory/Services/ImageStorage.swift`: writes original images and thumbnails to local app support storage.
- `ClipboardHistory/Services/RetentionCleaner.swift`: deletes expired non-favorite records.
- `ClipboardHistory/Services/PasteService.swift`: restores an item to `NSPasteboard` and optionally sends paste.
- `ClipboardHistory/Services/ShortcutService.swift`: registers the global shortcut and opens the popup.
- `ClipboardHistory/Services/LoginItemService.swift`: reads/writes launch-at-login state.
- `ClipboardHistory/ViewModels/ClipboardHistoryViewModel.swift`: search, list state, actions.
- `ClipboardHistory/ViewModels/SettingsViewModel.swift`: settings state and actions.
- `ClipboardHistory/Views/ClipboardPopupView.swift`: shortcut popup UI.
- `ClipboardHistory/Views/ClipboardRowView.swift`: text/image row UI.
- `ClipboardHistory/Views/MenuBarView.swift`: menu bar controls.
- `ClipboardHistory/Views/SettingsView.swift`: settings UI.
- `ClipboardHistoryTests/ClipboardStoreTests.swift`: persistence tests.
- `ClipboardHistoryTests/RetentionCleanerTests.swift`: cleanup tests.
- `ClipboardHistoryTests/ClipboardHistoryViewModelTests.swift`: search/favorite/delete tests.
- `ClipboardHistoryTests/ImageStorageTests.swift`: image and thumbnail storage tests.
- `ClipboardHistoryTests/PasteServiceTests.swift`: copy-only pasteboard behavior tests.

## Task 1: Create macOS App Skeleton

**Files:**
- Create: `ClipboardHistory.xcodeproj`
- Create: `project.yml`
- Create: `ClipboardHistory/App/ClipboardHistoryApp.swift`
- Create: `ClipboardHistory/App/AppEnvironment.swift`
- Create: `ClipboardHistory/Views/MenuBarView.swift`
- Create: `ClipboardHistoryTests/ClipboardHistorySmokeTests.swift`

- [ ] **Step 1: Create the Xcode project**

Run:

```bash
mkdir -p ClipboardHistory/App ClipboardHistory/Views ClipboardHistoryTests
cat > project.yml <<'YAML'
name: ClipboardHistory
options:
  bundleIdPrefix: com.local
  deploymentTarget:
    macOS: "14.0"
settings:
  base:
    SWIFT_VERSION: "5.0"
targets:
  ClipboardHistory:
    type: application
    platform: macOS
    sources:
      - ClipboardHistory
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.local.ClipboardHistory
        INFOPLIST_KEY_LSUIElement: true
        INFOPLIST_KEY_NSHumanReadableCopyright: ""
    info:
      path: ClipboardHistory/Info.plist
      properties:
        CFBundleDisplayName: ClipboardHistory
        LSUIElement: true
        NSPrincipalClass: NSApplication
  ClipboardHistoryTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - ClipboardHistoryTests
    dependencies:
      - target: ClipboardHistory
YAML
xcodegen generate
```

Expected: `ClipboardHistory.xcodeproj` exists. If `xcodegen` is missing, install it first with `brew install xcodegen`, then rerun `xcodegen generate`.

- [ ] **Step 2: Add the app entry point**

Write `ClipboardHistory/App/ClipboardHistoryApp.swift`:

```swift
import SwiftUI

@main
struct ClipboardHistoryApp: App {
    @StateObject private var environment = AppEnvironment.live()

    var body: some Scene {
        MenuBarExtra("Clipboard History", systemImage: "doc.on.clipboard") {
            MenuBarView()
                .environmentObject(environment)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(environment)
        }
    }
}
```

- [ ] **Step 3: Add the environment container**

Write `ClipboardHistory/App/AppEnvironment.swift`:

```swift
import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    @Published var isRecordingPaused: Bool

    init(isRecordingPaused: Bool = false) {
        self.isRecordingPaused = isRecordingPaused
    }

    static func live() -> AppEnvironment {
        AppEnvironment()
    }
}
```

- [ ] **Step 4: Add temporary menu bar view**

Write `ClipboardHistory/Views/MenuBarView.swift`:

```swift
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Button(environment.isRecordingPaused ? "Resume Recording" : "Pause Recording") {
            environment.isRecordingPaused.toggle()
        }
        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
```

- [ ] **Step 5: Add temporary settings view**

Write `ClipboardHistory/Views/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Text("Clipboard History Settings")
        }
        .padding()
        .frame(width: 420, height: 260)
    }
}
```

- [ ] **Step 6: Add smoke test**

Write `ClipboardHistoryTests/ClipboardHistorySmokeTests.swift`:

```swift
import XCTest
@testable import ClipboardHistory

final class ClipboardHistorySmokeTests: XCTestCase {
    @MainActor
    func testEnvironmentStartsRecordingEnabled() {
        let environment = AppEnvironment.live()
        XCTAssertFalse(environment.isRecordingPaused)
    }
}
```

- [ ] **Step 7: Run tests**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS'
```

Expected: test suite passes.

- [ ] **Step 8: Commit**

```bash
git add ClipboardHistory.xcodeproj ClipboardHistory ClipboardHistoryTests
git commit -m "chore: scaffold macOS clipboard history app"
```

## Task 2: Add Domain Models and Settings

**Files:**
- Create: `ClipboardHistory/Models/ClipboardItem.swift`
- Create: `ClipboardHistory/Models/AppSettings.swift`
- Create: `ClipboardHistoryTests/ClipboardItemTests.swift`

- [ ] **Step 1: Write model tests**

Write `ClipboardHistoryTests/ClipboardItemTests.swift`:

```swift
import XCTest
@testable import ClipboardHistory

final class ClipboardItemTests: XCTestCase {
    func testTextItemSearchesCaseInsensitively() {
        let item = ClipboardItem.text("Project Quote", copiedAt: Date(timeIntervalSince1970: 10))
        XCTAssertTrue(item.matches(query: "quote"))
        XCTAssertTrue(item.matches(query: "PROJECT"))
        XCTAssertFalse(item.matches(query: "invoice"))
    }

    func testImageItemDoesNotMatchTextQuery() {
        let item = ClipboardItem.image(
            imagePath: "/tmp/original.png",
            thumbnailPath: "/tmp/thumb.png",
            copiedAt: Date(timeIntervalSince1970: 10)
        )
        XCTAssertFalse(item.matches(query: "png"))
    }

    func testDefaultSettingsUseThirtyDayRetentionAndStartupOff() {
        let settings = AppSettings.default
        XCTAssertEqual(settings.retentionDays, 30)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertEqual(settings.shortcutDisplayName, "Option + Command + V")
    }
}
```

- [ ] **Step 2: Run model tests to verify they fail**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/ClipboardItemTests
```

Expected: FAIL because `ClipboardItem` and `AppSettings` do not exist.

- [ ] **Step 3: Implement models**

Write `ClipboardHistory/Models/ClipboardItem.swift`:

```swift
import Foundation

enum ClipboardItemKind: String, Codable, Equatable {
    case text
    case image
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ClipboardItemKind
    var copiedAt: Date
    var lastUsedAt: Date?
    var isFavorite: Bool
    var text: String?
    var imagePath: String?
    var thumbnailPath: String?

    static func text(_ value: String, copiedAt: Date = Date()) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .text,
            copiedAt: copiedAt,
            lastUsedAt: nil,
            isFavorite: false,
            text: value,
            imagePath: nil,
            thumbnailPath: nil
        )
    }

    static func image(imagePath: String, thumbnailPath: String, copiedAt: Date = Date()) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .image,
            copiedAt: copiedAt,
            lastUsedAt: nil,
            isFavorite: false,
            text: nil,
            imagePath: imagePath,
            thumbnailPath: thumbnailPath
        )
    }

    func matches(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard kind == .text, let text else { return false }
        return text.localizedCaseInsensitiveContains(trimmed)
    }
}
```

Write `ClipboardHistory/Models/AppSettings.swift`:

```swift
import Foundation

struct AppSettings: Codable, Equatable {
    var retentionDays: Int
    var launchAtLogin: Bool
    var shortcutDisplayName: String

    static let `default` = AppSettings(
        retentionDays: 30,
        launchAtLogin: false,
        shortcutDisplayName: "Option + Command + V"
    )
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/ClipboardItemTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ClipboardHistory/Models ClipboardHistoryTests/ClipboardItemTests.swift
git commit -m "feat: add clipboard domain models"
```

## Task 3: Implement Local Persistence

**Files:**
- Create: `ClipboardHistory/Persistence/ClipboardStore.swift`
- Create: `ClipboardHistory/Persistence/DatabaseMigrator.swift`
- Create: `ClipboardHistory/Persistence/SQLiteClipboardStore.swift`
- Create: `ClipboardHistoryTests/ClipboardStoreTests.swift`

- [ ] **Step 1: Write persistence tests**

Write `ClipboardHistoryTests/ClipboardStoreTests.swift`:

```swift
import XCTest
@testable import ClipboardHistory

final class ClipboardStoreTests: XCTestCase {
    func testInsertAndFetchTextItem() throws {
        let store = try SQLiteClipboardStore.temporary()
        let item = ClipboardItem.text("hello world", copiedAt: Date(timeIntervalSince1970: 100))

        try store.insert(item)
        let items = try store.fetchAll()

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].kind, .text)
        XCTAssertEqual(items[0].text, "hello world")
    }

    func testFavoriteAndDeleteItem() throws {
        let store = try SQLiteClipboardStore.temporary()
        let item = ClipboardItem.text("keep me")

        try store.insert(item)
        try store.setFavorite(id: item.id, isFavorite: true)
        XCTAssertEqual(try store.fetchAll()[0].isFavorite, true)

        try store.delete(id: item.id)
        XCTAssertTrue(try store.fetchAll().isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/ClipboardStoreTests
```

Expected: FAIL because persistence types do not exist.

- [ ] **Step 3: Add store protocol**

Write `ClipboardHistory/Persistence/ClipboardStore.swift`:

```swift
import Foundation

protocol ClipboardStore {
    func insert(_ item: ClipboardItem) throws
    func fetchAll() throws -> [ClipboardItem]
    func setFavorite(id: UUID, isFavorite: Bool) throws
    func delete(id: UUID) throws
    func deleteNonFavorites(olderThan cutoff: Date) throws
    func deleteAll(includeFavorites: Bool) throws
}
```

- [ ] **Step 4: Add database migrator**

Write `ClipboardHistory/Persistence/DatabaseMigrator.swift`:

```swift
import Foundation
import SQLite3

enum DatabaseError: Error {
    case openFailed
    case executeFailed(String)
    case prepareFailed(String)
}

enum DatabaseMigrator {
    static func migrate(_ db: OpaquePointer?) throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            copied_at REAL NOT NULL,
            last_used_at REAL,
            is_favorite INTEGER NOT NULL,
            text TEXT,
            image_path TEXT,
            thumbnail_path TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_clipboard_items_copied_at ON clipboard_items(copied_at DESC);
        """
        try execute(sql, db: db)
    }

    static func execute(_ sql: String, db: OpaquePointer?) throws {
        var error: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "Unknown SQLite error"
            sqlite3_free(error)
            throw DatabaseError.executeFailed(message)
        }
    }
}
```

- [ ] **Step 5: Implement SQLite store**

Write `ClipboardHistory/Persistence/SQLiteClipboardStore.swift` with prepared statements for `insert`, `fetchAll`, `setFavorite`, `delete`, `deleteNonFavorites`, and `deleteAll`. Bind dates using `timeIntervalSince1970`, booleans as `0` or `1`, and UUIDs as strings. Fetch rows ordered by `is_favorite DESC, copied_at DESC`.

- [ ] **Step 6: Run persistence tests**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/ClipboardStoreTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add ClipboardHistory/Persistence ClipboardHistoryTests/ClipboardStoreTests.swift
git commit -m "feat: persist clipboard history locally"
```

## Task 4: Add Image Storage

**Files:**
- Create: `ClipboardHistory/Services/ImageStorage.swift`
- Create: `ClipboardHistoryTests/ImageStorageTests.swift`

- [ ] **Step 1: Write image storage tests**

Write tests that create a 100x100 `NSImage`, save it through `ImageStorage`, and assert that both original and thumbnail files exist and that `storageUsageBytes()` returns a positive value.

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/ImageStorageTests
```

Expected: FAIL because `ImageStorage` does not exist.

- [ ] **Step 3: Implement image storage**

Write `ClipboardHistory/Services/ImageStorage.swift` with:

```swift
import AppKit
import Foundation

final class ImageStorage {
    let directory: URL

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func save(_ image: NSImage, id: UUID) throws -> (imagePath: String, thumbnailPath: String) {
        let imageURL = directory.appendingPathComponent("\(id.uuidString).png")
        let thumbnailURL = directory.appendingPathComponent("\(id.uuidString)-thumb.png")
        try writePNG(image, to: imageURL)
        try writePNG(thumbnail(from: image), to: thumbnailURL)
        return (imageURL.path, thumbnailURL.path)
    }

    func storageUsageBytes() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return files.reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            return total + size
        }
    }
}
```

Add these private helpers in the same file:

```swift
private extension ImageStorage {
    func thumbnail(from image: NSImage) -> NSImage {
        let targetSize = NSSize(width: 96, height: 96)
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: targetSize).fill()
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        thumbnail.unlockFocus()
        return thumbnail
    }

    func writePNG(_ image: NSImage, to url: URL) throws {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        try pngData.write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: Run image tests**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/ImageStorageTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ClipboardHistory/Services/ImageStorage.swift ClipboardHistoryTests/ImageStorageTests.swift
git commit -m "feat: store clipboard images and thumbnails"
```

## Task 5: Add Retention, Favorites, Search View Model

**Files:**
- Create: `ClipboardHistory/Services/RetentionCleaner.swift`
- Create: `ClipboardHistory/ViewModels/ClipboardHistoryViewModel.swift`
- Create: `ClipboardHistoryTests/RetentionCleanerTests.swift`
- Create: `ClipboardHistoryTests/ClipboardHistoryViewModelTests.swift`

- [ ] **Step 1: Write cleanup tests**

Test that non-favorite items older than 30 days are deleted and favorite items are kept.

- [ ] **Step 2: Write view model tests**

Test that search filters text records, leaves matching records sorted newest first, toggles favorites, deletes individual records, and exposes image rows without text matching.

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/RetentionCleanerTests -only-testing:ClipboardHistoryTests/ClipboardHistoryViewModelTests
```

Expected: FAIL because cleaner and view model do not exist.

- [ ] **Step 4: Implement retention cleaner**

Write `RetentionCleaner` with `run(now:settings:)` that computes `cutoff = now - retentionDays` and calls `deleteNonFavorites(olderThan:)`.

- [ ] **Step 5: Implement clipboard history view model**

Write `ClipboardHistoryViewModel` as `@MainActor final class ClipboardHistoryViewModel: ObservableObject` with `@Published var query`, `@Published private(set) var items`, computed `filteredItems`, and methods `reload()`, `toggleFavorite(_:)`, `delete(_:)`.

- [ ] **Step 6: Run tests**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/RetentionCleanerTests -only-testing:ClipboardHistoryTests/ClipboardHistoryViewModelTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add ClipboardHistory/Services/RetentionCleaner.swift ClipboardHistory/ViewModels/ClipboardHistoryViewModel.swift ClipboardHistoryTests/RetentionCleanerTests.swift ClipboardHistoryTests/ClipboardHistoryViewModelTests.swift
git commit -m "feat: add cleanup and history view model"
```

## Task 6: Add Clipboard Monitoring

**Files:**
- Create: `ClipboardHistory/Services/ClipboardMonitor.swift`
- Create: `ClipboardHistoryTests/ClipboardMonitorTests.swift`

- [ ] **Step 1: Write monitor unit tests around a pasteboard adapter**

Create a `PasteboardReading` protocol in the test plan with `changeCount`, `readString()`, and `readImage()` so monitor logic can be tested without relying on the real pasteboard.

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/ClipboardMonitorTests
```

Expected: FAIL because monitor types do not exist.

- [ ] **Step 3: Implement clipboard monitor**

Implement a timer-driven monitor that:

- Does nothing when recording is paused.
- Ignores unchanged pasteboard `changeCount`.
- Inserts non-empty copied text.
- Saves copied images through `ImageStorage`, then inserts image records.
- Skips an item if image saving fails, then continues monitoring future changes.

- [ ] **Step 4: Run monitor tests**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/ClipboardMonitorTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ClipboardHistory/Services/ClipboardMonitor.swift ClipboardHistoryTests/ClipboardMonitorTests.swift
git commit -m "feat: monitor clipboard changes"
```

## Task 7: Add Paste Service and Global Shortcut

**Files:**
- Create: `ClipboardHistory/Services/PasteService.swift`
- Create: `ClipboardHistory/Services/ShortcutService.swift`
- Create: `ClipboardHistoryTests/PasteServiceTests.swift`

- [ ] **Step 1: Write paste service tests**

Test copy-only behavior by injecting a pasteboard writer and asserting text/image data is written. Do not send keyboard events in unit tests.

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/PasteServiceTests
```

Expected: FAIL because paste service does not exist.

- [ ] **Step 3: Implement paste service**

Implement:

- `copy(_ item: ClipboardItem) throws`
- `copyAndPaste(_ item: ClipboardItem) throws`

`copyAndPaste` should call `copy` first. Then it should send `Command + V` through accessibility/CGEvent. If keyboard event posting fails or permission is missing, the method should leave the item copied and surface a user-visible error state.

- [ ] **Step 4: Implement shortcut service**

Register `Option + Command + V` and call an injected `openPopup` closure. Add a settings-facing display name so settings can display the active shortcut.

- [ ] **Step 5: Run tests**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/PasteServiceTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ClipboardHistory/Services/PasteService.swift ClipboardHistory/Services/ShortcutService.swift ClipboardHistoryTests/PasteServiceTests.swift
git commit -m "feat: restore clipboard items for paste"
```

## Task 8: Build Popup, Rows, Menu Bar, and Settings UI

**Files:**
- Create: `ClipboardHistory/Views/ClipboardPopupView.swift`
- Create: `ClipboardHistory/Views/ClipboardRowView.swift`
- Modify: `ClipboardHistory/Views/MenuBarView.swift`
- Modify: `ClipboardHistory/Views/SettingsView.swift`
- Create: `ClipboardHistory/ViewModels/SettingsViewModel.swift`

- [ ] **Step 1: Add popup UI**

Build a compact SwiftUI window with:

- Search field.
- List of `ClipboardRowView`.
- Text preview for text items.
- Thumbnail preview for image items.
- Favorite button.
- Delete button.
- Primary paste action.
- Copy-only action.

- [ ] **Step 2: Add menu bar UI**

Replace the temporary menu with:

- Open Search.
- Recent Records submenu.
- Favorites submenu.
- Pause Recording or Resume Recording.
- Clear History.
- Settings.
- Quit.

- [ ] **Step 3: Add settings view model**

Implement settings state for retention days, launch at login, shortcut display name, and storage usage bytes.

- [ ] **Step 4: Add settings UI**

Show:

- Retention days numeric field or stepper.
- Launch at login toggle defaulting off.
- Shortcut display value.
- Storage usage display.
- Clear history button that offers non-favorites-only or all-records choices.

- [ ] **Step 5: Run app manually**

Run:

```bash
xcodebuild -scheme ClipboardHistory -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/*/Build/Products/Debug/ClipboardHistory.app
```

Expected: menu bar item appears, settings opens, popup can be opened from menu.

- [ ] **Step 6: Commit**

```bash
git add ClipboardHistory/Views ClipboardHistory/ViewModels/SettingsViewModel.swift
git commit -m "feat: add clipboard history interface"
```

## Task 9: Wire Production Dependencies

**Files:**
- Modify: `ClipboardHistory/App/AppEnvironment.swift`
- Modify: `ClipboardHistory/App/ClipboardHistoryApp.swift`
- Modify: `ClipboardHistory/Services/LoginItemService.swift`

- [ ] **Step 1: Add production storage paths**

Use `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] / "ClipboardHistory"` for the SQLite database and image folder.

- [ ] **Step 2: Wire services**

`AppEnvironment.live()` should create:

- `SQLiteClipboardStore`
- `ImageStorage`
- `ClipboardMonitor`
- `RetentionCleaner`
- `PasteService`
- `ShortcutService`
- history and settings view models

- [ ] **Step 3: Start runtime services**

On app launch:

- Run migrations.
- Run retention cleanup.
- Start clipboard monitoring.
- Register the shortcut.

- [ ] **Step 4: Add login item service**

Implement launch-at-login read/write using Apple's `ServiceManagement` APIs for supported macOS versions. Settings should remain off by default.

- [ ] **Step 5: Run full tests and build**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS'
xcodebuild -scheme ClipboardHistory -destination 'platform=macOS' build
```

Expected: tests and build pass.

- [ ] **Step 6: Commit**

```bash
git add ClipboardHistory/App ClipboardHistory/Services/LoginItemService.swift
git commit -m "feat: wire clipboard history app services"
```

## Task 10: Manual Acceptance Verification

**Files:**
- Create: `docs/verification/2026-05-31-manual-acceptance.md`

- [ ] **Step 1: Create verification checklist**

Write `docs/verification/2026-05-31-manual-acceptance.md` with each acceptance criterion from the design spec and a blank result field.

- [ ] **Step 2: Run full automated verification**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS'
xcodebuild -scheme ClipboardHistory -destination 'platform=macOS' build
```

Expected: both commands pass.

- [ ] **Step 3: Run manual checks**

Launch the app and verify:

- Copy text, search it, paste it.
- Copy an image, see thumbnail.
- Use `Option + Command + V` to open popup.
- Use copy-only action.
- Favorite an item and confirm cleanup does not remove it.
- Delete an item manually.
- Pause recording and confirm new copies are not recorded.
- Clear non-favorites and then clear all records.
- Quit and reopen app; existing records remain.
- Confirm settings default startup launch is off.

- [ ] **Step 4: Record results**

Fill in the verification document with pass/fail notes and any known limitations.

- [ ] **Step 5: Commit**

```bash
git add docs/verification/2026-05-31-manual-acceptance.md
git commit -m "test: document manual acceptance results"
```
