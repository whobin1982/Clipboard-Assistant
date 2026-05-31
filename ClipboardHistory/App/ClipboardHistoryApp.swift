import AppKit
import SwiftUI

/// SwiftUI 应用入口，负责注册系统菜单命令并共享全局环境对象。
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

/// 全局唯一的应用环境，确保菜单、窗口和快捷键操作的是同一份状态。
@MainActor
private enum SharedAppEnvironment {
    static let environment = AppEnvironment.live()
}

/// AppKit 生命周期代理，用来创建菜单栏应用所需的状态栏按钮。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            NSApplication.shared.setActivationPolicy(.accessory)
            statusItemController = StatusItemController(environment: SharedAppEnvironment.environment)
        }
    }
}

/// 管理 macOS 菜单栏图标、左键历史窗口和右键菜单。
@MainActor
private final class StatusItemController: NSObject {
    private let environment: AppEnvironment
    private let statusItem: NSStatusItem
    private let helpWindowPresenter = HelpWindowPresenter.shared
    private var menuItemsByID: [String: ClipboardItem] = [:]
    private var pendingPreviousApplication: NSRunningApplication?

    init(environment: AppEnvironment) {
        self.environment = environment
        statusItem = NSStatusBar.system.statusItem(withLength: 34)
        super.init()
        configureStatusButton()
    }

    /// 设置菜单栏按钮的图标、提示和鼠标事件监听。
    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.image = Self.statusBarIcon()
        button.imageScaling = .scaleNone
        button.toolTip = "剪贴板历史"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseDown, .leftMouseUp, .rightMouseDown])
    }

    /// 菜单栏使用应用图标；资源缺失时回退到系统剪贴板图标。
    private static func statusBarIcon() -> NSImage {
        if
            let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let image = NSImage(contentsOf: url)
        {
            image.size = NSSize(width: 26, height: 26)
            image.isTemplate = false
            return image
        }

        return NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "剪贴板历史"
        ) ?? NSImage()
    }

    /// 区分左键和右键：左键打开历史窗口，右键显示菜单。
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

    /// 延迟极短时间再打开历史窗口，避免第一次左键点击时状态栏事件还没完全结束。
    private func openHistoryAfterMenuBarClick() {
        let previousApplication = pendingPreviousApplication ?? frontmostApplicationExcludingCurrentApp()
        pendingPreviousApplication = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            Task { @MainActor in
                self?.environment.openSearch(previousApplication: previousApplication)
            }
        }
    }

    /// 记录呼出前真正的前台应用，排除剪贴板助手自己。
    private func frontmostApplicationExcludingCurrentApp() -> NSRunningApplication? {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        guard frontmostApplication?.processIdentifier != NSRunningApplication.current.processIdentifier else {
            return nil
        }
        return frontmostApplication
    }

    /// NSStatusItem 的菜单是临时挂载的，显示完立即清空，避免影响后续左键行为。
    private func showMenu() {
        statusItem.menu = makeMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// 构建右键菜单，包含最近记录、收藏记录、设置、帮助、关于和退出。
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

    /// 把历史记录数组转换成子菜单，并把菜单项 id 映射回 ClipboardItem。
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

    /// 创建统一 target 的菜单项，减少菜单构建时的重复代码。
    private func item(_ title: String, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// 菜单里只展示短标题，避免长文本把系统菜单撑得过宽。
    private func menuTitle(for item: ClipboardItem) -> String {
        switch item.kind {
        case .text:
            let value = item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? "空文本" : String(value.prefix(48))
        case .image:
            return "图片 · \(item.copiedAt.formatted(date: .omitted, time: .shortened))"
        }
    }

    /// 菜单项入口：打开完整历史窗口。
    @objc private func openHistory() {
        openHistoryAfterMenuBarClick()
    }

    /// 菜单项入口：选择某条记录并执行粘贴。
    @objc private func pasteRecord(_ sender: NSMenuItem) {
        guard
            let id = sender.representedObject as? String,
            let item = menuItemsByID[id]
        else {
            return
        }
        environment.paste(item)
    }

    /// 菜单项入口：切换自动记录开关。
    @objc private func toggleRecording() {
        environment.isRecordingPaused.toggle()
    }

    /// 清空非收藏记录前二次确认，避免误删。
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

    /// 清空全部记录前二次确认，收藏记录也会被删除。
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

    /// 菜单项入口：打开设置窗口。
    @objc private func openSettings() {
        environment.openSettings()
    }

    /// 菜单项入口：打开帮助窗口。
    @objc private func openHelp() {
        helpWindowPresenter.show()
    }

    /// 菜单项入口：打开系统关于面板。
    @objc private func showAbout() {
        AboutPanelPresenter.show()
    }

    /// 菜单项入口：退出应用。
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    /// 通用危险操作确认弹窗。
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
