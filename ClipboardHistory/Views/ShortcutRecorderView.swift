import AppKit
import SwiftUI

struct ShortcutRecorderView: View {
    let shortcut: ShortcutDefinition
    let onRecord: (ShortcutDefinition) -> Void

    @State private var isRecording = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ShortcutCaptureView(
                    isRecording: $isRecording,
                    onRecord: { recordedShortcut in
                        message = nil
                        onRecord(recordedShortcut)
                    },
                    onCancel: {
                        message = nil
                        isRecording = false
                    },
                    onReject: {
                        message = "请同时按下一个修饰键和一个字母或数字键。"
                    }
                )
                .frame(width: 168, height: 34)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1)
                }
                .overlay {
                    Text(isRecording ? "请按快捷键" : shortcut.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    message = nil
                    isRecording = true
                }

                Button(isRecording ? "取消" : "录制") {
                    message = nil
                    isRecording.toggle()
                }
            }

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onRecord: (ShortcutDefinition) -> Void
    let onCancel: () -> Void
    let onReject: () -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onRecord = { shortcut in
            isRecording = false
            onRecord(shortcut)
        }
        view.onCancel = onCancel
        view.onReject = onReject
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.isRecording = isRecording
        nsView.onRecord = { shortcut in
            isRecording = false
            onRecord(shortcut)
        }
        nsView.onCancel = onCancel
        nsView.onReject = onReject

        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

private final class ShortcutCaptureNSView: NSView {
    var isRecording = false
    var onRecord: ((ShortcutDefinition) -> Void)?
    var onCancel: (() -> Void)?
    var onReject: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            onCancel?()
            return
        }

        guard let shortcut = ShortcutDefinition(event: event) else {
            onReject?()
            return
        }

        onRecord?(shortcut)
    }
}

private extension ShortcutDefinition {
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let requiresCommand = flags.contains(.command)
        let requiresOption = flags.contains(.option)
        let requiresControl = flags.contains(.control)
        let requiresShift = flags.contains(.shift)

        guard requiresCommand || requiresOption || requiresControl || requiresShift else {
            return nil
        }
        guard let rawKey = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines),
              let firstCharacter = rawKey.first,
              !rawKey.isEmpty
        else {
            return nil
        }

        let keyName = String(firstCharacter).uppercased()
        let displayName = ShortcutDefinition.displayName(
            keyName: keyName,
            requiresCommand: requiresCommand,
            requiresOption: requiresOption,
            requiresControl: requiresControl,
            requiresShift: requiresShift
        )

        self = .custom(
            displayName: displayName,
            keyCode: event.keyCode,
            requiresCommand: requiresCommand,
            requiresOption: requiresOption,
            requiresControl: requiresControl,
            requiresShift: requiresShift
        )
    }

    static func displayName(
        keyName: String,
        requiresCommand: Bool,
        requiresOption: Bool,
        requiresControl: Bool,
        requiresShift: Bool
    ) -> String {
        var parts: [String] = []
        if requiresControl {
            parts.append("⌃")
        }
        if requiresOption {
            parts.append("⌥")
        }
        if requiresShift {
            parts.append("⇧")
        }
        if requiresCommand {
            parts.append("⌘")
        }
        parts.append(keyName)
        return parts.joined(separator: " + ")
    }
}
