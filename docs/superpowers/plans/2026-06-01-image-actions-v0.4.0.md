# Image Actions v0.4.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add image-only context menu actions for copying an image, showing a clear no-OCR-text message, exporting an image, and publish v0.4.0.

**Architecture:** Keep `ClipboardRowView` as the row interaction surface and inject image action callbacks from `ClipboardPopupView`, `SearchWindowPresenter`, and `AppEnvironment`. Add a small `ImageExportService` that loads the existing `ClipboardImageArchive` and writes the first decoded image as PNG through an injectable save destination picker.

**Tech Stack:** Swift, SwiftUI context menus, AppKit `NSSavePanel`, `NSBitmapImageRep`, XCTest, GitHub CLI.

---

### Task 1: Context Menu Wiring

**Files:**
- Modify: `ClipboardHistory/Views/ClipboardRowView.swift`
- Modify: `ClipboardHistory/Views/ClipboardPopupView.swift`
- Modify: `ClipboardHistory/App/SearchWindowPresenter.swift`
- Test: `ClipboardHistoryTests/ClipboardRowViewTests.swift`

- [ ] **Step 1: Write failing row menu tests**

Create `ClipboardHistoryTests/ClipboardRowViewTests.swift` with tests that host `ClipboardRowView` and inspect its context-menu command labels:

```swift
import AppKit
import SwiftUI
import XCTest
@testable import ClipboardHistory

@MainActor
final class ClipboardRowViewTests: XCTestCase {
    func testImageRowContextMenuContainsImageActions() throws {
        let item = ClipboardItem.image(imagePath: "/tmp/image.clipboardimage", thumbnailPath: "/tmp/thumb.png")
        let view = ClipboardRowView(
            item: item,
            shortcutNumber: nil,
            isSelected: false,
            onFavorite: {},
            onDelete: {},
            onPaste: {},
            onCopy: {},
            onCopyImageText: {},
            onExportImage: {}
        )

        let labels = contextMenuLabels(for: view)

        XCTAssertTrue(labels.contains("复制图片"))
        XCTAssertTrue(labels.contains("复制图片文字"))
        XCTAssertTrue(labels.contains("导出图片"))
    }

    func testTextRowContextMenuDoesNotContainImageActions() throws {
        let view = ClipboardRowView(
            item: .text("hello"),
            shortcutNumber: nil,
            isSelected: false,
            onFavorite: {},
            onDelete: {},
            onPaste: {},
            onCopy: {},
            onCopyImageText: {},
            onExportImage: {}
        )

        let labels = contextMenuLabels(for: view)

        XCTAssertFalse(labels.contains("复制图片"))
        XCTAssertFalse(labels.contains("复制图片文字"))
        XCTAssertFalse(labels.contains("导出图片"))
    }
}
```

- [ ] **Step 2: Run the new tests and confirm they fail**

Run:

```bash
xcodebuild test -project ClipboardHistory.xcodeproj -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/ClipboardRowViewTests
```

Expected: build fails because `ClipboardRowView` does not yet expose `onCopyImageText` and `onExportImage`.

- [ ] **Step 3: Add row callbacks and context menu**

Update `ClipboardRowView` to accept `onCopyImageText` and `onExportImage`, then add:

```swift
.contextMenu {
    if item.kind == .image {
        Button("复制图片", action: onCopy)
        Button("复制图片文字", action: onCopyImageText)
        Divider()
        Button("导出图片", action: onExportImage)
    }
}
```

Update every `ClipboardRowView` initializer in app and tests.

- [ ] **Step 4: Pass the image action callbacks through window layers**

Add `onCopyImageText` and `onExportImage` to `ClipboardPopupView`, `SearchWindowPresenting.show`, `SearchWindowPresenter.show`, and all fake presenters.

- [ ] **Step 5: Run targeted tests**

Run:

```bash
xcodebuild test -project ClipboardHistory.xcodeproj -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/ClipboardRowViewTests
```

Expected: the row menu tests pass.

### Task 2: Image Text Placeholder Action

**Files:**
- Modify: `ClipboardHistory/App/AppEnvironment.swift`
- Test: `ClipboardHistoryTests/SettingsViewModelTests.swift`

- [ ] **Step 1: Write failing environment test**

Add an `AppEnvironmentTests` case that calls the new `onCopyImageText` callback captured by the fake presenter:

```swift
@MainActor
func testCopyImageTextWithoutOCRShowsMessage() throws {
    let recorder = AppEnvironmentCallRecorder()
    let item = ClipboardItem.image(imagePath: "/tmp/image.clipboardimage", thumbnailPath: "/tmp/thumb.png")
    let store = AppEnvironmentFakeStore(items: [item], recorder: recorder)
    let presenter = AppEnvironmentFakeSearchWindowPresenter(recorder: recorder)
    let environment = AppEnvironment(store: store, searchWindowPresenter: presenter)

    environment.openSearch()
    try XCTUnwrap(presenter.onCopyImageText)(item)

    XCTAssertEqual(environment.lastErrorMessage, "这张图片还没有可复制的识别文字。")
    XCTAssertFalse(recorder.calls.contains { $0.hasPrefix("writeText:") })
}
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
xcodebuild test -project ClipboardHistory.xcodeproj -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/AppEnvironmentTests/testCopyImageTextWithoutOCRShowsMessage
```

