import AppKit
import Foundation

protocol PasteboardReading {
    var changeCount: Int { get }
    func readString() -> String?
    func readImage() -> NSImage?
    func wasWrittenByClipboardHistory() -> Bool
}

protocol ImageStoring {
    func save(_ image: NSImage, id: UUID) throws -> (imagePath: String, thumbnailPath: String)
}

extension ImageStorage: ImageStoring {}

extension Notification.Name {
    static let clipboardHistoryDidChange = Notification.Name("ClipboardHistoryDidChange")
}

final class SystemPasteboardReader: PasteboardReading {
    private static let directImageTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
        NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("public.heic"),
        NSPasteboard.PasteboardType("public.heif"),
        NSPasteboard.PasteboardType("com.compuserve.gif")
    ]

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    func readString() -> String? {
        pasteboard.string(forType: .string)
    }

    func readImage() -> NSImage? {
        for type in Self.directImageTypes {
            guard
                let imageData = pasteboard.data(forType: type),
                let image = NSImage(data: imageData)
            else {
                continue
            }
            return image
        }
        return nil
    }

    func wasWrittenByClipboardHistory() -> Bool {
        pasteboard.string(forType: ClipboardPasteboardMarker.type) == ClipboardPasteboardMarker.value
    }
}

final class ClipboardMonitor {
    private let pasteboard: PasteboardReading
    private let store: ClipboardStore
    private let imageStorage: ImageStoring
    private let isRecordingPaused: () -> Bool
    private let interval: TimeInterval
    private var lastProcessedChangeCount: Int
    private var timer: Timer?
    private(set) var lastError: Error?

    init(
        pasteboard: PasteboardReading = SystemPasteboardReader(),
        store: ClipboardStore,
        imageStorage: ImageStoring,
        interval: TimeInterval = 0.5,
        isRecordingPaused: @escaping () -> Bool
    ) {
        self.pasteboard = pasteboard
        self.store = store
        self.imageStorage = imageStorage
        self.interval = interval
        self.isRecordingPaused = isRecordingPaused
        lastProcessedChangeCount = pasteboard.changeCount
    }

    deinit {
        stop()
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollOnce()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func pollOnce() {
        let currentChangeCount = pasteboard.changeCount

        guard !isRecordingPaused() else {
            markChangeHandled(currentChangeCount)
            return
        }

        guard currentChangeCount != lastProcessedChangeCount else { return }

        if pasteboard.wasWrittenByClipboardHistory() {
            markChangeHandled(currentChangeCount)
            return
        }

        if let image = pasteboard.readImage() {
            recordImage(image, changeCount: currentChangeCount)
            return
        }

        if let string = pasteboard.readString(),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                try store.insert(.text(string))
                postHistoryChanged()
                markChangeHandled(currentChangeCount)
            } catch {
                lastError = error
            }
            return
        }

        markChangeHandled(currentChangeCount)
    }

    private func markChangeHandled(_ changeCount: Int) {
        lastProcessedChangeCount = changeCount
        lastError = nil
    }

    private func postHistoryChanged() {
        NotificationCenter.default.post(name: .clipboardHistoryDidChange, object: self)
    }

    private func recordImage(_ image: NSImage, changeCount: Int) {
        let id = UUID()
        let paths: (imagePath: String, thumbnailPath: String)
        do {
            paths = try imageStorage.save(image, id: id)
        } catch {
            // Image encoding/storage failures are intentionally skipped so later
            // pasteboard changes can still be recorded.
            markChangeHandled(changeCount)
            lastError = error
            return
        }
        let item = ClipboardItem(
            id: id,
            kind: .image,
            copiedAt: Date(),
            lastUsedAt: nil,
            isFavorite: false,
            text: nil,
            imagePath: paths.imagePath,
            thumbnailPath: paths.thumbnailPath
        )
        do {
            try store.insert(item)
            postHistoryChanged()
            markChangeHandled(changeCount)
        } catch {
            lastError = error
        }
    }
}
