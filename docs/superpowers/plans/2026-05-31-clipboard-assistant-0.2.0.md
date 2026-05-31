# Clipboard Assistant 0.2.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add keyboard-driven history selection and a richer Chinese settings page for paste behavior, shortcuts, startup, and retention.

**Architecture:** Extend the existing settings model first, then route selection behavior through `AppEnvironment` so click, Enter, and menu actions share the same copy/paste policy. Keep `SearchWindowPresenter` responsible for AppKit window lifecycle and move keyboard selection into focused SwiftUI/AppKit bridge components that can be tested without relying on full UI automation.

**Tech Stack:** Swift 5, SwiftUI, AppKit, Carbon hotkeys, XCTest, existing Xcode project and `xcodebuild test`.

---

## File Structure

- Modify `ClipboardHistory/Models/AppSettings.swift`: add paste behavior settings, richer retention policy, and fixed/custom shortcut definitions.
- Modify `ClipboardHistory/ViewModels/SettingsViewModel.swift`: expose settings bindings and validation methods for the expanded settings page.
- Modify `ClipboardHistory/Services/RetentionCleaner.swift`: skip cleanup when retention is permanent.
- Modify `ClipboardHistory/App/AppEnvironment.swift`: apply paste behavior settings for popup selection and retention cleanup.
- Modify `ClipboardHistory/Services/ShortcutService.swift`: support the new shortcut definitions and custom Carbon modifier combinations.
- Modify `ClipboardHistory/Views/SettingsView.swift`: reorganize settings into Chinese sections with toggles, pickers, and custom inputs.
- Modify `ClipboardHistory/Views/ClipboardPopupView.swift`: add keyboard selection state, Enter selection, and Esc close hook.
- Modify `ClipboardHistory/Views/ClipboardRowView.swift`: let the row render selected state using system selection colors.
- Modify `ClipboardHistory/App/SearchWindowPresenter.swift`: pass Esc close behavior and selection actions into the popup.
- Modify tests in `ClipboardHistoryTests/*.swift`: add TDD coverage for settings defaults, paste behavior, retention, shortcut persistence, and keyboard selection reducer.

## Task 1: Settings Model

**Files:**
- Modify: `ClipboardHistory/Models/AppSettings.swift`
- Test: `ClipboardHistoryTests/ClipboardItemTests.swift`

- [ ] **Step 1: Write failing tests for 0.2.0 defaults and compatibility**

Add tests to `ClipboardHistoryTests/ClipboardItemTests.swift`:

```swift
func testDefaultSettingsUseKeyboardPasteDefaults() {
    XCTAssertEqual(AppSettings.default.selectionAction, .paste)
    XCTAssertTrue(AppSettings.default.closeWindowAfterSelection)
    XCTAssertTrue(AppSettings.default.escapeClosesWindow)
    XCTAssertEqual(AppSettings.default.retentionPolicy, .days(30))
    XCTAssertEqual(AppSettings.default.shortcut.id, ShortcutDefinition.optionCommandV.id)
}

func testPermanentRetentionPolicyStoresZeroRetentionDaysForCompatibility() {
    var settings = AppSettings.default
    settings.retentionPolicy = .forever

    XCTAssertEqual(settings.retentionDays, 0)
}

func testAvailableShortcutsContainFixedOptions() {
    XCTAssertEqual(
        ShortcutDefinition.available.map(\.id),
        [
            ShortcutDefinition.optionCommandV.id,
            ShortcutDefinition.controlCommandV.id,
            ShortcutDefinition.shiftCommandV.id
        ]
    )
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/ClipboardItemTests
```

Expected: fails because `selectionAction`, `closeWindowAfterSelection`, `escapeClosesWindow`, `retentionPolicy`, `controlCommandV`, and `shiftCommandV` do not exist yet.

- [ ] **Step 3: Implement model additions**

In `ClipboardHistory/Models/AppSettings.swift`, add:

