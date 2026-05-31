# Manual Acceptance Verification - 2026-05-31

Task: Manual Acceptance Verification for Version 1 of the native macOS clipboard history app.

Environment note: Full Xcode is now installed and selected. Automated build and test verification was run with Xcode 26.5.

Latest reviewed implementation commit: `956b1d0 test: fix fake store return`.

Post-acceptance-review fixes included before this final verification:

- `f3b79fe`: image files are cleaned up on delete/clear/retention, retention cleanup runs during app lifetime, and shortcut selection is configurable/persisted.
- `250387b`, `c67546c`, `64b6c9c`, `75c4d35`: popup paste targets the previously active app, menu paste avoids stale popup targets, and tests reflect the separated menu/popup paste paths.
- `956b1d0`: fixes the fake store test implementation so the full XCTest target compiles and runs.

## Acceptance Criteria Results

| # | Acceptance criterion | Result | Notes |
|---|---|---|---|
| 1 | Copying text creates a searchable history record. | NOT RUN | Requires full Xcode build/launched app. |
| 2 | Copying an image creates a history record with a thumbnail. | NOT RUN | Requires full Xcode build/launched app. |
| 3 | The global shortcut opens the search popup. | NOT RUN | Requires full Xcode build/launched app. |
| 4 | Selecting a history item restores it to the clipboard and automatically pastes by default. | NOT RUN | Requires full Xcode build/launched app. |
| 5 | A copy-only action is available. | NOT RUN | Requires full Xcode build/launched app. |
| 6 | Records can be favorited. | NOT RUN | Requires full Xcode build/launched app. |
| 7 | Favorite records are not removed by automatic retention cleanup. | NOT RUN | Requires full Xcode build/launched app. |
| 8 | Normal records are cleaned up according to the configured retention period, default 30 days. | NOT RUN | Requires full Xcode build/launched app. |
| 9 | The menu bar can pause or resume recording, clear history, open settings, and quit the app. | NOT RUN | Requires full Xcode build/launched app. |
| 10 | History persists after app restart. | NOT RUN | Requires full Xcode build/launched app. |
| 11 | Data stays on the local Mac. | NOT RUN | Requires full Xcode build/launched app and storage inspection. |
| 12 | Startup launch is configurable and defaults to off. | NOT RUN | Requires full Xcode build/launched app. |
| 13 | Individual history records can be deleted manually. | NOT RUN | Requires full Xcode build/launched app. |

## Automated Verification Attempts

### `xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS'`

Result: PASS.

Exit code: 0

Output:

```text
Test Suite 'ClipboardHistoryTests.xctest' passed.
Executed 36 tests, with 0 failures (0 unexpected).
** TEST SUCCEEDED **
```

### `xcodebuild -scheme ClipboardHistory -destination 'platform=macOS' build`

Result: PASS.

Exit code: 0

Output:

```text
** BUILD SUCCEEDED **
```

## Lightweight Verification

### `swiftc -typecheck $(rg --files ClipboardHistory -g '*.swift')`

Result: PASS.

Exit code: 0

Output: no output.

### `plutil -lint ClipboardHistory.xcodeproj/project.pbxproj`

Result: PASS.

Exit code: 0

Output:

```text
ClipboardHistory.xcodeproj/project.pbxproj: OK
```

### `git diff --check`

Result: PASS.

Exit code: 0

Output: no output.

## Manual Checks

| Check | Status | Notes |
|---|---|---|
| Copy text, search it, paste it. | NOT RUN - requires full Xcode build/launched app | App could not be launched from this environment. |
| Copy an image, see thumbnail. | NOT RUN - requires full Xcode build/launched app | App could not be launched from this environment. |
| Use Option + Command + V to open popup. | NOT RUN - requires full Xcode build/launched app | App could not be launched from this environment. |
| Use copy-only action. | NOT RUN - requires full Xcode build/launched app | App could not be launched from this environment. |
| Favorite an item and confirm cleanup does not remove it. | NOT RUN - requires full Xcode build/launched app | App could not be launched from this environment. |
| Delete an item manually. | NOT RUN - requires full Xcode build/launched app | App could not be launched from this environment. |
| Pause recording and confirm new copies are not recorded. | NOT RUN - requires full Xcode build/launched app | App could not be launched from this environment. |
| Clear non-favorites and then clear all records. | NOT RUN - requires full Xcode build/launched app | App could not be launched from this environment. |
| Quit and reopen app; existing records remain. | NOT RUN - requires full Xcode build/launched app | App could not be launched from this environment. |
| Confirm settings default startup launch is off. | NOT RUN - requires full Xcode build/launched app | App could not be launched from this environment. |

## Summary

Status: DONE_WITH_CONCERNS

The requested manual acceptance checklist was created and all required verification commands were run again after the final review fixes. Full Xcode build and test verification now pass. Manual app interaction checks remain not run and should be performed from the launched menu bar app.
