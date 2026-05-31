import Foundation

/// 管理历史窗口中键盘上下键选中的记录。
final class ClipboardSelectionController: ObservableObject {
    /// 当前选中的记录 id；为空表示没有选中项。
    @Published private(set) var selectedItemID: UUID?

    /// 向下移动选择；没有选择时选中第一条，已经到底时保持在最后一条。
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

    /// 向上移动选择；没有选择时选中第一条，已经到顶时保持在第一条。
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

    /// 从当前列表中取出选中的完整记录。
    func selectedItem(in items: [ClipboardItem]) -> ClipboardItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    /// 根据 1-9 数字键选择当前可见列表中的对应记录，并返回这条记录给调用方执行粘贴。
    @discardableResult
    func selectNumberShortcut(_ number: Int, in items: [ClipboardItem]) -> ClipboardItem? {
        guard (1...9).contains(number) else { return nil }
        let index = number - 1
        guard items.indices.contains(index) else { return nil }

        let item = items[index]
        selectedItemID = item.id
        return item
    }

    /// 搜索结果刷新后，如果原选中项不在列表里，则清空选择。
    func reconcileSelection(with items: [ClipboardItem]) {
        guard let selectedItemID else { return }
        if !items.contains(where: { $0.id == selectedItemID }) {
            self.selectedItemID = nil
        }
    }
}
