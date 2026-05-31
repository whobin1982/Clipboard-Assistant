import AppKit
import Foundation
import XCTest
@testable import ClipboardHistory

/// 验证复制、图片归档恢复、系统剪贴板读写和自动粘贴事件发送。
final class PasteServiceTests: XCTestCase {
    /// 文本记录应写入文本剪贴板，不应写入图片归档。
    func testCopyTextWritesTextToPasteboard() throws {
        let pasteboard = FakePasteboardWriter()
        let service = PasteService(pasteboard: pasteboard, pasteEventSender: FakePasteEventSender())

        try service.copy(.text("Saved text"))

        XCTAssertEqual(pasteboard.writtenText, "Saved text")
        XCTAssertNil(pasteboard.writtenImageArchive)
    }

    /// 写入文本时应带上内部 marker，避免监听器重复记录。
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

    /// 旧版单图片文件记录应被包装成单 item 图片归档。
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

    /// 新版图片归档应按原 manifest 恢复。
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

    /// 写入图片时也应带上内部 marker。
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

    /// 写回图片归档时应保留多个 item 和同一 item 的多种图片格式。
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

    /// 读取根 pasteboard 上的 PNG 图片数据。
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

    /// 读取多个 pasteboard item 时应保留图片类型，并忽略非图片类型。
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

    /// Finder 复制图片文件时应读取文件真实内容。
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

    /// 文件引用同时带有系统图标时，应读取图片文件内容而不是图标。
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

    /// 非图片文件即使带有图标图片，也不应被当成图片历史。
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

    /// PDF 文件不属于图片复制范围，应被忽略。
    func testSystemPasteboardReaderIgnoresPDFFileURL() throws {
        let pdfURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try makeTestPDFData().write(to: pdfURL)
        defer { try? FileManager.default.removeItem(at: pdfURL) }
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name(UUID().uuidString)))
        pasteboard.clearContents()
        pasteboard.writeObjects([pdfURL as NSURL])
        let reader = SystemPasteboardReader(pasteboard: pasteboard)

        XCTAssertNil(reader.readImageArchive())
    }

    /// copyAndPaste 应先复制再发送粘贴快捷键。
    func testCopyAndPasteCopiesThenSendsPasteCommand() throws {
        let recorder = CallRecorder()
        let pasteboard = FakePasteboardWriter(recorder: recorder)
        let sender = FakePasteEventSender(recorder: recorder)
        let service = PasteService(pasteboard: pasteboard, pasteEventSender: sender)

        try service.copyAndPaste(.text("Saved text"))

        XCTAssertEqual(recorder.calls, ["writeText:Saved text", "sendPasteCommand"])
    }

    /// 自动粘贴失败时，复制动作已经完成，错误继续向上抛出。
    func testCopyAndPasteThrowsWhenPasteSenderFailsAfterCopying() {
        let pasteboard = FakePasteboardWriter()
        let sender = FakePasteEventSender(error: TestError.pasteFailed)
        let service = PasteService(pasteboard: pasteboard, pasteEventSender: sender)

        XCTAssertThrowsError(try service.copyAndPaste(.text("Saved text"))) { error in
            XCTAssertEqual(error as? TestError, .pasteFailed)
        }
        XCTAssertEqual(pasteboard.writtenText, "Saved text")
    }

    /// 文本记录缺少文本内容时应抛出明确错误。
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

    /// 图片记录缺少图片路径时应抛出明确错误。
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

    /// 图片路径不可读时应抛出带路径的错误。
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

/// 测试用剪贴板写入器，记录文本或图片归档写入结果。
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

/// 测试用粘贴事件发送器，可记录调用顺序并模拟失败。
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

/// 简单调用记录器，用于验证复制和粘贴事件的先后顺序。
private final class CallRecorder {
    private(set) var calls: [String] = []

    func record(_ call: String) {
        calls.append(call)
    }
}

/// 粘贴服务测试中的模拟错误。
private enum TestError: Error, Equatable {
    case pasteFailed
}

/// 构造 PDF 测试数据时可能出现的错误。
private enum TestDataError: Error {
    case pdfCreationFailed
}

/// 创建纯色测试图片。
private func makeTestImage(size: NSSize = NSSize(width: 2, height: 2)) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    return image
}

/// 创建最小 PDF 数据，用于验证 PDF 文件不会被当成图片记录。
private func makeTestPDFData() throws -> Data {
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
        throw TestDataError.pdfCreationFailed
    }
    var mediaBox = CGRect(x: 0, y: 0, width: 24, height: 24)
    guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        throw TestDataError.pdfCreationFailed
    }
    context.beginPDFPage(nil)
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(mediaBox)
    context.endPDFPage()
    context.closePDF()
    return data as Data
}

/// 为测试图片生成 PNG/JPEG 数据。
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
