import AppKit
import Carbon.HIToolbox
import Foundation

final class ShortcutService {
    static let defaultShortcutDisplayName = "⌥ + ⌘ + V"
    private static let hotKeySignature = OSType(0x434C4853)

    var shortcutDisplayName: String {
        shortcut.displayName
    }

    private let openPopup: () -> Void
    private var shortcut: ShortcutDefinition
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(shortcut: ShortcutDefinition = .optionCommandV, openPopup: @escaping () -> Void) {
        self.shortcut = shortcut
        self.openPopup = openPopup
    }

    deinit {
        stop()
    }

    func start() {
        guard hotKeyRef == nil else { return }
        installEventHandlerIfNeeded()
        registerHotKey()
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    func updateShortcut(_ shortcut: ShortcutDefinition) {
        let wasRunning = hotKeyRef != nil || eventHandlerRef != nil
        if wasRunning {
            stop()
        }
        self.shortcut = shortcut
        if wasRunning {
            start()
        }
    }

    func triggerForTesting() {
        openPopup()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }

                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard
                    parameterStatus == noErr,
                    hotKeyID.signature == ShortcutService.hotKeySignature
                else {
                    return noErr
                }

                let service = Unmanaged<ShortcutService>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    service.openPopup()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )

        if status != noErr {
            eventHandlerRef = nil
        }
    }

    private func registerHotKey() {
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: 1)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            hotKeyRef = nil
        }
    }
}

private extension ShortcutDefinition {
    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if requiresCommand {
            flags |= UInt32(cmdKey)
        }
        if requiresOption {
            flags |= UInt32(optionKey)
        }
        if requiresControl {
            flags |= UInt32(controlKey)
        }
        if requiresShift {
            flags |= UInt32(shiftKey)
        }
        return flags
    }
}
