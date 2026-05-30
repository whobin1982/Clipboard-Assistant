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
            Section("History") {
                Stepper(value: retentionDays, in: 1...365) {
                    HStack {
                        Text("Retention")
                        Spacer()
                        Text("\(viewModel.retentionDays) days")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("Storage Used")
                    Spacer()
                    Text(viewModel.storageUsageDescription)
                        .foregroundStyle(.secondary)
                }
            }

            Section("App") {
                Toggle("Launch at Login", isOn: launchAtLogin)

                if let message = viewModel.lastErrorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }

                HStack {
                    Text("Shortcut")
                    Spacer()
                    Text(viewModel.shortcutDisplayName)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Danger Zone") {
                Menu("Clear History") {
                    Button("Clear Non-Favorites") {
                        clearConfirmation = .nonFavorites
                    }

                    Button("Clear All Records", role: .destructive) {
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
        .frame(width: 460, height: 320)
    }

    private var retentionDays: Binding<Int> {
        Binding(
            get: { viewModel.retentionDays },
            set: { viewModel.retentionDays = $0 }
        )
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { viewModel.launchAtLogin },
            set: { viewModel.launchAtLogin = $0 }
        )
    }
}

private enum ClearConfirmation: Hashable, Identifiable {
    case nonFavorites
    case all

    var id: Self { self }

    var title: String {
        switch self {
        case .nonFavorites:
            return "Clear Non-Favorites?"
        case .all:
            return "Clear All Records?"
        }
    }

    var message: String {
        switch self {
        case .nonFavorites:
            return "This removes every clipboard record that is not marked as a favorite."
        case .all:
            return "This removes every clipboard record, including favorites."
        }
    }

    var confirmTitle: String {
        switch self {
        case .nonFavorites:
            return "Clear Non-Favorites"
        case .all:
            return "Clear All Records"
        }
    }
}
