import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        SettingsFormView(viewModel: environment.settingsViewModel)
    }
}

private struct SettingsFormView: View {
    @ObservedObject var viewModel: SettingsViewModel

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
                        viewModel.clearNonFavorites()
                    }

                    Button("Clear All Records", role: .destructive) {
                        viewModel.clearAll()
                    }
                }
            }
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
