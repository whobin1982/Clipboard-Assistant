import Foundation
import XCTest
@testable import ClipboardHistory

final class PasteServiceTests: XCTestCase {
    func testCopyTextWritesTextToPasteboard() throws {
        let pasteboard = FakePasteboardWriter()
        let service = PasteService(pasteboard: pasteboard, pasteEventSender: FakePasteEventSender())

        try service.copy(.text("Saved text"))

        XCTAssertEqual(pasteboard.writtenText, "Saved text")
        XCTAssertNil(pasteboard.writtenImagePath)
    }

    func testCopyImageWritesImagePathToPasteboard() throws {
        let pasteboard = FakePasteboardWriter()
        let service = PasteService(pasteboard: pasteboard, pasteEventSender: FakePasteEventSender())
        let item = ClipboardItem.image(imagePath: "/tmp/saved.png", thumbnailPath: "/tmp/thumb.png")

        try service.copy(item)

        XCTAssertEqual(pasteboard.writtenImagePath, "/tmp/saved.png")
        XCTAssertNil(pasteboard.writtenText)
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
}

private final class FakePasteboardWriter: PasteboardWriting {
    private let recorder: CallRecorder?
    private(set) var writtenText: String?
    private(set) var writtenImagePath: String?

    init(recorder: CallRecorder? = nil) {
        self.recorder = recorder
    }

    func writeText(_ text: String) throws {
        writtenText = text
        recorder?.record("writeText:\(text)")
    }

    func writeImage(at path: String) throws {
        writtenImagePath = path
        recorder?.record("writeImage:\(path)")
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