```swift
enum ClipboardSelectionAction: String, Codable, Equatable, CaseIterable, Identifiable {
    case paste
    case copyOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paste:
            return "自动粘贴"
        case .copyOnly:
            return "只复制到剪贴板"
        }
    }
}

enum RetentionPolicy: Equatable {
    case days(Int)
    case forever
}
```

Update `ShortcutDefinition` fixed options:

```swift
static let controlCommandV = ShortcutDefinition(
    id: "control-command-v",
    displayName: "⌃ + ⌘ + V",
    keyCode: 9,
    requiresCommand: true,
    requiresOption: false,
    requiresControl: true,
    requiresShift: false
)

static let shiftCommandV = ShortcutDefinition(
    id: "shift-command-v",
    displayName: "⇧ + ⌘ + V",
    keyCode: 9,
    requiresCommand: true,
    requiresOption: false,
    requiresControl: false,
    requiresShift: true
)

static let available: [ShortcutDefinition] = [
    .optionCommandV,
    .controlCommandV,
    .shiftCommandV
]
```

Update `AppSettings` fields and defaults:

```swift
var selectionAction: ClipboardSelectionAction
var closeWindowAfterSelection: Bool
var escapeClosesWindow: Bool

var retentionPolicy: RetentionPolicy {
    get {
        retentionDays <= 0 ? .forever : .days(retentionDays)
    }
    set {
        switch newValue {
        case .days(let days):
            retentionDays = max(1, days)
        case .forever:
            retentionDays = 0
        }
    }
}

static let `default` = AppSettings(
    retentionDays: 30,
    launchAtLogin: false,
    shortcutID: ShortcutDefinition.optionCommandV.id,
    selectionAction: .paste,
    closeWindowAfterSelection: true,
    escapeClosesWindow: true
)
```

Add optional decoding defaults for new fields in `init(from:)`:

```swift
selectionAction = try container.decodeIfPresent(ClipboardSelectionAction.self, forKey: .selectionAction) ?? .paste
closeWindowAfterSelection = try container.decodeIfPresent(Bool.self, forKey: .closeWindowAfterSelection) ?? true
escapeClosesWindow = try container.decodeIfPresent(Bool.self, forKey: .escapeClosesWindow) ?? true
```

Encode the new fields.

- [ ] **Step 4: Run model tests to verify pass**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/ClipboardItemTests
```

Expected: pass.

## Task 2: Settings View Model

**Files:**
- Modify: `ClipboardHistory/ViewModels/SettingsViewModel.swift`
- Test: `ClipboardHistoryTests/SettingsViewModelTests.swift`

- [ ] **Step 1: Write failing tests for settings bindings**

Add tests to `SettingsViewModelTests`:

```swift
func testChangingSelectionActionPersistsSettings() {
    var savedSettings: [AppSettings] = []
    let viewModel = SettingsViewModel(settingsDidChange: { savedSettings.append($0) })

    viewModel.selectionAction = .copyOnly

    XCTAssertEqual(viewModel.settings.selectionAction, .copyOnly)
    XCTAssertEqual(savedSettings.last?.selectionAction, .copyOnly)
}

func testChangingCloseAndEscapeSettingsPersistsSettings() {
    var savedSettings: [AppSettings] = []
    let viewModel = SettingsViewModel(settingsDidChange: { savedSettings.append($0) })

    viewModel.closeWindowAfterSelection = false
    viewModel.escapeClosesWindow = false

    XCTAssertFalse(viewModel.settings.closeWindowAfterSelection)
    XCTAssertFalse(viewModel.settings.escapeClosesWindow)
    XCTAssertEqual(savedSettings.last?.escapeClosesWindow, false)
}

