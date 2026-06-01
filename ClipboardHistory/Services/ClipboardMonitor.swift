import AppKit
import Foundation

/// 系统剪贴板读取抽象，便于用假的 pasteboard 做单元测试。
protocol PasteboardReading {
    var changeCount: Int { get }
    /// 读取文本内容。
    func readString() -> String?
    /// 读取图片内容，并尽量保留原始 pasteboard 类型。
    func readImageArchive() -> ClipboardImageArchive?
    /// 判断剪贴板是否包含文件引用；非图片文件不会被当成文本记录。
    func hasFileReference() -> Bool
    /// 判断这次剪贴板变化是否由本应用写入，避免从历史粘贴时重复新增记录。
    func wasWrittenByClipboardHistory() -> Bool
}

/// 图片存储抽象，ClipboardMonitor 只关心保存结果，不关心磁盘细节。
protocol ImageStoring {
    func save(_ archive: ClipboardImageArchive, id: UUID) throws -> (imagePath: String, thumbnailPath: String)
}

extension ImageStorage: ImageStoring {}

extension Notification.Name {
    /// 剪贴板历史发生变化时发出，历史窗口据此自动刷新列表。
    static let clipboardHistoryDidChange = Notification.Name("ClipboardHistoryDidChange")
}

/// 单个图片 payload，包含原始二进制数据和它在 pasteboard 上对应的类型。
struct ClipboardImagePayload: Equatable, Codable {
    let data: Data
    let pasteboardType: NSPasteboard.PasteboardType

    private enum CodingKeys: String, CodingKey {
        case data
        case pasteboardType
    }

    /// 用于校验 payload 是否真的是可解码图片。
    var image: NSImage? {
        NSImage(data: data)
    }

    /// 将 pasteboard 类型映射成适合落盘或兼容旧记录的扩展名。
    var fileExtension: String {
        Self.fileExtension(for: pasteboardType)
    }

    /// 从 Finder 文件扩展名推断写回 pasteboard 时应使用的图片类型。
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

    /// 自定义解码，因为 NSPasteboard.PasteboardType 本身不是 Codable。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode(Data.self, forKey: .data)
        let pasteboardTypeRawValue = try container.decode(String.self, forKey: .pasteboardType)
        pasteboardType = NSPasteboard.PasteboardType(pasteboardTypeRawValue)
    }

    /// 自定义编码，把 pasteboard type 保存成 rawValue。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        try container.encode(pasteboardType.rawValue, forKey: .pasteboardType)
    }

    /// 将常见图片 pasteboard 类型转成文件扩展名。
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

/// 一次图片剪贴板内容的完整归档。
///
/// 外层数组表示 pasteboard item，内层数组表示同一个 item 的多种图片格式，
/// 这样从 Finder 或图片软件复制时可以尽量原样恢复。
struct ClipboardImageArchive: Equatable, Codable {
    static let fileExtension = "clipboardimage"

    let items: [[ClipboardImagePayload]]

    /// 第一张可解码图片，主要用于生成缩略图。
    var firstImage: NSImage? {
        firstPayload?.image
    }

    /// 查找归档中的第一个 payload。
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

    /// 将单个图片 payload 包装成归档。
    static func single(_ payload: ClipboardImagePayload) -> ClipboardImageArchive {
        ClipboardImageArchive(items: [[payload]])
    }

    /// 从磁盘读取图片归档。
    static func load(from url: URL) throws -> ClipboardImageArchive {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ClipboardImageArchive.self, from: data)
    }

    /// 将图片归档写入磁盘。
    func write(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }
}

