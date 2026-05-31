import AppKit
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

/// 历史窗口键盘快捷键解析器。
enum ClipboardKeyboardShortcut {
    /// 将主键盘和数字小键盘的 1-9 解析成快速选择编号。
    ///
    /// 搜索框为空时，即使当前焦点在搜索框里，也优先让数字键用于快速选择；
    /// 搜索框已有内容时，数字键继续交给搜索框，方便搜索包含数字的内容。
    static func numberShortcut(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        searchQuery: String,
        isTextEditing: Bool
    ) -> Int? {
        let meaningfulModifiers = modifierFlags.intersection([.command, .control, .option, .shift])
        guard meaningfulModifiers.isEmpty else { return nil }

        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isTextEditing || trimmedQuery.isEmpty else { return nil }

        switch keyCode {
        case 18, 83:
            return 1
        case 19, 84:
            return 2
        case 20, 85:
            return 3
        case 21, 86:
            return 4
        case 23, 87:
            return 5
        case 22, 88:
            return 6
        case 26, 89:
            return 7
        case 28, 91:
            return 8
        case 25, 92:
            return 9
        default:
            return nil
        }
    }
}
