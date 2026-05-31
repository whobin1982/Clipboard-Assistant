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
        XCTAssertNil(pasteboard.writtenImageArchive)
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

    func testCopyImageWritesLegacyImageFileAsSingleItemArchive() throws {
        let pasteboard = FakePasteboardWriter()
        let service = PasteService(pasteboard: pasteboard, pasteEventSender: FakePasteEventSender())
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        let imageData = try XCTUnwrap(makeTestImage().pngData)
        try imageData.write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        try service.copy(.image(imagePath: imageURL.path, thumbnailPath: "/tmp/thumb.png"))

        let archive = try XCTUnwrap(pasteboard.writtenImageArchive)
        XCTAssertEqual(archive.items.count, 1)
        XCTAssertEqual(archive.items[0].count, 1)
        XCTAssertEqual(archive.items[0][0].data, imageData)
        XCTAssertEqual(archive.items[0][0].pasteboardType, .png)
        XCTAssertNil(pasteboard.writtenText)
    }

    func testCopyImageRestoresArchiveManifest() throws {
        let pasteboard = FakePasteboardWriter()
        let service = PasteService(pasteboard: pasteboard, pasteEventSender: FakePasteEventSender())
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ClipboardImageArchive.fileExtension)
        let imageData = try XCTUnwrap(makeTestImage().pngData)
        let archive = ClipboardImageArchive(items: [[
            ClipboardImagePayload(data: imageData, pasteboardType: .png)
        ]])
        try archive.write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        try service.copy(.image(imagePath: imageURL.path, thumbnailPath: "/tmp/thumb.png"))

        XCTAssertEqual(pasteboard.writtenImageArchive, archive)
        XCTAssertNil(pasteboard.writtenText)
    }

    func testSystemPasteboardWriterMarksImageAsClipboardHistoryCopy() throws {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name(UUID().uuidString)))
        let writer = SystemPasteboardWriter(pasteboard: pasteboard)

        let imageData = try XCTUnwrap(makeTestImage().pngData)
        try writer.writeImageArchive(ClipboardImageArchive(items: [[
            ClipboardImagePayload(data: imageData, pasteboardType: .png)
        ]]))

        XCTAssertEqual(
            pasteboard.string(forType: ClipboardPasteboardMarker.type),
            ClipboardPasteboardMarker.value
        )
    }

    func testSystemPasteboardWriterRestoresArchiveItemsWithAllImageTypes() throws {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name(UUID().uuidString)))
        let writer = SystemPasteboardWriter(pasteboard: pasteboard)
        let pngData = try XCTUnwrap(makeTestImage().pngData)
        let tiffData = try XCTUnwrap(makeTestImage().tiffRepresentation)
        let jpegData = try XCTUnwrap(makeTestImage().jpegData)
        let jpegType = NSPasteboard.PasteboardType("public.jpeg")
        let archive = ClipboardImageArchive(items: [
            [
                ClipboardImagePayload(data: pngData, pasteboardType: .png),
                ClipboardImagePayload(data: tiffData, pasteboardType: .tiff)
            ],
            [
                ClipboardImagePayload(data: jpegData, pasteboardType: jpegType)
            ]
        ])

        try writer.writeImageArchive(archive)

        let items = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].data(forType: .png), pngData)
        XCTAssertEqual(items[0].data(forType: .tiff), tiffData)
        XCTAssertEqual(items[1].data(forType: jpegType), jpegData)
        XCTAssertEqual(
            pasteboard.string(forType: ClipboardPasteboardMarker.type),
            ClipboardPasteboardMarker.value
        )
    }

    func testSystemPasteboardReaderReadsPngImageArchive() throws {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name(UUID().uuidString)))
        let imageData = try XCTUnwrap(makeTestImage().pngData)
        pasteboard.declareTypes([.png], owner: nil)
        pasteboard.setData(imageData, forType: .png)
        let reader = SystemPasteboardReader(pasteboard: pasteboard)
        let archive = try XCTUnwrap(reader.readImageArchive())

        XCTAssertEqual(archive.items.count, 1)
        XCTAssertEqual(archive.items[0].count, 1)
        XCTAssertEqual(archive.items[0][0].data, imageData)
        XCTAssertEqual(archive.items[0][0].pasteboardType, .png)
    }

    func testSystemPasteboardReaderPreservesImageItemsAndIgnoresNonImageTypes() throws {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name(UUID().uuidString)))
        let pngData = try XCTUnwrap(makeTestImage().pngData)
        let tiffData = try XCTUnwrap(makeTestImage().tiffRepresentation)
        let jpegData = try XCTUnwrap(makeTestImage().jpegData)
        let jpegType = NSPasteboard.PasteboardType("public.jpeg")
        let firstItem = NSPasteboardItem()
        firstItem.setString("caption", forType: .string)
        firstItem.setData(pngData, forType: .png)
        firstItem.setData(tiffData, forType: .tiff)
        let secondItem = NSPasteboardItem()
        secondItem.setData(jpegData, forType: jpegType)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([firstItem, secondItem]))
        let reader = SystemPasteboardReader(pasteboard: pasteboard)

        let archive = try XCTUnwrap(reader.readImageArchive())

        XCTAssertEqual(archive.items.count, 2)
        XCTAssertEqual(Set(archive.items[0].map(\.pasteboardType)), Set([.png, .tiff]))
        XCTAssertEqual(Set(archive.items[0].map(\.data)), Set([pngData, tiffData]))
        XCTAssertEqual(archive.items[1], [ClipboardImagePayload(data: jpegData, pasteboardType: jpegType)])
    }

    func testSystemPasteboardReaderReadsImageFileURLContents() throws {
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        let imageData = try XCTUnwrap(makeTestImage().pngData)
        try imageData.write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name(UUID().uuidString)))
        pasteboard.clearContents()
        pasteboard.writeObjects([imageURL as NSURL])
        let reader = SystemPasteboardReader(pasteboard: pasteboard)

        let archive = try XCTUnwrap(reader.readImageArchive())
        XCTAssertEqual(archive.items, [[ClipboardImagePayload(data: imageData, pasteboardType: .png)]])
    }

    func testSystemPasteboardReaderReadsImageFileURLContentsInsteadOfFileIcon() throws {
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        let imageData = try XCTUnwrap(makeTestImage().pngData)
        try imageData.write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }
        let iconData = try XCTUnwrap(makeTestImage(size: NSSize(width: 1024, height: 1024)).tiffRepresentation)
        let fileItem = NSPasteboardItem()
        fileItem.setString(imageURL.absoluteString, forType: .fileURL)
        let iconItem = NSPasteboardItem()
        iconItem.setData(iconData, forType: .tiff)
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name(UUID().uuidString)))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([fileItem, iconItem]))
        let reader = SystemPasteboardReader(pasteboard: pasteboard)

        let archive = try XCTUnwrap(reader.readImageArchive())
        XCTAssertEqual(archive.items, [[ClipboardImagePayload(data: imageData, pasteboardType: .png)]])
    }

    func testSystemPasteboardReaderIgnoresNonImageFileURLEvenWhenItAlsoContainsImageIcon() throws {
        let textURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        try Data("not an image".utf8).write(to: textURL)
        defer { try? FileManager.default.removeItem(at: textURL) }
        let iconData = try XCTUnwrap(makeTestImage(size: NSSize(width: 1024, height: 1024)).tiffRepresentation)
        let fileItem = NSPasteboardItem()
        fileItem.setString(textURL.absoluteString, forType: .fileURL)
        let iconItem = NSPasteboardItem()
        iconItem.setData(iconData, forType: .tiff)
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name(UUID().uuidString)))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([fileItem, iconItem]))
        let reader = SystemPasteboardReader(pasteboard: pasteboard)

        XCTAssertNil(reader.readImageArchive())
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
    private(set) var writtenImageArchive: ClipboardImageArchive?

    init(recorder: CallRecorder? = nil) {
        self.recorder = recorder
    }

    func writeText(_ text: String) throws {
        writtenText = text
        recorder?.record("writeText:\(text)")
    }

    func writeImageArchive(_ archive: ClipboardImageArchive) throws {
        writtenImageArchive = archive
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

private func makeTestImage(size: NSSize = NSSize(width: 2, height: 2)) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(origin: .zero, size: size).fill()
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
