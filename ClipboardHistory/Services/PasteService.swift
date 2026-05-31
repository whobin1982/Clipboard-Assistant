import AppKit
import ApplicationServices
import Foundation

/// 系统剪贴板写入抽象，方便测试验证写入内容。
protocol PasteboardWriting {
    /// 写入文本到系统剪贴板。
    func writeText(_ text: String) throws
    /// 写入图片归档到系统剪贴板。
    func writeImageArchive(_ archive: ClipboardImageArchive) throws
}

/// 本应用写入剪贴板时使用的内部标记，监听器据此跳过重复记录。
enum ClipboardPasteboardMarker {
    static let type = NSPasteboard.PasteboardType("com.hubin.ClipboardAssistant.internal-copy")
    static let value = "clipboard-assistant"
}

/// 自动粘贴事件发送抽象，便于测试替换 CGEvent。
protocol PasteEventSending {
    func sendPasteCommand() throws
}

/// 复制或自动粘贴过程中可能展示给用户的错误。
enum PasteServiceError: Error, Equatable, LocalizedError {
    case missingText
    case missingImagePath
    case unreadableImage(String)
    case pasteboardWriteFailed
    case pasteEventCreationFailed
    case accessibilityPermissionMissing

    var errorDescription: String? {
        switch self {
        case .missingText:
            return "这条文本记录没有可复制的内容。"
        case .missingImagePath:
            return "这条图片记录缺少图片文件路径。"
        case .unreadableImage(let path):
            return "无法读取图片文件：\(path)。"
        case .pasteboardWriteFailed:
            return "无法写入系统剪贴板。"
        case .pasteEventCreationFailed:
            return "无法创建自动粘贴按键事件。"
        case .accessibilityPermissionMissing:
            return "需要在系统设置里开启辅助功能权限，才能自动执行粘贴。"
        }
    }
}

/// 统一处理“复制到系统剪贴板”和“发送 Cmd+V 自动粘贴”。
final class PasteService {
    private let pasteboard: PasteboardWriting
    private let pasteEventSender: PasteEventSending

    init(
        pasteboard: PasteboardWriting = SystemPasteboardWriter(),
        pasteEventSender: PasteEventSending = CGEventPasteEventSender()
    ) {
        self.pasteboard = pasteboard
        self.pasteEventSender = pasteEventSender
    }

    /// 将历史记录写回系统剪贴板；文本直接写入，图片从本地归档恢复。
    func copy(_ item: ClipboardItem) throws {
        switch item.kind {
        case .text:
            guard let text = item.text else {
                throw PasteServiceError.missingText
            }
            try pasteboard.writeText(text)
        case .image:
            guard let imagePath = item.imagePath else {
                throw PasteServiceError.missingImagePath
            }
            let imageURL = URL(fileURLWithPath: imagePath)
            let archive: ClipboardImageArchive
            do {
                archive = try Self.imageArchive(from: imageURL)
            } catch {
                throw PasteServiceError.unreadableImage(imagePath)
            }
            try pasteboard.writeImageArchive(archive)
        }
    }

    /// 复制后立即发送粘贴快捷键。
    func copyAndPaste(_ item: ClipboardItem) throws {
        try copy(item)
        try sendPasteCommand()
    }

    /// 发送系统 Cmd+V；权限和事件创建错误由底层实现抛出。
    func sendPasteCommand() throws {
        try pasteEventSender.sendPasteCommand()
    }

    /// 从磁盘路径恢复图片归档；兼容早期只保存单个图片文件的记录。
    private static func imageArchive(from imageURL: URL) throws -> ClipboardImageArchive {
        if imageURL.pathExtension == ClipboardImageArchive.fileExtension {
            let archive = try ClipboardImageArchive.load(from: imageURL)
            guard archive.firstImage != nil else {
                throw PasteServiceError.unreadableImage(imageURL.path)
            }
            return archive
        }

        let imageData = try Data(contentsOf: imageURL)
        let payload = ClipboardImagePayload(
            data: imageData,
            pasteboardType: ClipboardImagePayload.pasteboardType(forFileExtension: imageURL.pathExtension)
        )
        guard payload.image != nil else {
            throw PasteServiceError.unreadableImage(imageURL.path)
        }
        return ClipboardImageArchive.single(payload)
    }
}

/// 辅助功能权限请求器，保证同一运行会话只弹一次系统授权提示。
enum AccessibilityPermission {
    private static var didRequestPromptThisSession = false

    /// 如果尚未授权，则请求系统显示辅助功能权限弹窗。
    static func requestIfNeeded() {
        guard !AXIsProcessTrusted(), !didRequestPromptThisSession else { return }

        didRequestPromptThisSession = true
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}

/// 使用 NSPasteboard 写入系统剪贴板。
final class SystemPasteboardWriter: PasteboardWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// 写入文本，同时写入内部 marker，防止监听器重复记录。
    func writeText(_ text: String) throws {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, ClipboardPasteboardMarker.type], owner: nil)
        guard
            pasteboard.setString(text, forType: .string),
            pasteboard.setString(ClipboardPasteboardMarker.value, forType: ClipboardPasteboardMarker.type)
        else {
            throw PasteServiceError.pasteboardWriteFailed
        }
    }

    /// 写入图片归档中的每个 pasteboard item，并保留同一图片的多种格式。
    func writeImageArchive(_ archive: ClipboardImageArchive) throws {
        var items: [NSPasteboardItem] = []
        for archiveItem in archive.items {
            let item = NSPasteboardItem()
            var didWriteImage = false
            for payload in archiveItem {
                guard payload.image != nil else { continue }
                guard item.setData(payload.data, forType: payload.pasteboardType) else {
                    throw PasteServiceError.pasteboardWriteFailed
                }
                didWriteImage = true
            }
            guard didWriteImage else { continue }
            // marker 只需要写到第一个 item，即可让监听器识别这是本应用写入。
            if items.isEmpty {
                guard item.setString(ClipboardPasteboardMarker.value, forType: ClipboardPasteboardMarker.type) else {
                    throw PasteServiceError.pasteboardWriteFailed
                }
            }
            items.append(item)
        }

        guard !items.isEmpty else {
            throw PasteServiceError.pasteboardWriteFailed
        }

        pasteboard.clearContents()
        guard pasteboard.writeObjects(items) else {
            throw PasteServiceError.pasteboardWriteFailed
        }
    }
}

/// 使用 CGEvent 向当前焦点应用发送 Command + V。
final class CGEventPasteEventSender: PasteEventSending {
    private let eventSource: CGEventSource?

    init(eventSource: CGEventSource? = CGEventSource(stateID: .combinedSessionState)) {
        self.eventSource = eventSource
    }

    /// 发送粘贴按键；未授权辅助功能时先触发授权提示再抛错。
    func sendPasteCommand() throws {
        guard AXIsProcessTrusted() else {
            AccessibilityPermission.requestIfNeeded()
            throw PasteServiceError.accessibilityPermissionMissing
        }

        let keyCodeForV: CGKeyCode = 9
        guard
            let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCodeForV, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCodeForV, keyDown: false)
        else {
            throw PasteServiceError.pasteEventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
