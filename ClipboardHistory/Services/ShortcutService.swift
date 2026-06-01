import AppKit
import Carbon.HIToolbox
import Foundation

/// 全局快捷键注册失败时向设置页展示的错误。
enum ShortcutServiceError: LocalizedError, Equatable {
    case eventHandlerInstallFailed(OSStatus)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .eventHandlerInstallFailed:
            return "无法安装快捷键监听器，请重启剪贴板助手后再试。"
        case .registrationFailed:
            return "快捷键注册失败，可能已被其他应用占用。请换一个快捷键组合。"
        }
    }
}

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
    private let registerHotKeyHandler: (ShortcutDefinition, EventHotKeyID, inout EventHotKeyRef?) -> OSStatus
    private var shortcut: ShortcutDefinition
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(
        shortcut: ShortcutDefinition = .optionCommandV,
        openPopup: @escaping () -> Void,
        registerHotKeyHandler: @escaping (ShortcutDefinition, EventHotKeyID, inout EventHotKeyRef?) -> OSStatus = { shortcut, hotKeyID, hotKeyRef in
            RegisterEventHotKey(
                UInt32(shortcut.keyCode),
                shortcut.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
        }
    ) {
        self.shortcut = shortcut
        self.openPopup = openPopup
        self.registerHotKeyHandler = registerHotKeyHandler
    }

    deinit {
        stop()
    }

    /// 安装事件处理器并注册当前快捷键。
    func start() throws {
        guard hotKeyRef == nil else { return }
        do {
            try installEventHandlerIfNeeded()
            try registerHotKey()
        } catch {
            stop()
            throw error
        }
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
    func updateShortcut(_ shortcut: ShortcutDefinition) throws {
        let wasRunning = hotKeyRef != nil || eventHandlerRef != nil
        let previousShortcut = self.shortcut
        if wasRunning {
            stop()
        }
        self.shortcut = shortcut
        if wasRunning {
            do {
                try start()
            } catch {
                self.shortcut = previousShortcut
                try? start()
                throw error
            }
        }
    }

    /// 测试专用入口，直接触发回调而不依赖系统快捷键事件。
    func triggerForTesting() {
        openPopup()
    }

    /// 安装 Carbon 事件处理器，收到本应用 hot key 事件时切回主线程打开窗口。
    private func installEventHandlerIfNeeded() throws {
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
            throw ShortcutServiceError.eventHandlerInstallFailed(status)
        }
    }

    /// 将当前快捷键注册为系统全局快捷键。
    private func registerHotKey() throws {
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: 1)
        let status = registerHotKeyHandler(shortcut, hotKeyID, &hotKeyRef)

        if status != noErr || hotKeyRef == nil {
            hotKeyRef = nil
            throw ShortcutServiceError.registrationFailed(status)
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
