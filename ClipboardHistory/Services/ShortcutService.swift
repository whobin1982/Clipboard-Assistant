import AppKit
import Foundation

final class ShortcutService {
    static let defaultShortcutDisplayName = "Option + Command + V"

    var shortcutDisplayName: String {
        shortcut.displayName
    }

    private let openPopup: () -> Void
    private var shortcut: ShortcutDefinition
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(shortcut: ShortcutDefinition = .optionCommandV, openPopup: @escaping () -> Void) {
        self.shortcut = shortcut
        self.openPopup = openPopup
    }

    deinit {
        stop()
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    func updateShortcut(_ shortcut: ShortcutDefinition) {
        self.shortcut = shortcut
    }

    func triggerForTesting() {
        openPopup()
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        guard matchesShortcut(event) else { return false }
        openPopup()
        return true
    }

    private func matchesShortcut(_ event: NSEvent) -> Bool {
        let relevantFlags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        return event.keyCode == shortcut.keyCode && relevantFlags == shortcut.modifierFlags
    }
}

private extension ShortcutDefinition {
    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if requiresCommand {
            flags.insert(.command)
        }
        if requiresOption {
            flags.insert(.option)
        }
        if requiresControl {
            flags.insert(.control)
        }
        if requiresShift {
            flags.insert(.shift)
        }
        return flags
    }
}