func testRetentionPolicySupportsForeverAndCustomDays() {
    var cleanupCalls = 0
    let viewModel = SettingsViewModel(retentionDaysDidChange: { _ in cleanupCalls += 1 })

    viewModel.retentionPolicy = .forever
    XCTAssertEqual(viewModel.settings.retentionPolicy, .forever)

    viewModel.customRetentionDaysText = "90"
    viewModel.applyCustomRetentionDays()

    XCTAssertEqual(viewModel.settings.retentionPolicy, .days(90))
    XCTAssertEqual(cleanupCalls, 2)
    XCTAssertNil(viewModel.lastErrorMessage)
}

func testInvalidCustomRetentionDaysDoesNotOverwriteSetting() {
    let viewModel = SettingsViewModel()
    viewModel.customRetentionDaysText = "0"

    viewModel.applyCustomRetentionDays()

    XCTAssertEqual(viewModel.settings.retentionPolicy, .days(30))
    XCTAssertEqual(viewModel.lastErrorMessage, "请输入大于 0 的保留天数。")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/SettingsViewModelTests
```

Expected: fails because the new view model properties do not exist.

- [ ] **Step 3: Implement settings bindings and validation**

In `SettingsViewModel`, add:

```swift
@Published var customRetentionDaysText: String

var selectionAction: ClipboardSelectionAction {
    get { settings.selectionAction }
    set {
        settings.selectionAction = newValue
        settingsDidChange(settings)
        lastErrorMessage = nil
    }
}

var closeWindowAfterSelection: Bool {
    get { settings.closeWindowAfterSelection }
    set {
        settings.closeWindowAfterSelection = newValue
        settingsDidChange(settings)
        lastErrorMessage = nil
    }
}

var escapeClosesWindow: Bool {
    get { settings.escapeClosesWindow }
    set {
        settings.escapeClosesWindow = newValue
        settingsDidChange(settings)
        lastErrorMessage = nil
    }
}

var retentionPolicy: RetentionPolicy {
    get { settings.retentionPolicy }
    set {
        settings.retentionPolicy = newValue
        customRetentionDaysText = settings.retentionDays > 0 ? "\(settings.retentionDays)" : ""
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

func applyCustomRetentionDays() {
    guard let days = Int(customRetentionDaysText.trimmingCharacters(in: .whitespacesAndNewlines)), days > 0 else {
        lastErrorMessage = "请输入大于 0 的保留天数。"
        return
    }
    retentionPolicy = .days(days)
}
```

Initialize `customRetentionDaysText` in `init`:

```swift
self.customRetentionDaysText = settings.retentionDays > 0 ? "\(settings.retentionDays)" : ""
```

- [ ] **Step 4: Run settings view model tests**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/SettingsViewModelTests
```

Expected: pass.

## Task 3: Retention Cleanup

**Files:**
- Modify: `ClipboardHistory/Services/RetentionCleaner.swift`
- Modify: `ClipboardHistory/App/AppEnvironment.swift`
- Test: `ClipboardHistoryTests/RetentionCleanerTests.swift`
- Test: `ClipboardHistoryTests/SettingsViewModelTests.swift`

- [ ] **Step 1: Write failing test for permanent retention**

Add to `RetentionCleanerTests`:

```swift
func testRunKeepsAllItemsWhenRetentionIsForever() throws {
    let oldItem = ClipboardItem.text("old", copiedAt: Date(timeIntervalSince1970: 0))
    let store = InMemoryClipboardStore(items: [oldItem])
    let cleaner = RetentionCleaner(store: store)
    var settings = AppSettings.default
    settings.retentionPolicy = .forever

    try cleaner.run(now: Date(timeIntervalSince1970: 10_000_000), settings: settings)

    XCTAssertEqual(try store.fetchAll().map(\.id), [oldItem.id])
}
```

- [ ] **Step 2: Run retention test to verify it fails**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/RetentionCleanerTests
```

Expected: fails because retention with `0` days deletes older non-favorite items.

- [ ] **Step 3: Implement permanent retention skip**

In `RetentionCleaner.run`:

```swift
func run(now: Date = Date(), settings: AppSettings) throws {
    guard settings.retentionDays > 0 else { return }
    let cutoff = now.addingTimeInterval(TimeInterval(-settings.retentionDays * 24 * 60 * 60))
    try store.deleteNonFavorites(olderThan: cutoff)
}
```

In `AppEnvironment.runRetentionCleanup`, add the same guard before computing cutoff:

```swift
guard settings.retentionDays > 0 else { return }
```

- [ ] **Step 4: Run retention and environment tests**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/RetentionCleanerTests -only-testing:ClipboardHistoryTests/AppEnvironmentTests
```

Expected: pass.

## Task 4: Popup Selection Behavior

**Files:**
- Create: `ClipboardHistory/ViewModels/ClipboardSelectionController.swift`
- Modify: `ClipboardHistory.xcodeproj/project.pbxproj`
- Test: `ClipboardHistoryTests/ClipboardSelectionControllerTests.swift`

- [ ] **Step 1: Write failing controller tests**

Create `ClipboardHistoryTests/ClipboardSelectionControllerTests.swift`:

```swift
import XCTest
@testable import ClipboardHistory

final class ClipboardSelectionControllerTests: XCTestCase {
    func testStartsWithNoSelectionAndDownSelectsFirstItem() {
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")
        let controller = ClipboardSelectionController()

        controller.moveDown(in: [first, second])

        XCTAssertEqual(controller.selectedItemID, first.id)
    }

    func testUpAndDownMoveWithinBounds() {
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")
        let controller = ClipboardSelectionController()

        controller.moveDown(in: [first, second])
        controller.moveDown(in: [first, second])
        controller.moveDown(in: [first, second])
        XCTAssertEqual(controller.selectedItemID, second.id)

        controller.moveUp(in: [first, second])
        controller.moveUp(in: [first, second])
        XCTAssertEqual(controller.selectedItemID, first.id)
    }

    func testSelectedItemClearsWhenFilteredOut() {
        let first = ClipboardItem.text("first")
        let controller = ClipboardSelectionController()
        controller.moveDown(in: [first])

        controller.reconcileSelection(with: [])

        XCTAssertNil(controller.selectedItemID)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/ClipboardSelectionControllerTests
```

Expected: fails because `ClipboardSelectionController` does not exist.

- [ ] **Step 3: Implement controller**

Create `ClipboardHistory/ViewModels/ClipboardSelectionController.swift`:

```swift
import Foundation

final class ClipboardSelectionController: ObservableObject {
    @Published private(set) var selectedItemID: UUID?

    func moveDown(in items: [ClipboardItem]) {
        guard !items.isEmpty else {
            selectedItemID = nil
            return
        }

        guard let selectedItemID,
              let currentIndex = items.firstIndex(where: { $0.id == selectedItemID })
        else {
            selectedItemID = items[0].id
            return
        }

        let nextIndex = min(items.index(after: currentIndex), items.index(before: items.endIndex))
        self.selectedItemID = items[nextIndex].id
    }

    func moveUp(in items: [ClipboardItem]) {
        guard !items.isEmpty else {
            selectedItemID = nil
            return
        }

        guard let selectedItemID,
              let currentIndex = items.firstIndex(where: { $0.id == selectedItemID })
        else {
            self.selectedItemID = items[0].id
            return
        }

        let previousIndex = currentIndex == items.startIndex ? currentIndex : items.index(before: currentIndex)
        self.selectedItemID = items[previousIndex].id
    }

    func selectedItem(in items: [ClipboardItem]) -> ClipboardItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    func reconcileSelection(with items: [ClipboardItem]) {
        guard let selectedItemID else { return }
        if !items.contains(where: { $0.id == selectedItemID }) {
            self.selectedItemID = nil
        }
    }
}
```

Add the file to the Xcode project target.

- [ ] **Step 4: Run controller tests**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/ClipboardSelectionControllerTests
```

Expected: pass.

## Task 5: Keyboard Events in History Window

**Files:**
- Modify: `ClipboardHistory/Views/ClipboardPopupView.swift`
- Modify: `ClipboardHistory/Views/ClipboardRowView.swift`
- Modify: `ClipboardHistory/App/SearchWindowPresenter.swift`
- Test: `ClipboardHistoryTests/SettingsViewModelTests.swift`

- [ ] **Step 1: Add presenter test for Esc configuration**

Extend `SearchWindowPresenterTests`:

```swift
func testSearchWindowPassesEscapeCloseConfigurationToPopup() {
    let presenter = SearchWindowPresenter()
    let viewModel = ClipboardHistoryViewModel(store: AppEnvironmentFakeStore(items: []))

    presenter.show(
        viewModel: viewModel,
        previousApplication: nil,
        escapeClosesWindow: false,
        onPaste: { _ in },
        onCopy: { _ in },
        onDelete: { _ in }
    )
    defer { presenter.orderOut() }

    XCTAssertNotNil(NSApp.windows.first { $0.title == "剪贴板历史" })
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/SearchWindowPresenterTests/testSearchWindowPassesEscapeCloseConfigurationToPopup
```

Expected: fails because `show` does not accept `escapeClosesWindow`.

- [ ] **Step 3: Update presenter API and popup view**

Update `SearchWindowPresenting.show` signature to include:

```swift
escapeClosesWindow: Bool,
onClose: @escaping () -> Void,
```

When constructing `ClipboardPopupView`, pass both values.

In `ClipboardPopupView`, add:

```swift
@StateObject private var selectionController = ClipboardSelectionController()
let escapeClosesWindow: Bool
let onClose: () -> Void
```

Render rows with selected state:

```swift
ClipboardRowView(
    item: item,
    isSelected: selectionController.selectedItemID == item.id,
    onFavorite: { viewModel.toggleFavorite(item) },
    onDelete: { onDelete(item) },
    onPaste: { onPaste(item) },
    onCopy: { onCopy(item) }
)
```

Add keyboard handling with an AppKit key event bridge so the behavior does not depend on SwiftUI focus quirks:

```swift
KeyEventHandlingView(
    onDownArrow: {
        selectionController.moveDown(in: viewModel.filteredItems)
    },
    onUpArrow: {
        selectionController.moveUp(in: viewModel.filteredItems)
    },
    onReturn: {
        guard let item = selectionController.selectedItem(in: viewModel.filteredItems) else { return }
        onPaste(item)
    },
    onEscape: {
        if escapeClosesWindow {
            onClose()
        }
    }
)
.frame(width: 0, height: 0)
.onAppear {
    viewModel.reload()
}
.onChange(of: viewModel.filteredItems.map(\.id)) { _, _ in
    selectionController.reconcileSelection(with: viewModel.filteredItems)
}
```

Create `KeyEventHandlingView` in `ClipboardPopupView.swift` or a new focused file:

```swift
private struct KeyEventHandlingView: NSViewRepresentable {
    let onDownArrow: () -> Void
    let onUpArrow: () -> Void
    let onReturn: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.onDownArrow = onDownArrow
        view.onUpArrow = onUpArrow
        view.onReturn = onReturn
        view.onEscape = onEscape
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        nsView.onDownArrow = onDownArrow
        nsView.onUpArrow = onUpArrow
        nsView.onReturn = onReturn
        nsView.onEscape = onEscape
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class KeyCatcherView: NSView {
    var onDownArrow: () -> Void = {}
    var onUpArrow: () -> Void = {}
    var onReturn: () -> Void = {}
    var onEscape: () -> Void = {}

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125:
            onDownArrow()
        case 126:
            onUpArrow()
        case 36:
            onReturn()
        case 53:
            onEscape()
        default:
            super.keyDown(with: event)
        }
    }
}
```

Update `ClipboardRowView` initializer:

```swift
let isSelected: Bool
```

Apply system selection background:

```swift
.padding(.horizontal, 6)
.background(
    RoundedRectangle(cornerRadius: 6)
        .fill(isSelected ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear)
)
```

- [ ] **Step 4: Run presenter and build tests**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/SearchWindowPresenterTests
```

Expected: pass.

## Task 6: Paste Behavior Policy

**Files:**
- Modify: `ClipboardHistory/App/AppEnvironment.swift`
- Test: `ClipboardHistoryTests/SettingsViewModelTests.swift`

- [ ] **Step 1: Write failing tests for copy-only and close behavior**

Add to `AppEnvironmentTests`:

```swift
@MainActor
func testPopupSelectionCopyOnlyDoesNotSendPasteCommand() throws {
    let recorder = AppEnvironmentCallRecorder()
    let item = ClipboardItem.text("Saved text")
    let store = AppEnvironmentFakeStore(items: [item], recorder: recorder)
    let pasteboard = AppEnvironmentFakePasteboardWriter(recorder: recorder)
    let sender = AppEnvironmentFakePasteEventSender(recorder: recorder, onSend: {})
    let pasteService = PasteService(pasteboard: pasteboard, pasteEventSender: sender)
    let presenter = AppEnvironmentFakeSearchWindowPresenter(recorder: recorder)
    var settings = AppSettings.default
    settings.selectionAction = .copyOnly
    let environment = AppEnvironment(
        store: store,
        pasteService: pasteService,
        searchWindowPresenter: presenter,
        settings: settings
    )

    environment.openSearch()
    recorder.calls.removeAll()
    try XCTUnwrap(presenter.onPaste)(item)

    XCTAssertEqual(pasteboard.writtenText, "Saved text")
    XCTAssertFalse(recorder.calls.contains("sendPasteCommand"))
    XCTAssertTrue(recorder.calls.contains("orderOut"))
}

@MainActor
func testPopupSelectionCanKeepWindowOpenAfterCopyOnly() throws {
    let recorder = AppEnvironmentCallRecorder()
    let item = ClipboardItem.text("Saved text")
    let presenter = AppEnvironmentFakeSearchWindowPresenter(recorder: recorder)
    var settings = AppSettings.default
    settings.selectionAction = .copyOnly
    settings.closeWindowAfterSelection = false
    let environment = AppEnvironment(
        store: AppEnvironmentFakeStore(items: [item], recorder: recorder),
        searchWindowPresenter: presenter,
        settings: settings
    )

    environment.openSearch()
    recorder.calls.removeAll()
    try XCTUnwrap(presenter.onPaste)(item)

    XCTAssertFalse(recorder.calls.contains("orderOut"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/AppEnvironmentTests
```

Expected: fails because popup selection always sends paste and always closes.

- [ ] **Step 3: Implement selection policy**

In `AppEnvironment.openSearch`, pass:

```swift
escapeClosesWindow: settingsViewModel.settings.escapeClosesWindow,
onClose: { [weak self] in self?.searchWindowPresenter.orderOut() },
```

Refactor `pasteFromSearchWindow`:

```swift
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            Task { @MainActor in
                self?.sendPasteCommand()
            }
        }
    } catch {
        lastErrorMessage = error.localizedDescription
    }
}
```

- [ ] **Step 4: Run environment tests**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/AppEnvironmentTests
```

Expected: pass.

## Task 7: Settings Page UI

**Files:**
- Modify: `ClipboardHistory/Views/SettingsView.swift`
- Test: `ClipboardHistoryTests/SettingsViewModelTests.swift`

- [ ] **Step 1: Confirm view model tests cover UI bindings**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/SettingsViewModelTests
```

Expected: pass from Task 2.

- [ ] **Step 2: Implement Chinese settings UI sections**

Replace the current `Form` sections with:

```swift
Section("粘贴行为") {
    Picker("选择记录后", selection: selectionAction) {
        ForEach(ClipboardSelectionAction.allCases) { action in
            Text(action.title).tag(action)
        }
    }
    .pickerStyle(.segmented)

    Toggle("选择后关闭窗口", isOn: closeWindowAfterSelection)
    Toggle("按 Esc 关闭窗口", isOn: escapeClosesWindow)
}

Section("快捷键") {
    Picker("呼出历史窗口", selection: shortcutID) {
        ForEach(viewModel.availableShortcuts) { shortcut in
            Text(shortcut.displayName).tag(shortcut.id)
        }
    }
    .pickerStyle(.menu)

    ShortcutRecorderView { shortcut in
        viewModel.applyCustomShortcut(shortcut)
    }

    Text("点击录入区域后按下新的组合键。")
        .font(.caption)
        .foregroundStyle(.secondary)
}

Section("启动与历史") {
    Toggle("开机自动启动", isOn: launchAtLogin)

    Picker("保留历史", selection: retentionPolicy) {
        Text("7 天").tag(RetentionPolicy.days(7))
        Text("30 天").tag(RetentionPolicy.days(30))
        Text("90 天").tag(RetentionPolicy.days(90))
        Text("永久").tag(RetentionPolicy.forever)
    }
    .pickerStyle(.segmented)

    HStack {
        TextField("自定义天数", text: customRetentionDaysText)
            .frame(width: 100)
        Button("应用") {
            viewModel.applyCustomRetentionDays()
        }
    }

    HStack {
        Text("已用空间")
        Spacer()
        Text(viewModel.storageUsageDescription)
            .foregroundStyle(.secondary)
    }
}
```

Add SwiftUI bindings for `selectionAction`, `closeWindowAfterSelection`, `escapeClosesWindow`, `retentionPolicy`, and `customRetentionDaysText`.

- [ ] **Step 3: Continue to custom shortcut capture before the next build gate**

Do not run the full build yet because `SettingsView` now references `ShortcutRecorderView`, which Task 8 creates. Continue immediately to Task 8, then run the combined build and test commands there.

## Task 8: Custom Shortcut Capture

**Files:**
- Create: `ClipboardHistory/Views/ShortcutRecorderView.swift`
- Modify: `ClipboardHistory/Models/AppSettings.swift`
- Modify: `ClipboardHistory/ViewModels/SettingsViewModel.swift`
- Modify: `ClipboardHistory/Views/SettingsView.swift`
- Test: `ClipboardHistoryTests/ShortcutServiceTests.swift`

- [ ] **Step 1: Write failing test for custom shortcut persistence**

Add to `ShortcutServiceTests`:

```swift
func testCustomShortcutDefinitionPersistsModifiersAndKeyCode() {
    let shortcut = ShortcutDefinition.custom(
        displayName: "⌃ + ⇧ + C",
        keyCode: 8,
        requiresCommand: false,
        requiresOption: false,
        requiresControl: true,
        requiresShift: true
    )
    let settings = AppSettings(
        retentionDays: 30,
        launchAtLogin: false,
        shortcutID: shortcut.id,
        selectionAction: .paste,
        closeWindowAfterSelection: true,
        escapeClosesWindow: true,
        customShortcut: shortcut
    )

    XCTAssertEqual(settings.shortcut, shortcut)
}
```

- [ ] **Step 2: Run shortcut test to verify it fails**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/ShortcutServiceTests
```

Expected: fails because custom shortcut storage is not implemented.

- [ ] **Step 3: Implement custom shortcut model**

Add to `ShortcutDefinition`:

```swift
static func custom(
    displayName: String,
    keyCode: UInt16,
    requiresCommand: Bool,
    requiresOption: Bool,
    requiresControl: Bool,
    requiresShift: Bool
) -> ShortcutDefinition {
    ShortcutDefinition(
        id: "custom",
        displayName: displayName,
        keyCode: keyCode,
        requiresCommand: requiresCommand,
        requiresOption: requiresOption,
        requiresControl: requiresControl,
        requiresShift: requiresShift
    )
}
```

Add `var customShortcut: ShortcutDefinition?` to `AppSettings`. Update `shortcut`:

```swift
var shortcut: ShortcutDefinition {
    if shortcutID == "custom", let customShortcut {
        return customShortcut
    }
    return ShortcutDefinition.definition(for: shortcutID)
}
```

Encode and decode `customShortcut`.

- [ ] **Step 4: Implement recorder view**

Create `ShortcutRecorderView.swift` as `NSViewRepresentable` that accepts a keyDown event, requires at least one modifier plus a non-modifier key, builds a display name, and calls:

```swift
var onRecord: (ShortcutDefinition) -> Void
```

In `SettingsViewModel`, add:

```swift
func applyCustomShortcut(_ shortcut: ShortcutDefinition) {
    settings.customShortcut = shortcut
    settings.shortcutID = shortcut.id
    settingsDidChange(settings)
    shortcutDidChange(shortcut)
    lastErrorMessage = nil
}
```

In `SettingsView`, place the recorder under the fixed shortcut picker with button text "录入自定义快捷键".

- [ ] **Step 5: Run shortcut and settings tests**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS' -only-testing:ClipboardHistoryTests/ShortcutServiceTests -only-testing:ClipboardHistoryTests/SettingsViewModelTests
```

Expected: pass.

## Task 9: Full Verification and Packaging

**Files:**
- Modify as required from previous tasks.
- Generated: `dist/剪贴板助手-0.2.0.dmg`

- [ ] **Step 1: Run all tests**

Run:

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS'
```

Expected: all tests pass.

- [ ] **Step 2: Build release**

Run:

```bash
rm -rf dist/build dist/dmg-root
xcodebuild -scheme ClipboardHistory -configuration Release -destination 'platform=macOS' -derivedDataPath dist/build build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Install local app**

Run:

```bash
osascript -e 'tell application "剪贴板助手" to quit' || true
rm -rf /Applications/剪贴板助手.app
/usr/bin/ditto "dist/build/Build/Products/Release/剪贴板助手.app" "/Applications/剪贴板助手.app"
open /Applications/剪贴板助手.app
sleep 1
pgrep -fl '剪贴板助手|ClipboardHistory' || true
```

Expected: shows `/Applications/剪贴板助手.app/Contents/MacOS/剪贴板助手`.

- [ ] **Step 4: Create and verify DMG**

Run:

```bash
rm -rf dist/dmg-root dist/剪贴板助手-0.2.0.dmg
mkdir -p dist/dmg-root
/usr/bin/ditto "/Applications/剪贴板助手.app" "dist/dmg-root/剪贴板助手.app"
ln -s /Applications "dist/dmg-root/应用程序"
hdiutil create -volname "剪贴板助手 0.2.0" -srcfolder "dist/dmg-root" -ov -format UDZO "dist/剪贴板助手-0.2.0.dmg"
hdiutil verify "dist/剪贴板助手-0.2.0.dmg"
rm -rf dist/dmg-root dist/build
```

Expected: `checksum ... is VALID`.

- [ ] **Step 5: Manual smoke test**

Run the app and verify:

- Left click menu bar icon opens history window.
- Press Down once selects the first item.
- Press Enter performs the configured action.
- Copy-only mode does not paste into the frontmost app.
- Paste mode pastes into the frontmost input field when Accessibility permission is enabled.
- Esc closes the window when the setting is enabled.
- Settings page is Chinese and persists changes after app restart.

## Self-Review

- Spec coverage: keyboard selection, Enter selection, Esc close, paste vs copy-only, close-after-selection, shortcut fixed/custom, startup toggle, retention fixed/custom/permanent, tests, packaging are all represented.
- Placeholder scan: no unfinished markers or undefined task references remain.
- Type consistency: `ClipboardSelectionAction`, `RetentionPolicy`, `ClipboardSelectionController`, `shortcutID`, `customShortcut`, `escapeClosesWindow`, and `closeWindowAfterSelection` are used consistently across tasks.
