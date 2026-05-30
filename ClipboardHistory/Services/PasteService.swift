import AppKit
import ApplicationServices
import Foundation

protocol PasteboardWriting {
    func writeText(_ text: String) throws
    func writeImage(_ image: NSImage) throws
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
            return "Text clipboard item is missing text."
        case .missingImagePath:
            return "Image clipboard item is missing an image path."
        case .unreadableImage(let path):
            return "Image clipboard item could not be loaded from \(path)."
        case .pasteboardWriteFailed:
            return "Clipboard item could not be written to the pasteboard."
        case .pasteEventCreationFailed:
            return "Paste keyboard event could not be created."
        case .accessibilityPermissionMissing:
            return "Accessibility permission is required to send the paste command."
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

final class SystemPasteboardWriter: PasteboardWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func writeText(_ text: String) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw PasteServiceError.pasteboardWriteFailed
        }
    }

    func writeImage(_ image: NSImage) throws {
        pasteboard.clearContents()
        guard pasteboard.writeObjects([image]) else {
            throw PasteServiceError.pasteboardWriteFailed
        }
    }
}

final class CGEventPasteEventSender: PasteEventSending {
    private let eventSource: CGEventSource?

    init(eventSource: CGEventSource? = CGEventSource(stateID: .hidSystemState)) {
        self.eventSource = eventSource
    }

    func sendPasteCommand() throws {
        guard AXIsProcessTrusted() else {
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
