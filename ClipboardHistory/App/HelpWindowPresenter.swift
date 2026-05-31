import AppKit
import SwiftUI

@MainActor
final class HelpWindowPresenter {
    static let shared = HelpWindowPresenter()

    private var window: NSWindow?

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

@MainActor
enum AboutPanelPresenter {
    static func show() {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0"
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

private struct HelpSection: Identifiable {
    let title: String
    let items: [HelpItem]

    var id: String { title }
}

private struct HelpItem: Identifiable {
    let title: String?
    let detail: String

    var id: String { "\(title ?? "")-\(detail)" }

    init(title: String?, detail: String) {
        self.title = title
        self.detail = detail
    }

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