Expected: build fails until the callback is added.

- [ ] **Step 3: Implement no-OCR-text action**

Add `copyImageText(_:)` to `AppEnvironment`:

```swift
func copyImageText(_ item: ClipboardItem) {
    guard item.kind == .image else { return }
    lastErrorMessage = "这张图片还没有可复制的识别文字。"
}
```

Pass this method into `SearchWindowPresenter.show`.

- [ ] **Step 4: Run targeted test**

Run the same `xcodebuild test -only-testing` command. Expected: pass.

### Task 3: Image Export Service

**Files:**
- Create: `ClipboardHistory/Services/ImageExportService.swift`
- Modify: `ClipboardHistory/App/AppEnvironment.swift`
- Test: `ClipboardHistoryTests/ImageExportServiceTests.swift`
- Test: `ClipboardHistoryTests/SettingsViewModelTests.swift`

- [ ] **Step 1: Write failing service tests**

Create `ImageExportServiceTests` covering successful PNG export, cancel, and unreadable images. Use a fake destination picker returning either a file URL or nil.

- [ ] **Step 2: Implement export types**

Create:

```swift
protocol ImageExportDestinationChoosing {
    func exportDestination(defaultFilename: String) -> URL?
}

enum ImageExportServiceError: LocalizedError, Equatable {
    case missingImagePath
    case unreadableImage(String)
    case writeFailed
}
```

Use the same Chinese error strings as the design.

- [ ] **Step 3: Implement PNG export**

`ImageExportService.export(_:)` should:

1. Return `.cancelled` if the picker returns nil.
2. Load `ClipboardImageArchive` when the path extension is `clipboardimage`.
3. Otherwise load a legacy image file as `NSImage`.
4. Convert the image to PNG with `NSBitmapImageRep`.
5. Write to the selected URL.

- [ ] **Step 4: Wire export into app environment**

Inject `ImageExportService` into `AppEnvironment`, add `exportImage(_:)`, and pass it to the history window.

- [ ] **Step 5: Run targeted tests**

Run:

```bash
xcodebuild test -project ClipboardHistory.xcodeproj -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/ImageExportServiceTests -only-testing:ClipboardHistoryTests/AppEnvironmentTests/testExportImageWritesPNGFile
```

Expected: pass.

### Task 4: Documentation and Version

**Files:**
- Modify: `README.md`
- Modify: `ClipboardHistory/Resources/HelpREADME.md`
- Modify: `ClipboardHistory.xcodeproj/project.pbxproj`

- [ ] **Step 1: Update docs**

Document image right-click actions in README and help. Keep OCR wording clear: copying image text currently needs future OCR data.

- [ ] **Step 2: Bump version**

Change both `MARKETING_VERSION = 0.3.0;` entries to `MARKETING_VERSION = 0.4.0;`.

- [ ] **Step 3: Run version check**

Run:

```bash
rg "MARKETING_VERSION = 0.4.0|当前版本：`0.4.0`" ClipboardHistory.xcodeproj README.md
```

Expected: project and README mention 0.4.0.

### Task 5: Full Verification and Release

**Files:**
- Generated: `dist/剪贴板助手-v0.4.0.dmg`

- [ ] **Step 1: Run full tests**

```bash
git diff --check
xcodebuild test -project ClipboardHistory.xcodeproj -scheme ClipboardHistory -destination 'platform=macOS'
```

Expected: all tests pass.

- [ ] **Step 2: Build Release app**

```bash
xcodebuild -project ClipboardHistory.xcodeproj -scheme ClipboardHistory -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/ClipboardHistory-v0.4.0 build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Create and verify DMG**

```bash
scripts/create_release_dmg.sh '/tmp/ClipboardHistory-v0.4.0/Build/Products/Release/剪贴板助手.app' 'dist/剪贴板助手-v0.4.0.dmg'
hdiutil verify 'dist/剪贴板助手-v0.4.0.dmg'
```

Expected: DMG verifies successfully.

- [ ] **Step 4: Commit, push, PR, merge, tag, and release**

```bash
git add .
git commit -m "feat: add image context actions"
git push -u origin codex/v0.4-image-actions
gh pr create --base main --head codex/v0.4-image-actions --title "[codex] 发布 v0.4.0 图片右键操作" --body-file /tmp/pr-body.md
```

After checks and merge:

```bash
git switch main
git pull --ff-only
git tag -a v0.4.0 -m "v0.4.0"
git push origin v0.4.0
gh release create v0.4.0 'dist/剪贴板助手-v0.4.0.dmg' --title '剪贴板助手 v0.4.0' --notes-file /tmp/release-notes.md
```

Expected: GitHub Release exists and issue #8 is closed.
