import AppKit
import SwiftUI

@MainActor
protocol SettingsWindowPresenting: AnyObject {
    func show(environment: AppEnvironment)
}

@MainActor
final class SettingsWindowPresenter: NSObject, SettingsWindowPresenting, NSWindowDelegate {
    private var window: NSWindow?

    func show(environment: AppEnvironment) {
        if let window {
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = SettingsView()
            .environmentObject(environment)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 500),
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
        window.minSize = NSSize(width: 460, height: 420)

        self.window = window
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
