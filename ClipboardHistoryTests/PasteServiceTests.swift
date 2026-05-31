import AppKit
import Foundation
import XCTest
@testable import ClipboardHistory

final class PasteServiceTests: XCTestCase {
    func testCopyTextWritesTextToPasteboard() throws {
        let pasteboard = FakePasteboardWriter()
        let service = PasteService(pasteboard: pasteboard, pasteEventSender: FakePasteEventSender())

        try service.copy(.text("Saved text"))

        XCTAssertEqual(pasteboard.writtenText, "Saved text")
        XCTAssertNil(pasteboard.writtenImagePayload)
    }

    func testSystemPasteboardWriterMarksTextAsClipboardHistoryCopy() throws {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name(UUID().uuidString)))
        let writer = SystemPasteboardWriter(pasteboard: pasteboard)

        try writer.writeText("Saved text")

        XCTAssertEqual(pasteboard.string(forType: .string), "Saved text")
        XCTAssertEqual(
            pasteboard.string(forType: ClipboardPasteboardMarker.type),
            ClipboardPasteboardMarker.value
        )
    }

    func testCopyImageWritesLoadedImageToPasteboard() throws {
        let pasteboard = FakePasteboardWriter()
        let service = PasteService(pasteboard: pasteboard, pasteEventSender: FakePasteEventSender())
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        let imageData = try XCTUnwrap(makeTestImage().pngData)
        try imageData.write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        try service.copy(.image(imagePath: imageURL.path, thumbnailPath: "/tmp/thumb.png"))

        XCTAssertEqual(pasteboard.writtenImagePayload?.data, imageData)
        XCTAssertEqual(pasteboard.writtenImagePayload?.pasteboardType, .png)
        XCTAssertNil(pasteboard.writtenText)
    }

    func testSystemPasteboardWriterMarksImageAsClipboardHistoryCopy() throws {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name(UUID().uuidString)))
        let writer = SystemPasteboardWriter(pasteboard: pasteboard)

        let imageData = try XCTUnwrap(makeTestImage().pngData)
        try writer.writeImage(ClipboardImagePayload(data: imageData, pasteboardType: .png))

        XCTAssertEqual(
            pasteboard.string(forType: ClipboardPasteboardMarker.type),
            ClipboardPasteboardMarker.value
        )
    }

    func testSystemPasteboardWriterPublishesOriginalImageDataAndFallbacks() throws {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name(UUID().uuidString)))
        let writer = SystemPasteboardWriter(pasteboard: pasteboard)
        let jpegData = try XCTUnwrap(makeTestImage().jpegData)
        let jpegType = NSPasteboard.PasteboardType("public.jpeg")

        try writer.writeImage(ClipboardImagePayload(data: jpegData, pasteboardType: jpegType))

        XCTAssertEqual(pasteboard.data(forType: jpegType), jpegData)
        XCTAssertNotNil(pasteboard.data(forType: .png))
        XCTAssertNotNil(pasteboard.data(forType: .tiff))
        XCTAssertEqual(
            pasteboard.string(forType: ClipboardPasteboardMarker.type),
            ClipboardPasteboardMarker.value
        )
    }

    func testSystemPasteboardReaderReadsPngImagePayload() throws {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name(UUID().uuidString)))
        let imageData = try XCTUnwrap(makeTestImage().pngData)
        pasteboard.declareTypes([.png], owner: nil)
        pasteboard.setData(imageData, forType: .png)
        let reader = SystemPasteboardReader(pasteboard: pasteboard)
        let payload = try XCTUnwrap(reader.readImagePayload())

        XCTAssertEqual(payload.data, imageData)
        XCTAssertEqual(payload.pasteboardType, .png)
    }

    func testSystemPasteboardReaderIgnoresImageFileURL() throws {
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try XCTUnwrap(makeTestImage().pngData).write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name(UUID().uuidString)))
        pasteboard.clearContents()
        pasteboard.writeObjects([imageURL as NSURL])
        let reader = SystemPasteboardReader(pasteboard: pasteboard)

        XCTAssertNil(reader.readImagePayload())
    }

    func testCopyAndPasteCopiesThenSendsPasteCommand() throws {
        let recorder = CallRecorder()
        let pasteboard = FakePasteboardWriter(recorder: recorder)
        let sender = FakePasteEventSender(recorder: recorder)
        let service = PasteService(pasteboard: pasteboard, pasteEventSender: sender)

        try service.copyAndPaste(.text("Saved text"))

        XCTAssertEqual(recorder.calls, ["writeText:Saved text", "sendPasteCommand"])
    }

    func testCopyAndPasteThrowsWhenPasteSenderFailsAfterCopying() {
        let pasteboard = FakePasteboardWriter()
        let sender = FakePasteEventSender(error: TestError.pasteFailed)
        let service = PasteService(pasteboard: pasteboard, pasteEventSender: sender)

        XCTAssertThrowsError(try service.copyAndPaste(.text("Saved text"))) { error in
            XCTAssertEqual(error as? TestError, .pasteFailed)
        }
        XCTAssertEqual(pasteboard.writtenText, "Saved text")
    }

    func testCopyTextThrowsWhenTextIsMissing() {
        let item = ClipboardItem(
            id: UUID(),
            kind: .text,
            copiedAt: Date(),
            lastUsedAt: nil,
            isFavorite: false,
            text: nil,
            imagePath: nil,
            thumbnailPath: nil
        )
        let service = PasteService(pasteboard: FakePasteboardWriter(), pasteEventSender: FakePasteEventSender())

        XCTAssertThrowsError(try service.copy(item)) { error in
            XCTAssertEqual(error as? PasteServiceError, .missingText)
        }
    }

    func testCopyImageThrowsWhenImagePathIsMissing() {
        let item = ClipboardItem(
            id: UUID(),
            kind: .image,
            copiedAt: Date(),
            lastUsedAt: nil,
            isFavorite: false,
            text: nil,
            imagePath: nil,
            thumbnailPath: nil
        )
        let service = PasteService(pasteboard: FakePasteboardWriter(), pasteEventSender: FakePasteEventSender())

        XCTAssertThrowsError(try service.copy(item)) { error in
            XCTAssertEqual(error as? PasteServiceError, .missingImagePath)
        }
    }

    func testCopyImageThrowsWhenImagePathIsUnreadable() {
        let service = PasteService(pasteboard: FakePasteboardWriter(), pasteEventSender: FakePasteEventSender())
        let item = ClipboardItem.image(
            imagePath: "/definitely/missing/file.png",
            thumbnailPath: "/tmp/thumb.png"
        )

        XCTAssertThrowsError(try service.copy(item)) { error in
            XCTAssertEqual(error as? PasteServiceError, .unreadableImage("/definitely/missing/file.png"))
        }
    }
}

