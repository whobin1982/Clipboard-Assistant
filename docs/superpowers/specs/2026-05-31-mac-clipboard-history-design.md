# Mac Clipboard History App Design

## Background

The user wants a Mac desktop app that remembers clipboard history so previously copied content can be found and reused without going back to the original source.

The first version should feel like a lightweight Mac system utility: always available when needed, not visually heavy, and focused on fast recall.

## Confirmed Product Direction

Build a balanced first version:

- Primary experience: keyboard shortcut popup for searching and pasting clipboard history.
- Secondary experience: menu bar utility for common actions and settings.
- Platform: macOS.
- Storage: local Mac only for version 1.
- Visual style: native Mac feel, minimal decoration, supports light and dark appearance where practical.

## Version 1 Scope

Version 1 includes:

- Clipboard history for text and images.
- Text keyword search.
- Image records shown with thumbnail and copied time.
- Local persistence across app restarts.
- Configurable retention period, defaulting to 30 days.
- Favorites that are kept indefinitely unless manually deleted.
- Default action: copy the selected history item back to the system clipboard and automatically paste it into the current app.
- Secondary action: copy only, without automatic paste.
- Menu bar controls for opening search, viewing recent items and favorites, pausing or resuming recording, clearing history, opening settings, and quitting.
- Settings for retention period, startup behavior, keyboard shortcut, storage usage, and clearing history.

Version 1 does not include:

- Cloud sync or iCloud sync.
- OCR for image text search.
- Manual tags or notes for images.
- Excluding specific source apps from recording.
- Complex folders, categories, or library-style management.
- Automatic sensitive-content detection or hiding.

## Core User Flow

1. The app runs in the background.
2. When the user copies text or an image, the app records it as a clipboard history item.
3. The user presses the global shortcut, initially recommended as `Option + Command + V`.
4. A small popup window opens with a search field and recent history.
5. Typing filters text records by keyword.
6. Image records appear with thumbnails and copied time.
7. Selecting an item restores it to the system clipboard.
8. By default, the app automatically pastes the selected item into the previously active app.
9. The user can choose a copy-only action when automatic paste is not desired.
10. The user can favorite a record so it will not expire during automatic cleanup.

## Data Model

Each clipboard history item should store:

- Unique ID.
- Type: text or image.
- Created/copied timestamp.
- Last used timestamp, if useful for sorting later.
- Favorite flag.
- Text content for text records.
- Image file path and thumbnail path for image records.

Storage requirements:

- All data remains on the local Mac.
- Data persists after quitting and reopening the app.
- Normal history is eligible for cleanup after the configured retention period.
- Favorite items are excluded from automatic cleanup.

## Retention and Cleanup

Default retention is 30 days. The user can change it in settings.

Automatic cleanup removes non-favorite items older than the configured retention period. Favorites are removed only through manual deletion. The clear-history action should ask whether to clear all records or only non-favorite records.

Because image history can consume disk space, settings should show approximate storage usage. Version 1 should include a basic storage warning or visible usage indicator so the user understands when image history grows large.

## Privacy and Control

Version 1 records clipboard content as ordinary local history, including potentially sensitive text. It does not try to detect passwords, verification codes, bank card numbers, or other sensitive data.

User controls:

- Pause or resume clipboard recording from the menu bar.
- Clear history from the menu bar or settings.
- Delete individual history items from the popup or menu bar history view.
- Disable startup launch by default, with an option to enable it.

## Interface Structure

### Shortcut Popup

Purpose: fast search and reuse.

Contains:

- Search field.
- Recent text and image records.
- Image thumbnails.
- Copied time.
- Favorite marker or action.
- Primary action: paste.
- Secondary action: copy only.

### Menu Bar Menu

Purpose: lightweight control and access.

Contains:

- Open search.
- Recent records.
- Favorites.
- Pause or resume recording.
- Clear history.
- Settings.
- Quit.

### Settings

Purpose: simple configuration.

Contains:

- Retention period, default 30 days.
- Startup launch toggle, default off.
- Keyboard shortcut setting.
- Storage usage display.
- Clear history action.

## Error Handling

The app should handle these situations gracefully:

- Clipboard access permission or monitoring fails: show a clear status in the menu bar/settings and suggest reopening or checking permissions.
- Automatic paste cannot be performed in the active app: still copy the item to the clipboard and show a brief notification or status.
- Image saving fails: skip the item and keep recording future clipboard changes.
- Database or storage errors: avoid crashing where possible and show a clear error in settings.

## Acceptance Criteria

Version 1 is complete when:

1. Copying text creates a searchable history record.
2. Copying an image creates a history record with a thumbnail.
3. The global shortcut opens the search popup.
4. Selecting a history item restores it to the clipboard and automatically pastes by default.
5. A copy-only action is available.
6. Records can be favorited.
7. Favorite records are not removed by automatic retention cleanup.
8. Normal records are cleaned up according to the configured retention period, default 30 days.
9. The menu bar can pause or resume recording, clear history, open settings, and quit the app.
10. History persists after app restart.
11. Data stays on the local Mac.
12. Startup launch is configurable and defaults to off.
13. Individual history records can be deleted manually.

## Open Decisions for Implementation Planning

These decisions should be made during the implementation plan:

- Exact macOS app technology: native Swift/SwiftUI is likely the best fit for a Mac-native utility.
- Exact local storage mechanism: SQLite, Core Data, or another local database.
- Exact automatic paste method and required accessibility permissions.
- Exact shortcut conflict handling.
