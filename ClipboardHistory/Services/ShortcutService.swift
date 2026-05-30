import AppKit
import Foundation

final class ShortcutService {
    static let defaultShortcutDisplayName = "Option + Command + V"

    var shortcutDisplayName: String {
        Self.defaultShortcutDisplayName
    }

    private let openPopup: () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(openPopup: @escaping () -> Void) {
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

    func triggerForTesting() {
        openPopup()
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        guard isDefaultShortcut(event) else { return false }
        openPopup()
        return true
    }

    private func isDefaultShortcut(_ event: NSEvent) -> Bool {
        let keyCodeForV: UInt16 = 9
        let relevantFlags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        return event.keyCode == keyCodeForV && relevantFlags == [.command, .option]
    }
}
