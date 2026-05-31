import SwiftUI

/// SwiftUI 设置页入口，从环境对象中取出 SettingsViewModel。
struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        SettingsFormView(viewModel: environment.settingsViewModel)
    }
}

/// 设置表单主体，按功能分为粘贴行为、快捷键、启动与历史、清理四块。
private struct SettingsFormView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var clearConfirmation: ClearConfirmation?

    /// 设置页整体滚动布局。
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsSection("粘贴行为") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsRow("点击或回车后") {
                            Picker("点击或回车后", selection: selectionAction) {
                                ForEach(ClipboardSelectionAction.allCases) { action in
                                    Text(action.title).tag(action)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 280)
                        }

                        Toggle("选择后关闭历史窗口", isOn: closeWindowAfterSelection)
                        Toggle("按 Esc 关闭历史窗口", isOn: escapeClosesWindow)
                    }
                }

                SettingsSection("快捷键") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsRow("预设快捷键") {
                            Picker("预设快捷键", selection: shortcutID) {
                                ForEach(viewModel.availableShortcuts) { shortcut in
                                    Text(shortcut.displayName).tag(shortcut.id)
                                }
                                if viewModel.selectedShortcutID == ShortcutDefinition.customID,
                                   let recordedShortcut = viewModel.recordedShortcut {
                                    Text(recordedShortcut.displayName).tag(recordedShortcut.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 160)
                        }

                        SettingsRow("自定义快捷键") {
                            ShortcutRecorderView(shortcut: viewModel.settings.shortcut) { shortcut in
                                viewModel.applyCustomShortcut(shortcut)
                            }
                        }
                    }
                }

                SettingsSection("启动与历史") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("开机自动启动", isOn: launchAtLogin)

                        SettingsRow("保留时间") {
                            Picker("保留时间", selection: retentionPolicy) {
                                Text("7 天").tag(RetentionPolicy.days(7))
                                Text("30 天").tag(RetentionPolicy.days(30))
                                Text("90 天").tag(RetentionPolicy.days(90))
                                Text("永久").tag(RetentionPolicy.forever)
                                if shouldShowCustomRetentionOption {
                                    Text("\(viewModel.retentionDays) 天").tag(viewModel.retentionPolicy)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 128)
                        }

                        SettingsRow("自定义天数") {
                            HStack(spacing: 8) {
                                TextField("天数", text: $viewModel.customRetentionDaysText)
                                    .frame(width: 72)
                                Button("应用") {
                                    viewModel.applyCustomRetentionDays()
                                }
                            }
                        }

                        SettingsRow("已用空间") {
                            Text(viewModel.storageUsageDescription)
                                .foregroundStyle(.secondary)
                        }

                        if let message = viewModel.lastErrorMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                SettingsSection("清理") {
                    Menu("清空历史") {
                        Button("清空非收藏记录") {
                            clearConfirmation = .nonFavorites
                        }

                        Button("清空全部记录", role: .destructive) {
                            clearConfirmation = .all
                        }
                    }
                }
            }
            .frame(maxWidth: 480, alignment: .leading)
            .padding(24)
        }
        .alert(item: $clearConfirmation) { confirmation in
            Alert(
                title: Text(confirmation.title),
                message: Text(confirmation.message),
                primaryButton: .destructive(Text(confirmation.confirmTitle)) {
                    switch confirmation {
                    case .nonFavorites:
                        viewModel.clearNonFavorites()
                    case .all:
                        viewModel.clearAll()
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .frame(minWidth: 480, minHeight: 520)
    }

    /// 开机启动开关绑定。
    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { viewModel.launchAtLogin },
            set: { viewModel.launchAtLogin = $0 }
        )
    }

    /// 选中历史后的动作绑定。
    private var selectionAction: Binding<ClipboardSelectionAction> {
        Binding(
            get: { viewModel.selectionAction },
            set: { viewModel.selectionAction = $0 }
        )
    }

    /// 选择记录后是否关闭窗口的绑定。
    private var closeWindowAfterSelection: Binding<Bool> {
        Binding(
            get: { viewModel.closeWindowAfterSelection },
            set: { viewModel.closeWindowAfterSelection = $0 }
        )
    }

    /// Esc 关闭窗口的设置绑定。
    private var escapeClosesWindow: Binding<Bool> {
        Binding(
            get: { viewModel.escapeClosesWindow },
            set: { viewModel.escapeClosesWindow = $0 }
        )
    }

    /// 保留策略 picker 绑定。
    private var retentionPolicy: Binding<RetentionPolicy> {
        Binding(
            get: { viewModel.retentionPolicy },
            set: { viewModel.retentionPolicy = $0 }
        )
    }

    /// 快捷键 picker 绑定。
    private var shortcutID: Binding<String> {
        Binding(
            get: { viewModel.selectedShortcutID },
            set: { viewModel.selectedShortcutID = $0 }
        )
    }

    /// 当前保留天数不是预设值时，在菜单里临时显示自定义选项。
    private var shouldShowCustomRetentionOption: Bool {
        guard case .days(let days) = viewModel.retentionPolicy else {
            return false
        }
        return ![7, 30, 90].contains(days)
    }
}

/// 设置页分区组件。
private struct SettingsSection<Content: View>: View {
    private let title: String
    @ViewBuilder private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    /// 分区标题和内容纵向排列。
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content
                .padding(.leading, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 设置页一行“标题 + 控件”的布局组件。
private struct SettingsRow<Content: View>: View {
    private let title: String
    @ViewBuilder private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    /// 左侧固定宽度标签，右侧放具体控件。
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 104, alignment: .leading)

            content

            Spacer(minLength: 0)
        }
    }
}

/// 清空历史操作的确认类型。
private enum ClearConfirmation: Hashable, Identifiable {
    case nonFavorites
    case all

    var id: Self { self }

    /// 确认弹窗标题。
    var title: String {
        switch self {
        case .nonFavorites:
            return "清空非收藏记录？"
        case .all:
            return "清空全部记录？"
        }
    }

    /// 确认弹窗说明。
    var message: String {
        switch self {
        case .nonFavorites:
            return "这会删除所有没有标记为收藏的剪贴板记录。"
        case .all:
            return "这会删除所有剪贴板记录，包括收藏记录。"
        }
    }

    /// 危险按钮文案。
    var confirmTitle: String {
        switch self {
        case .nonFavorites:
            return "清空非收藏记录"
        case .all:
            return "清空全部记录"
        }
    }
}
