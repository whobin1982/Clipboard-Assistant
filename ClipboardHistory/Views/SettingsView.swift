import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        SettingsFormView(viewModel: environment.settingsViewModel)
    }
}

private struct SettingsFormView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var clearConfirmation: ClearConfirmation?

    var body: some View {
        Form {
            Section("粘贴行为") {
                Picker("点击或回车后", selection: selectionAction) {
                    ForEach(ClipboardSelectionAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("选择后关闭历史窗口", isOn: closeWindowAfterSelection)
                Toggle("按 Esc 关闭历史窗口", isOn: escapeClosesWindow)
            }

            Section("快捷键") {
                Picker("预设快捷键", selection: shortcutID) {
                    ForEach(viewModel.availableShortcuts) { shortcut in
                        Text(shortcut.displayName).tag(shortcut.id)
                    }
                    if viewModel.selectedShortcutID == ShortcutDefinition.customID,
                       let recordedShortcut = viewModel.recordedShortcut {
                        Text(recordedShortcut.displayName).tag(recordedShortcut.id)
                    }
                }
                .pickerStyle(.menu)

                HStack(alignment: .top) {
                    Text("自定义快捷键")
                    Spacer()
                    ShortcutRecorderView(shortcut: viewModel.settings.shortcut) { shortcut in
                        viewModel.applyCustomShortcut(shortcut)
                    }
                }
            }

            Section("启动与历史") {
                Toggle("开机自动启动", isOn: launchAtLogin)

                Picker("保留时间", selection: retentionPolicy) {
                    Text("7 天").tag(RetentionPolicy.days(7))
                    Text("30 天").tag(RetentionPolicy.days(30))
                    Text("90 天").tag(RetentionPolicy.days(90))
                    Text("永久").tag(RetentionPolicy.forever)
                    if shouldShowCustomRetentionOption {
                        Text("\(viewModel.retentionDays) 天").tag(viewModel.retentionPolicy)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text("自定义天数")
                    Spacer()
                    TextField("天数", text: $viewModel.customRetentionDaysText)
                        .frame(width: 78)
                    Button("应用") {
                        viewModel.applyCustomRetentionDays()
                    }
                }

                HStack {
                    Text("已用空间")
                    Spacer()
                    Text(viewModel.storageUsageDescription)
                        .foregroundStyle(.secondary)
                }

                if let message = viewModel.lastErrorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("清理") {
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
        .padding()
        .frame(width: 540, height: 500)
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { viewModel.launchAtLogin },
            set: { viewModel.launchAtLogin = $0 }
        )
    }

    private var selectionAction: Binding<ClipboardSelectionAction> {
        Binding(
            get: { viewModel.selectionAction },
            set: { viewModel.selectionAction = $0 }
        )
    }

    private var closeWindowAfterSelection: Binding<Bool> {
        Binding(
            get: { viewModel.closeWindowAfterSelection },
            set: { viewModel.closeWindowAfterSelection = $0 }
        )
    }

    private var escapeClosesWindow: Binding<Bool> {
        Binding(
            get: { viewModel.escapeClosesWindow },
            set: { viewModel.escapeClosesWindow = $0 }
        )
    }

    private var retentionPolicy: Binding<RetentionPolicy> {
        Binding(
            get: { viewModel.retentionPolicy },
            set: { viewModel.retentionPolicy = $0 }
        )
    }

    private var shortcutID: Binding<String> {
        Binding(
            get: { viewModel.selectedShortcutID },
            set: { viewModel.selectedShortcutID = $0 }
        )
    }

    private var shouldShowCustomRetentionOption: Bool {
        guard case .days(let days) = viewModel.retentionPolicy else {
            return false
        }
        return ![7, 30, 90].contains(days)
    }
}

private enum ClearConfirmation: Hashable, Identifiable {
    case nonFavorites
    case all

    var id: Self { self }

    var title: String {
        switch self {
        case .nonFavorites:
            return "清空非收藏记录？"
        case .all:
            return "清空全部记录？"
        }
    }

    var message: String {
        switch self {
        case .nonFavorites:
            return "这会删除所有没有标记为收藏的剪贴板记录。"
        case .all:
            return "这会删除所有剪贴板记录，包括收藏记录。"
        }
    }

    var confirmTitle: String {
        switch self {
        case .nonFavorites:
            return "清空非收藏记录"
        case .all:
            return "清空全部记录"
        }
    }
}
