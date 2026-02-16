import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            IntelligenceSettingsTab()
                .tabItem {
                    Label("Intelligence", systemImage: "cpu")
                }

            PrivacySettingsTab()
                .tabItem {
                    Label("Privacy", systemImage: "eye.trianglebadge.exclamationmark")
                }

            AboutSettingsTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 560, height: 480)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @AppStorage(GhostClipConstants.StorageKeys.onboardingComplete) private var onboardingComplete = true
    @AppStorage(GhostClipConstants.StorageKeys.showInDock) private var showInDock = true

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle(isOn: $showInDock) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show in Dock")
                        Text("Toggle between Dock icon and menu bar only")
                            .font(.caption)
                            .foregroundStyle(GhostTheme.secondaryText)
                    }
                }
                .onChange(of: showInDock) { _, newValue in
                    NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                }
            }

            Section("Keyboard Shortcuts") {
                LabeledContent("Summon GhostClip", value: "⌥⌘G")
                LabeledContent("Apply & Copy", value: "⌘Return")
                LabeledContent("Dismiss", value: "Escape")
            }

            Section("Onboarding") {
                HStack {
                    Text("Show welcome screen on next launch")
                    Spacer()
                    Button("Reset") {
                        onboardingComplete = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal)
    }
}

// MARK: - Intelligence

struct IntelligenceSettingsTab: View {
    @AppStorage(GhostClipConstants.StorageKeys.detectionEngine) private var detectionEngine = "regex"
    @AppStorage("useSemanticReplacement") private var useSemanticReplacement = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Masking Strategy")
                        .font(.headline)
                    Text("Choose how sensitive data is replaced")
                        .font(.caption)
                        .foregroundStyle(GhostTheme.secondaryText)
                }
                .padding(.vertical, 4)

                Toggle(isOn: $useSemanticReplacement) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Semantic Abstraction")
                        Text(useSemanticReplacement ?
                            "Replaces with realistic fake data (e.g., john@acme.com → alice.smith@example.com)" :
                            "Replaces with opaque tokens (e.g., john@acme.com → [GHOST_A1B2])")
                            .font(.caption)
                            .foregroundStyle(GhostTheme.secondaryText)
                    }
                }
                .toggleStyle(.switch)

                if useSemanticReplacement {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(GhostTheme.purple.opacity(0.6))
                        Text("Semantic mode preserves context, letting LLMs work with abstracted but realistic data.")
                            .font(.caption2)
                            .foregroundStyle(GhostTheme.secondaryText)
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Detection Engine")
                        .font(.headline)
                    Text("Choose how GhostClip identifies sensitive information")
                        .font(.caption)
                        .foregroundStyle(GhostTheme.secondaryText)
                }
                .padding(.vertical, 4)

                Picker("", selection: $detectionEngine) {
                    HStack {
                        Image(systemName: "text.magnifyingglass")
                        VStack(alignment: .leading) {
                            Text("Regex (Fast)")
                            Text("Pattern-based detection, instant").font(.caption2).foregroundStyle(GhostTheme.secondaryText)
                        }
                    }
                    .tag("regex")

                    HStack {
                        Image(systemName: "brain")
                        VStack(alignment: .leading) {
                            Text("NLTagger (Smart)")
                            Text("Apple's semantic detection").font(.caption2).foregroundStyle(GhostTheme.secondaryText)
                        }
                    }
                    .tag("nltagger")

                    HStack {
                        Image(systemName: "cpu.fill")
                        VStack(alignment: .leading) {
                            Text("MLX (Advanced)")
                            Text("Local AI models (coming soon)").font(.caption2).foregroundStyle(GhostTheme.secondaryText)
                        }
                    }
                    .tag("mlx")
                }
                .pickerStyle(.inline)
            }

            Section("Active Engine") {
                HStack {
                    Image(systemName: detectionEngine == "regex" ? "text.magnifyingglass" : detectionEngine == "nltagger" ? "brain" : "cpu.fill")
                        .foregroundStyle(GhostTheme.purple)
                    Text(detectionEngine == "regex" ? "Regex-based (local, instant)" : detectionEngine == "nltagger" ? "NLTagger (semantic)" : "MLX (advanced)")
                    Spacer()
                    Text("Active")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(GhostTheme.green.opacity(0.2))
                        .foregroundStyle(GhostTheme.green)
                        .clipShape(Capsule())
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Local AI Models")
                        .font(.headline)
                    Text("Download and manage MLX models for advanced detection")
                        .font(.caption)
                        .foregroundStyle(GhostTheme.secondaryText)

                    Button {
                        // TODO: Show model management
                    } label: {
                        Label("Manage Models", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(true)  // Coming in Phase 3
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal)
    }
}

// MARK: - Privacy

struct PrivacySettingsTab: View {
    @AppStorage("detect_email") private var detectEmail = true
    @AppStorage("detect_phone") private var detectPhone = true
    @AppStorage("detect_creditCard") private var detectCreditCard = true
    @AppStorage("detect_ssn") private var detectSSN = true
    @AppStorage("detect_ipAddress") private var detectIP = true
    @AppStorage("detect_apiKey") private var detectAPIKey = true

    var body: some View {
        Form {
            Section("PII Categories to Detect") {
                Toggle("Emails", isOn: $detectEmail)
                Toggle("Phone Numbers", isOn: $detectPhone)
                Toggle("Credit Cards", isOn: $detectCreditCard)
                Toggle("Social Security Numbers", isOn: $detectSSN)
                Toggle("IP Addresses", isOn: $detectIP)
                Toggle("API Keys & Tokens", isOn: $detectAPIKey)
            }

            Section("Token History") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Stored Tokens")
                        Text("\(GhostMappingStore.shared.count) [GHOST_X] mappings")
                            .font(.caption)
                            .foregroundStyle(GhostTheme.secondaryText)
                    }
                    Spacer()
                    Button("Clear All") {
                        GhostMappingStore.shared.clearAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal)
    }
}

// MARK: - About

struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "theatermasks.fill")
                .font(.system(size: 48))
                .foregroundStyle(GhostTheme.purple)

            Text("GhostClip")
                .font(.title.bold())

            Text("Version 1.0.0")
                .font(.caption)
                .foregroundStyle(GhostTheme.secondaryText)

            Text("Local PII masking for LLM prompts.\nYour data never leaves your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(GhostTheme.secondaryText)

            Spacer()

            HStack(spacing: 20) {
                Link("Privacy Policy", destination: URL(string: "https://ghostclip.app/privacy")!)
                Text("·").foregroundStyle(GhostTheme.secondaryText)
                Link("GitHub", destination: URL(string: "https://github.com/ghostclip")!)
            }
            .font(.caption)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

#Preview {
    SettingsView()
}
