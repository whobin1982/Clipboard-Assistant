import AppKit
import Foundation

protocol PasteboardReading {
    var changeCount: Int { get }
    func readString() -> String?
    func readImageArchive() -> ClipboardImageArchive?
    func hasFileReference() -> Bool
    func wasWrittenByClipboardHistory() -> Bool
}

protocol ImageStoring {
    func save(_ archive: ClipboardImageArchive, id: UUID) throws -> (imagePath: String, thumbnailPath: String)
}

extension ImageStorage: ImageStoring {}

extension Notification.Name {
    static let clipboardHistoryDidChange = Notification.Name("ClipboardHistoryDidChange")
}

struct ClipboardImagePayload: Equatable, Codable {
    let data: Data
    let pasteboardType: NSPasteboard.PasteboardType

    private enum CodingKeys: String, CodingKey {
        case data
        case pasteboardType
    }

    var image: NSImage? {
        NSImage(data: data)
    }

    var fileExtension: String {
        Self.fileExtension(for: pasteboardType)
    }

    static func pasteboardType(forFileExtension fileExtension: String) -> NSPasteboard.PasteboardType {
        switch fileExtension.lowercased() {
        case "png":
            return .png
        case "tif", "tiff":
            return .tiff
        case "jpg", "jpeg":
            return NSPasteboard.PasteboardType("public.jpeg")
        case "heic":
            return NSPasteboard.PasteboardType("public.heic")
        case "heif":
            return NSPasteboard.PasteboardType("public.heif")
        case "gif":
            return NSPasteboard.PasteboardType("com.compuserve.gif")
        default:
            return .png
        }
    }

    init(data: Data, pasteboardType: NSPasteboard.PasteboardType) {
        self.data = data
        self.pasteboardType = pasteboardType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode(Data.self, forKey: .data)
        let pasteboardTypeRawValue = try container.decode(String.self, forKey: .pasteboardType)
        pasteboardType = NSPasteboard.PasteboardType(pasteboardTypeRawValue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        try container.encode(pasteboardType.rawValue, forKey: .pasteboardType)
    }

    private static func fileExtension(for pasteboardType: NSPasteboard.PasteboardType) -> String {
        switch pasteboardType {
        case .png:
            return "png"
        case .tiff:
            return "tiff"
        case NSPasteboard.PasteboardType("public.jpeg"):
            return "jpg"
        case NSPasteboard.PasteboardType("public.heic"):
            return "heic"
        case NSPasteboard.PasteboardType("public.heif"):
            return "heif"
        case NSPasteboard.PasteboardType("com.compuserve.gif"):
            return "gif"
        default:
            return "png"
        }
    }
}

struct ClipboardImageArchive: Equatable, Codable {
    static let fileExtension = "clipboardimage"

    let items: [[ClipboardImagePayload]]

    var firstImage: NSImage? {
        firstPayload?.image
    }

    private var firstPayload: ClipboardImagePayload? {
        for item in items {
            if let payload = item.first {
                return payload
            }
        }
        return nil
    }

    init(items: [[ClipboardImagePayload]]) {
        self.items = items
    }

    static func single(_ payload: ClipboardImagePayload) -> ClipboardImageArchive {
        ClipboardImageArchive(items: [[payload]])
    }

    static func load(from url: URL) throws -> ClipboardImageArchive {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ClipboardImageArchive.self, from: data)
    }