private final class FakePasteboardWriter: PasteboardWriting {
    private let recorder: CallRecorder?
    private(set) var writtenText: String?
    private(set) var writtenImagePayload: ClipboardImagePayload?

    init(recorder: CallRecorder? = nil) {
        self.recorder = recorder
    }

    func writeText(_ text: String) throws {
        writtenText = text
        recorder?.record("writeText:\(text)")
    }

    func writeImage(_ payload: ClipboardImagePayload) throws {
        writtenImagePayload = payload
        recorder?.record("writeImage")
    }
}

private final class FakePasteEventSender: PasteEventSending {
    private let recorder: CallRecorder?
    private let error: Error?

    init(recorder: CallRecorder? = nil, error: Error? = nil) {
        self.recorder = recorder
        self.error = error
    }

    func sendPasteCommand() throws {
        if let error {
            throw error
        }
        recorder?.record("sendPasteCommand")
    }
}

private final class CallRecorder {
    private(set) var calls: [String] = []

    func record(_ call: String) {
        calls.append(call)
    }
}

private enum TestError: Error, Equatable {
    case pasteFailed
}

private func makeTestImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 2, height: 2))
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: 2, height: 2).fill()
    image.unlockFocus()
    return image
}

private extension NSImage {
    var pngData: Data? {
        guard
            let tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffRepresentation)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    var jpegData: Data? {
        guard
            let tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffRepresentation)
        else {
            return nil
        }
        return bitmap.representation(using: .jpeg, properties: [:])
    }
}
