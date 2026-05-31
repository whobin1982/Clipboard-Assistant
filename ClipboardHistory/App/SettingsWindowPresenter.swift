import AppKit
import SwiftUI

/// 设置窗口展示接口，方便 AppEnvironment 在测试时替换窗口实现。
@MainActor
protocol SettingsWindowPresenting: AnyObject {
    /// 显示设置窗口，并注入全局应用环境。
    func show(environment: AppEnvironment)
}

/// 用独立 NSWindow 承载 SwiftUI 设置页，并在点击外部区域时自动关闭。
@MainActor
final class SettingsWindowPresenter: NSObject, SettingsWindowPresenting, NSWindowDelegate {
    private var window: NSWindow?
    private var localMouseEventMonitor: Any?
    private var globalMouseEventMonitor: Any?

    /// 创建或复用设置窗口。
    func show(environment: AppEnvironment) {
        if let window {
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            installOutsideClickMonitors()
            return
        }

        let contentView = SettingsView()
            .environmentObject(environment)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "剪贴板助手设置"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ClipboardHistorySettingsWindow")
        window.minSize = NSSize(width: 480, height: 480)

        self.window = window
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        installOutsideClickMonitors()
    }

    /// 窗口关闭时清理事件监听和窗口引用。
    func windowWillClose(_ notification: Notification) {
        removeOutsideClickMonitors()
        window = nil
    }

    /// 设置窗口失去焦点时关闭，符合轻量偏好设置面板的行为。
    func windowDidResignKey(_ notification: Notification) {
        closeWindow()
    }

    /// 统一关闭入口，确保监听总会被清理。
    private func closeWindow() {
        removeOutsideClickMonitors()
        window?.close()
    }

    /// 安装窗口外点击监听：本应用内点击走 local，全局其他应用点击走 global。
    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()

        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            guard let self else { return event }
            guard self.window?.isVisible == true else { return event }
            if event.window === self.window {
                return event
            }
            self.closeWindow()
            return event
        }
        globalMouseEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
            Task { @MainActor in
                self?.closeWindow()
            }
        }
    }

    /// 移除鼠标事件监听，避免重复安装或窗口关闭后继续回调。
    private func removeOutsideClickMonitors() {
        if let localMouseEventMonitor {
            NSEvent.removeMonitor(localMouseEventMonitor)
            self.localMouseEventMonitor = nil
        }
        if let globalMouseEventMonitor {
            NSEvent.removeMonitor(globalMouseEventMonitor)
            self.globalMouseEventMonitor = nil
        }
    }
}
