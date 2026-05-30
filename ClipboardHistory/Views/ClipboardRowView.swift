import AppKit
import SwiftUI

struct ClipboardRowView: View {
    let item: ClipboardItem
    let onFavorite: () -> Void
    let onDelete: () -> Void
    let onPaste: () -> Void
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            preview
                .frame(width: 42, height: 42)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.callout)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Favorite")
                    }
                }

                Text(item.copiedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Button(action: onPaste) {
                    Image(systemName: "arrow.up.doc.on.clipboard")
                }
                .help("Paste")

                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy")

                Button(action: onFavorite) {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                }
                .help(item.isFavorite ? "Remove Favorite" : "Favorite")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .help("Delete")
            }
            .buttonStyle(.borderless)
            .imageScale(.medium)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .text:
            Image(systemName: "text.alignleft")
                .font(.title3)
                .foregroundStyle(.secondary)
        case .image:
            if let image = thumbnailImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var title: String {
        switch item.kind {
        case .text:
            let value = item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? "Empty Text" : value
        case .image:
            return "Image"
        }
    }

    private var thumbnailImage: NSImage? {
        guard let thumbnailPath = item.thumbnailPath else { return nil }
        return NSImage(contentsOfFile: thumbnailPath)
    }
}
