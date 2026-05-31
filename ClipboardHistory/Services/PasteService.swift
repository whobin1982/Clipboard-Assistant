import AppKit
import ApplicationServices
import Foundation

protocol PasteboardWriting {
    func writeText(_ text: String) throws
    func writeImage(_ image: NSImage) throws
}

enum ClipboardPasteboardMarker {
    static let type = NSPasteboard.PasteboardType("com.hubin.ClipboardAssistant.internal-copy")
    static let value = "clipboard-assistant"
}

protocol PasteEventSending {
    func sendPasteCommand() throws
}

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
            guard let image = NSImage(contentsOfFile: imagePath) else {
                throw PasteServiceError.unreadableImage(imagePath)
            }
            try pasteboard.writeImage(image)
        }
    }

    func copyAndPaste(_ item: ClipboardItem) throws {
        try copy(item)
        try sendPasteCommand()
    }

    func sendPasteCommand() throws {
        try pasteEventSender.sendPasteCommand()
    }
}

enum AccessibilityPermission {
    private static var didRequestPromptThisSession = false

    static func requestIfNeeded() {
        guard !AXIsProcessTrusted(), !didRequestPromptThisSession else { return }

        didRequestPromptThisSession = true
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}

final class SystemPasteboardWriter: PasteboardWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

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

    func writeImage(_ image: NSImage) throws {
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff, ClipboardPasteboardMarker.type], owner: nil)
        let imageData = try Self.imagePasteboardData(from: image)
        guard
            pasteboard.setData(imageData.png, forType: .png),
            pasteboard.setData(imageData.tiff, forType: .tiff),
            pasteboard.setString(ClipboardPasteboardMarker.value, forType: ClipboardPasteboardMarker.type)
        else {
            throw PasteServiceError.pasteboardWriteFailed
        }
    }

    private static func imagePasteboardData(from image: NSImage) throws -> (png: Data, tiff: Data) {
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw PasteServiceError.pasteboardWriteFailed
        }

        return (png, tiff)
    }
}

final class CGEventPasteEventSender: PasteEventSending {
    private let eventSource: CGEventSource?

    init(eventSource: CGEventSource? = CGEventSource(stateID: .combinedSessionState)) {
        self.eventSource = eventSource
    }

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
