import Foundation

final class ClipboardSelectionController: ObservableObject {
    @Published private(set) var selectedItemID: UUID?

    func moveDown(in items: [ClipboardItem]) {
        guard !items.isEmpty else {
            selectedItemID = nil
            return
        }

        guard
            let selectedItemID,
            let currentIndex = items.firstIndex(where: { $0.id == selectedItemID })
        else {
            selectedItemID = items[0].id
            return
        }

        let nextIndex = min(items.index(after: currentIndex), items.index(before: items.endIndex))
        self.selectedItemID = items[nextIndex].id
    }

    func moveUp(in items: [ClipboardItem]) {
        guard !items.isEmpty else {
            selectedItemID = nil
            return
        }

        guard
            let selectedItemID,
            let currentIndex = items.firstIndex(where: { $0.id == selectedItemID })
        else {
            selectedItemID = items[0].id
            return
        }

        let previousIndex = currentIndex == items.startIndex ? currentIndex : items.index(before: currentIndex)
        self.selectedItemID = items[previousIndex].id
    }

    func selectedItem(in items: [ClipboardItem]) -> ClipboardItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    func reconcileSelection(with items: [ClipboardItem]) {
        guard let selectedItemID else { return }
        if !items.contains(where: { $0.id == selectedItemID }) {
            self.selectedItemID = nil
        }
    }
}
