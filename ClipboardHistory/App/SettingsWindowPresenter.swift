import AppKit
import SwiftUI

@MainActor
protocol SettingsWindowPresenting: AnyObject {
    func show(environment: AppEnvironment)
}

@MainActor
final class SettingsWindowPresenter: NSObject, SettingsWindowPresenting, NSWindowDelegate {
    private var window: NSWindow?
    private var localMouseEventMonitor: Any?
    private var globalMouseEventMonitor: Any?

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

    func windowWillClose(_ notification: Notification) {
        removeOutsideClickMonitors()
        window = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        closeWindow()
    }

    private func closeWindow() {
        removeOutsideClickMonitors()
        window?.close()
    }

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
