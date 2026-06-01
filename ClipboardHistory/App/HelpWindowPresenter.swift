import AppKit
import SwiftUI

/// 负责展示帮助文档窗口，并把打包进应用的 Markdown 转成 SwiftUI 页面。
@MainActor
final class HelpWindowPresenter {
    static let shared = HelpWindowPresenter()

    private var window: NSWindow?

    /// 显示帮助窗口；窗口复用同一个实例，避免重复创建多个帮助页。
    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "剪贴板助手帮助"
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        window?.contentViewController = NSHostingController(
            rootView: HelpDocumentView(content: helpContent())
        )
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// 从应用资源中读取帮助 Markdown；资源缺失时给用户一个可读的兜底提示。
    private func helpContent() -> String {
        guard
            let url = Bundle.main.url(forResource: "HelpREADME", withExtension: "md"),
            let content = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "剪贴板助手帮助暂时不可用。"
        }

        return content
    }
}

/// 使用 macOS 标准关于面板展示版本号和作者信息。
@MainActor
enum AboutPanelPresenter {
    static func show() {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.0"
        let credits = NSAttributedString(
            string: "作者：胡斌\n\n一个运行在 Mac 菜单栏里的剪贴板历史工具。",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "剪贴板助手",
            .applicationVersion: version,
            .version: "版本 \(version)",
            .credits: credits
        ])
    }
}

/// 帮助文档的主视图，负责页头和分区卡片排版。
private struct HelpDocumentView: View {
    private let document: HelpDocument

    init(content: String) {
        document = HelpDocument(markdown: content)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                ForEach(document.sections) { section in
                    HelpSectionCard(section: section)
                }
            }
            .padding(EdgeInsets(top: 28, leading: 30, bottom: 32, trailing: 30))
        }
        .frame(minWidth: 520, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// 顶部品牌区域，展示图标、标题和简介。
    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(nsImage: Self.appIcon)
                .resizable()
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(document.title)
                    .font(.system(size: 24, weight: .semibold))

                Text(document.introduction)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        )
    }

    /// 帮助页优先使用应用图标；找不到时使用系统符号兜底。
    private static var appIcon: NSImage {
        if let image = NSImage(named: "AppIcon") {
            return image
        }

        if
            let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let image = NSImage(contentsOf: url)
        {
            return image
        }

        return NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil) ?? NSImage()
    }
}

/// 单个帮助章节卡片，按标题、图标和条目展示内容。
private struct HelpSectionCard: View {
    let section: HelpSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.teal)
                    .frame(width: 22)

                Text(section.title)
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(section.items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle()
                            .fill(Color(nsColor: .tertiaryLabelColor))
                            .frame(width: 5, height: 5)

                        VStack(alignment: .leading, spacing: 3) {
                            if let title = item.title {
                                Text(title)
                                    .font(.subheadline.weight(.semibold))
                            }

                            Text(item.detail)
                                .font(.subheadline)
                                .foregroundStyle(item.title == nil ? .primary : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .textSelection(.enabled)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
    }

    /// 根据章节标题挑选更直观的系统图标。
    private var iconName: String {
        switch section.title {
        case "快速开始":
            return "bolt.fill"
        case "设置":
            return "gearshape.fill"
        case "图片记录":
            return "photo.on.rectangle.angled"
        case "常见问题":
            return "questionmark.circle.fill"
        default:
            return "circle.grid.2x2.fill"
        }
    }
}

/// 把简单 Markdown 文档解析成帮助页需要的结构化数据。
private struct HelpDocument {
    let title: String
    let introduction: String
    let sections: [HelpSection]

    init(markdown: String) {
        var parsedTitle = "剪贴板助手帮助"
        var introLines: [String] = []
        var parsedSections: [HelpSection] = []
        var currentTitle: String?
        var currentItems: [HelpItem] = []

        // 遇到下一个二级标题或文件结束时，将当前章节写入结果。
        func flushSection() {
            guard let currentTitle else { return }
            parsedSections.append(HelpSection(title: currentTitle, items: currentItems))
            currentItems = []
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("# ") {
                parsedTitle = String(line.dropFirst(2))
            } else if line.hasPrefix("## ") {
                flushSection()
                currentTitle = String(line.dropFirst(3))
            } else if line.hasPrefix("- ") {
                currentItems.append(HelpItem(markdownLine: String(line.dropFirst(2))))
            } else if currentTitle == nil {
                introLines.append(line)
            } else {
                currentItems.append(HelpItem(title: nil, detail: line))
            }
        }

        flushSection()

        title = parsedTitle
        introduction = introLines.joined(separator: "\n")
        sections = parsedSections.isEmpty ? HelpDocument.fallbackSections : parsedSections
    }

    /// 当 Markdown 内容为空或没有章节时，仍然给出最小可用帮助。
    private static let fallbackSections = [
        HelpSection(
            title: "快速开始",
            items: [
                HelpItem(title: "打开历史", detail: "左键点击菜单栏图标。"),
                HelpItem(title: "打开菜单", detail: "右键点击菜单栏图标。")
            ]
        )
    ]
}

/// 帮助文档中的一个二级章节。
private struct HelpSection: Identifiable {
    let title: String
    let items: [HelpItem]

    var id: String { title }
}

/// 帮助章节中的一条说明，支持“标题：详情”和普通文本两种形式。
private struct HelpItem: Identifiable {
    let title: String?
    let detail: String

    var id: String { "\(title ?? "")-\(detail)" }

    init(title: String?, detail: String) {
        self.title = title
        self.detail = detail
    }

    /// 从 Markdown 列表项解析标题和详情，兼容中文冒号和英文冒号。
    init(markdownLine: String) {
        let separators = ["：", ":"]
        for separator in separators {
            if let range = markdownLine.range(of: separator) {
                title = String(markdownLine[..<range.lowerBound])
                detail = String(markdownLine[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                return
            }
        }

        title = nil
        detail = markdownLine
    }
}
