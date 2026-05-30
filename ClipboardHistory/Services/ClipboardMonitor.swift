import AppKit
import Foundation

protocol PasteboardReading {
    var changeCount: Int { get }
    func readString() -> String?
    func readImage() -> NSImage?
}

protocol ImageStoring {
    func save(_ image: NSImage, id: UUID) throws -> (imagePath: String, thumbnailPath: String)
}

extension ImageStorage: ImageStoring {}

final class SystemPasteboardReader: PasteboardReading {
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
        pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage
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
        guard !isRecordingPaused() else { return }

        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastProcessedChangeCount else { return }

        if let string = pasteboard.readString(),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                try store.insert(.text(string))
                markChangeHandled(currentChangeCount)
            } catch {
                lastError = error
            }
            return
        }

        guard let image = pasteboard.readImage() else {
            markChangeHandled(currentChangeCount)
            return
        }

        let id = UUID()
        let paths: (imagePath: String, thumbnailPath: String)
        do {
            paths = try imageStorage.save(image, id: id)
        } catch {
            // Image encoding/storage failures are intentionally skipped so later
            // pasteboard changes can still be recorded.
            markChangeHandled(currentChangeCount)
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
            markChangeHandled(currentChangeCount)
        } catch {
            lastError = error
        }
    }

    private func markChangeHandled(_ changeCount: Int) {
        lastProcessedChangeCount = changeCount
        lastError = nil
    }
}
