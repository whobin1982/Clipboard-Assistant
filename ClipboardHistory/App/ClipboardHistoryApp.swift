import AppKit
import SwiftUI

@main
struct ClipboardHistoryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment = SharedAppEnvironment.environment

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(environment)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于剪贴板助手") {
                    AboutPanelPresenter.show()
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button("设置...") {
                    environment.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .help) {
                Button("剪贴板助手帮助") {
                    HelpWindowPresenter.shared.show()
                }
            }
        }
    }
}

@MainActor
private enum SharedAppEnvironment {
    static let environment = AppEnvironment.live()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            NSApplication.shared.setActivationPolicy(.accessory)
            statusItemController = StatusItemController(environment: SharedAppEnvironment.environment)
        }
    }
}

@MainActor
private final class StatusItemController: NSObject {
    private let environment: AppEnvironment
    private let statusItem: NSStatusItem
    private let helpWindowPresenter = HelpWindowPresenter.shared
    private var menuItemsByID: [String: ClipboardItem] = [:]
    private var pendingPreviousApplication: NSRunningApplication?

    init(environment: AppEnvironment) {
        self.environment = environment
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureStatusButton()
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "剪贴板历史"
        )
        button.toolTip = "剪贴板历史"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseDown, .leftMouseUp, .rightMouseDown])
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        switch NSApp.currentEvent?.type {
        case .rightMouseDown:
            showMenu()
        case .leftMouseDown:
            pendingPreviousApplication = frontmostApplicationExcludingCurrentApp()
        case .leftMouseUp:
            openHistoryAfterMenuBarClick()
        default:
            break
        }
    }

    private func openHistoryAfterMenuBarClick() {
        let previousApplication = pendingPreviousApplication ?? frontmostApplicationExcludingCurrentApp()
        pendingPreviousApplication = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            Task { @MainActor in
                self?.environment.openSearch(previousApplication: previousApplication)
            }
        }
    }

    private func frontmostApplicationExcludingCurrentApp() -> NSRunningApplication? {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        guard frontmostApplication?.processIdentifier != NSRunningApplication.current.processIdentifier else {
            return nil
        }
        return frontmostApplication
    }

    private func showMenu() {
        statusItem.menu = makeMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func makeMenu() -> NSMenu {
        environment.historyViewModel.reload()
        menuItemsByID = [:]

        let menu = NSMenu()
        menu.addItem(item("打开剪贴板历史", action: #selector(openHistory)))

        if let message = environment.lastErrorMessage ?? environment.settingsViewModel.lastErrorMessage {
            let errorItem = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        menu.addItem(.separator())
        menu.addItem(submenuItem("最近记录", items: Array(environment.historyViewModel.items.prefix(8))))
        menu.addItem(submenuItem("收藏记录", items: environment.historyViewModel.items.filter(\.isFavorite)))

        menu.addItem(.separator())
        menu.addItem(item(
            environment.isRecordingPaused ? "继续记录剪贴板" : "暂停记录剪贴板",
            action: #selector(toggleRecording)
        ))

        let clearMenu = NSMenu()
        clearMenu.addItem(item("清空非收藏记录", action: #selector(clearNonFavorites)))
        clearMenu.addItem(item("清空全部记录", action: #selector(clearAllRecords)))
        let clearItem = NSMenuItem(title: "清空历史", action: nil, keyEquivalent: "")
        clearItem.submenu = clearMenu
        menu.addItem(clearItem)

        menu.addItem(.separator())
        menu.addItem(item("设置", action: #selector(openSettings)))
        menu.addItem(item("帮助", action: #selector(openHelp)))
        menu.addItem(item("关于剪贴板助手", action: #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(item("退出", action: #selector(quit)))

        return menu
    }

    private func submenuItem(_ title: String, items: [ClipboardItem]) -> NSMenuItem {
        let submenu = NSMenu()
        if items.isEmpty {
            let emptyItem = NSMenuItem(title: "暂无记录", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            for item in items {
                let menuItem = self.item(menuTitle(for: item), action: #selector(pasteRecord(_:)))
                menuItem.representedObject = item.id.uuidString
                menuItemsByID[item.id.uuidString] = item
                submenu.addItem(menuItem)
            }
        }

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func item(_ title: String, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func menuTitle(for item: ClipboardItem) -> String {
        switch item.kind {
        case .text:
            let value = item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? "空文本" : String(value.prefix(48))
        case .image:
            return "图片 · \(item.copiedAt.formatted(date: .omitted, time: .shortened))"
        }
    }

    @objc private func openHistory() {
        openHistoryAfterMenuBarClick()
    }

    @objc private func pasteRecord(_ sender: NSMenuItem) {
        guard
            let id = sender.representedObject as? String,
            let item = menuItemsByID[id]
        else {
            return
        }
        environment.paste(item)
    }

    @objc private func toggleRecording() {
        environment.isRecordingPaused.toggle()
    }

    @objc private func clearNonFavorites() {
        guard confirmClear(
            title: "清空非收藏记录？",
            message: "这会删除所有没有标记为收藏的剪贴板记录。",
            confirmTitle: "清空非收藏记录"
        ) else {
            return
        }
        environment.settingsViewModel.clearNonFavorites()
    }

    @objc private func clearAllRecords() {
        guard confirmClear(
            title: "清空全部记录？",
            message: "这会删除所有剪贴板记录，包括收藏记录。",
            confirmTitle: "清空全部记录"
        ) else {
            return
        }
        environment.settingsViewModel.clearAll()
    }

    @objc private func openSettings() {
        environment.openSettings()
    }

    @objc private func openHelp() {
        helpWindowPresenter.show()
    }

    @objc private func showAbout() {
        AboutPanelPresenter.show()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func confirmClear(title: String, message: String, confirmTitle: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
