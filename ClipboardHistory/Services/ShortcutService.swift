import AppKit
import Carbon.HIToolbox
import Foundation

/// 注册和管理全局快捷键，用来从任意应用呼出剪贴板历史窗口。
final class ShortcutService {
    static let defaultShortcutDisplayName = "⌥ + ⌘ + V"
    /// Carbon hot key signature，用四个字符的整数值区分本应用的快捷键事件。
    private static let hotKeySignature = OSType(0x434C4853)

    /// 当前快捷键展示名。
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

    /// 安装事件处理器并注册当前快捷键。
    func start() {
        guard hotKeyRef == nil else { return }
        installEventHandlerIfNeeded()
        registerHotKey()
    }

    /// 注销快捷键和事件处理器。
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

    /// 更新快捷键；如果服务正在运行，会先注销旧快捷键再注册新快捷键。
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

    /// 测试专用入口，直接触发回调而不依赖系统快捷键事件。
    func triggerForTesting() {
        openPopup()
    }

    /// 安装 Carbon 事件处理器，收到本应用 hot key 事件时切回主线程打开窗口。
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

    /// 将当前快捷键注册为系统全局快捷键。
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

/// 将 ShortcutDefinition 的布尔修饰键转换成 Carbon API 所需的位掩码。
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
