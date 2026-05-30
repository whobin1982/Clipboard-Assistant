import SwiftUI

struct ClipboardPopupView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel

    var onPaste: (ClipboardItem) -> Void
    var onCopy: (ClipboardItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search clipboard history", text: $viewModel.query)
                .textFieldStyle(.roundedBorder)

            if let message = viewModel.lastErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            if viewModel.filteredItems.isEmpty {
                ContentUnavailableView("No Clipboard Records", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                List(viewModel.filteredItems) { item in
                    ClipboardRowView(
                        item: item,
                        onFavorite: { viewModel.toggleFavorite(item) },
                        onDelete: { viewModel.delete(item) },
                        onPaste: { onPaste(item) },
                        onCopy: { onCopy(item) }
                    )
                }
                .listStyle(.plain)
                .frame(minHeight: 180, maxHeight: 360)
            }
        }
        .padding(12)
        .frame(width: 420)
        .onAppear {
            viewModel.reload()
        }
    }
}
