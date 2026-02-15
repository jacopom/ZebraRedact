import SwiftUI

/// Settings sheet accessible from the overlay gear icon or ⌘,.
struct SettingsView: View {
    @AppStorage(GhostClipConstants.StorageKeys.onboardingComplete) private var onboardingComplete = true
    @AppStorage(GhostClipConstants.StorageKeys.isPro) private var isPro = false
    @AppStorage(GhostClipConstants.StorageKeys.showMenuBarIcon) private var showMenuBarIcon = true

    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case models = "Models"
        case vault = "Vault"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .models: return "cpu"
            case .vault: return "lock.shield"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 140)
        } detail: {
            ScrollView {
                switch selectedTab {
                case .general:
                    generalSettings
                case .models:
                    ModelManagementView()
                case .vault:
                    VaultView()
                case .about:
                    aboutSection
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 600, minHeight: 450)
    }

    // MARK: - General

    private var generalSettings: some View {
        Form {
            Section("Hotkeys") {
                LabeledContent("Summon GhostClip", value: GhostClipConstants.Hotkeys.ghostTrigger)
                LabeledContent("Apply", value: GhostClipConstants.Hotkeys.applyShortcut)
                LabeledContent("Cancel", value: GhostClipConstants.Hotkeys.cancelShortcut)
            }

            Section("Display") {
                Toggle("Show Menu Bar Icon", isOn: $showMenuBarIcon)
            }

            Section("Onboarding") {
                HStack {
                    Text("Re-show onboarding on next launch")
                    Spacer()
                    Button("Reset") {
                        onboardingComplete = false
                    }
                    .buttonStyle(.bordered)
                }
            }

            Section("Upgrade") {
                if isPro {
                    Label("Pro Unlocked", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(GhostTheme.green)
                } else {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Unlock Pro")
                                .font(.headline)
                            Text("MLX AI detection + Vault + Priority support")
                                .font(.caption)
                                .foregroundStyle(GhostTheme.secondaryText)
                        }
                        Spacer()
                        Button("€19 – Upgrade") {
                            // IAP trigger placeholder
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(GhostTheme.purple)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "theatermasks.fill")
                .font(.system(size: 48))
                .foregroundStyle(GhostTheme.purple)

            Text("GhostClip")
                .font(.title.bold())

            Text("v1.0.0")
                .font(.caption)
                .foregroundStyle(GhostTheme.secondaryText)

            Text("Local PII masking for LLM prompts.\nYour data never leaves your Mac.")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundStyle(GhostTheme.secondaryText)

            Divider()

            Link("Privacy Policy", destination: URL(string: "https://ghostclip.app/privacy")!)
                .font(.caption)
        }
        .padding(40)
    }
}

#Preview {
    SettingsView()
}
