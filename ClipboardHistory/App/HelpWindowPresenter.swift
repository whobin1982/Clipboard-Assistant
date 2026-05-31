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
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
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
            .applicationVersion: "\(version) (\(build))",
            .version: "版本 \(version)",
            .credits: credits
        ])
    }
}

private struct HelpDocumentView: View {
    let content: String

    var body: some View {
        ScrollView {
            Text(markdownContent)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 28, leading: 30, bottom: 32, trailing: 30))
        }
        .frame(minWidth: 460, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var markdownContent: AttributedString {
        (try? AttributedString(markdown: content)) ?? AttributedString(content)
    }
}