/// 从系统剪贴板读取文本、图片和文件引用。
final class SystemPasteboardReader: PasteboardReading {
    /// 直接承载图片二进制数据的 pasteboard 类型。
    private static let directImageTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
        NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("public.heic"),
        NSPasteboard.PasteboardType("public.heif"),
        NSPasteboard.PasteboardType("com.compuserve.gif")
    ]
    private static let directImageTypeSet = Set(directImageTypes)
    /// Finder 中图片文件引用按扩展名映射为图片类型，非图片扩展名会被忽略。
    private static let imageFilePasteboardTypesByExtension: [String: NSPasteboard.PasteboardType] = [
        "png": .png,
        "tif": .tiff,
        "tiff": .tiff,
        "jpg": NSPasteboard.PasteboardType("public.jpeg"),
        "jpeg": NSPasteboard.PasteboardType("public.jpeg"),
        "heic": NSPasteboard.PasteboardType("public.heic"),
        "heif": NSPasteboard.PasteboardType("public.heif"),
        "gif": NSPasteboard.PasteboardType("com.compuserve.gif")
    ]
    /// macOS 里常见的文件引用类型，用来避免把 PDF 等文件图标误记录成图片。
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

    /// NSPasteboard 的 changeCount，ClipboardMonitor 用它判断是否有新内容。
    var changeCount: Int {
        pasteboard.changeCount
    }

    /// 读取普通文本。
    func readString() -> String? {
        pasteboard.string(forType: .string)
    }

    /// 优先读取图片文件内容；没有文件引用时再读取直接图片 payload。
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

    /// 判断剪贴板 item 中是否存在文件引用类型。
    func hasFileReference() -> Bool {
        pasteboard.pasteboardItems?.contains { item in
            item.types.contains(where: Self.isFileReferenceType)
        } ?? false
    }

    /// 本应用写回剪贴板时会写入 marker，监听器看到 marker 就跳过记录。
    func wasWrittenByClipboardHistory() -> Bool {
        pasteboard.string(forType: ClipboardPasteboardMarker.type) == ClipboardPasteboardMarker.value
    }

    /// 文件引用类型在不同应用里命名不完全一致，因此同时做集合和字符串兜底判断。
    private static func isFileReferenceType(_ type: NSPasteboard.PasteboardType) -> Bool {
        if knownFileReferenceTypes.contains(type) {
            return true
        }

        let rawValue = type.rawValue.lowercased()
        return rawValue == "nsfilenamespboardtype"
            || rawValue.contains("file-url")
            || rawValue.contains("promised-file")
    }

    /// 兼容只在 pasteboard 根对象上写入单张图片数据的应用。
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

    /// 读取 Finder 复制的图片文件引用，并把真实文件内容保存为图片 payload。
    private func readImageFileArchive() -> ClipboardImageArchive? {
        let payloadItems = fileURLsFromPasteboard().compactMap { url -> [ClipboardImagePayload]? in
            guard let payload = imagePayload(fromFileURL: url) else {
                return nil
            }
            return [payload]
        }

        return payloadItems.isEmpty ? nil : ClipboardImageArchive(items: payloadItems)
    }

    /// 从多种 pasteboard 表达中提取本地文件 URL，并去重。
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

    /// 兼容 file:// 字符串和普通路径字符串。
    private func fileURL(from value: String?) -> URL? {
        guard let value, !value.isEmpty else {
            return nil
        }

        if let url = URL(string: value), url.isFileURL {
            return url
        }

        return URL(fileURLWithPath: value)
    }

    /// 只接受真实图片文件；PDF、文件夹和其他格式都会被忽略。
    private func imagePayload(fromFileURL url: URL) -> ClipboardImagePayload? {
        guard let pasteboardType = Self.imageFilePasteboardTypesByExtension[url.pathExtension.lowercased()] else {
            return nil
        }

        guard
            let data = try? Data(contentsOf: url),
            !data.isEmpty
        else {
            return nil
        }

        let payload = ClipboardImagePayload(
            data: data,
            pasteboardType: pasteboardType
        )
        return payload.image == nil ? nil : payload
    }
}

/// 轮询系统剪贴板变化，并把可记录的文本或图片写入历史。
final class ClipboardMonitor {
    private let pasteboard: PasteboardReading
    private let store: ClipboardStore
    private let imageStorage: ImageStoring
    private let isRecordingPaused: () -> Bool
    private let interval: TimeInterval
    private var lastProcessedChangeCount: Int
    private var timer: Timer?
    private(set) var lastError: Error?

    /// 创建监听器；默认每 0.5 秒检查一次系统剪贴板。
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

    /// 启动定时轮询。
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollOnce()
        }
    }

    /// 停止定时轮询。
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 执行一次剪贴板检查；测试直接调用这个方法验证各类输入。
    func pollOnce() {
        let currentChangeCount = pasteboard.changeCount

        guard !isRecordingPaused() else {
            // 暂停期间也要推进 changeCount，恢复后不会把暂停时复制的内容补记进去。
            markChangeHandled(currentChangeCount)
            return
        }

        guard currentChangeCount != lastProcessedChangeCount else { return }

        if pasteboard.wasWrittenByClipboardHistory() {
            // 从历史记录复制/粘贴回系统剪贴板时，不应产生一条新的历史记录。
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

    /// 标记本次 changeCount 已处理，并清空旧错误。
    private func markChangeHandled(_ changeCount: Int) {
        lastProcessedChangeCount = changeCount
        lastError = nil
    }

    /// 通知历史窗口刷新列表。
    private func postHistoryChanged() {
        NotificationCenter.default.post(name: .clipboardHistoryDidChange, object: self)
    }

    /// 保存图片归档和缩略图，再写入历史记录。
    private func recordImage(_ imageArchive: ClipboardImageArchive, changeCount: Int) {
        let id = UUID()
        let paths: (imagePath: String, thumbnailPath: String)
        do {
            paths = try imageStorage.save(imageArchive, id: id)
        } catch {
            // 图片编码或落盘失败时跳过本次内容，但要推进 changeCount，避免卡住后续记录。
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
            removePartiallySavedImageFiles(paths)
            lastError = error
        }
    }

    /// 图片已落盘但数据库写入失败时，删除本次生成的文件，避免重试期间不断产生孤儿文件。
    private func removePartiallySavedImageFiles(_ paths: (imagePath: String, thumbnailPath: String)) {
        [paths.imagePath, paths.thumbnailPath].forEach { path in
            guard FileManager.default.fileExists(atPath: path) else { return }
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