    func write(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }
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
    private static let directImageTypeSet = Set(directImageTypes)
    private static let knownFileReferenceTypes: Set<NSPasteboard.PasteboardType> = [
        .fileURL,
        .fileContents,
        NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
        NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type")
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

    func readImageArchive() -> ClipboardImageArchive? {
        if hasFileReference() {
            return readImageFileArchive()
        }

        let imageItems = pasteboard.pasteboardItems?.compactMap { item -> [ClipboardImagePayload]? in
            let payloads = item.types.compactMap { type -> ClipboardImagePayload? in
                guard
                    Self.directImageTypeSet.contains(type),
                    let imageData = item.data(forType: type),
                    NSImage(data: imageData) != nil
                else {
                    return nil
                }
                return ClipboardImagePayload(data: imageData, pasteboardType: type)
            }
            return payloads.isEmpty ? nil : payloads
        }

        if let imageItems, !imageItems.isEmpty {
            return ClipboardImageArchive(items: imageItems)
        }

        return readSingleImagePayload().map(ClipboardImageArchive.single)
    }

    func hasFileReference() -> Bool {
        pasteboard.pasteboardItems?.contains { item in
            item.types.contains(where: Self.isFileReferenceType)
        } ?? false
    }

    func wasWrittenByClipboardHistory() -> Bool {
        pasteboard.string(forType: ClipboardPasteboardMarker.type) == ClipboardPasteboardMarker.value
    }

    private static func isFileReferenceType(_ type: NSPasteboard.PasteboardType) -> Bool {
        if knownFileReferenceTypes.contains(type) {
            return true
        }

        let rawValue = type.rawValue.lowercased()
        return rawValue == "nsfilenamespboardtype"
            || rawValue.contains("file-url")
            || rawValue.contains("promised-file")
    }

    private func readSingleImagePayload() -> ClipboardImagePayload? {
        for type in Self.directImageTypes {
            guard
                let imageData = pasteboard.data(forType: type),
                NSImage(data: imageData) != nil
            else {
                continue
            }
            return ClipboardImagePayload(data: imageData, pasteboardType: type)
        }
        return nil
    }

    private func readImageFileArchive() -> ClipboardImageArchive? {
        let payloadItems = fileURLsFromPasteboard().compactMap { url -> [ClipboardImagePayload]? in
            guard let payload = imagePayload(fromFileURL: url) else {
                return nil
            }
            return [payload]
        }

        return payloadItems.isEmpty ? nil : ClipboardImageArchive(items: payloadItems)
    }

    private func fileURLsFromPasteboard() -> [URL] {
        var urls: [URL] = []

        let objectURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )?.compactMap { object -> URL? in
            if let url = object as? URL {
                return url
            }
            if let url = object as? NSURL {
                return url as URL
            }
            return nil
        } ?? []
        urls.append(contentsOf: objectURLs)

        pasteboard.pasteboardItems?.forEach { item in
            if let url = fileURL(from: item.string(forType: .fileURL)) {
                urls.append(url)
            }

            let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
            if item.types.contains(filenamesType),
               let paths = item.propertyList(forType: filenamesType) as? [String] {
                urls.append(contentsOf: paths.map(URL.init(fileURLWithPath:)))
            }
        }

        var seen: Set<String> = []
        return urls.filter { url in
            guard url.isFileURL else { return false }
            return seen.insert(url.standardizedFileURL.path).inserted
        }
    }

    private func fileURL(from value: String?) -> URL? {
        guard let value, !value.isEmpty else {
            return nil
        }

        if let url = URL(string: value), url.isFileURL {
            return url
        }

        return URL(fileURLWithPath: value)
    }

    private func imagePayload(fromFileURL url: URL) -> ClipboardImagePayload? {
        guard
            let data = try? Data(contentsOf: url),
            !data.isEmpty
        else {
            return nil
        }

        let payload = ClipboardImagePayload(
            data: data,
            pasteboardType: ClipboardImagePayload.pasteboardType(forFileExtension: url.pathExtension)
        )
        return payload.image == nil ? nil : payload
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

        if let imageArchive = pasteboard.readImageArchive() {
            recordImage(imageArchive, changeCount: currentChangeCount)
            return
        }

        if pasteboard.hasFileReference() {
            markChangeHandled(currentChangeCount)
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

    private func recordImage(_ imageArchive: ClipboardImageArchive, changeCount: Int) {
        let id = UUID()
        let paths: (imagePath: String, thumbnailPath: String)
        do {
            paths = try imageStorage.save(imageArchive, id: id)
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
