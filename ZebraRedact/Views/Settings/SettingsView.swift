import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            AboutSettingsTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 340)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @AppStorage(ZebraRedactConstants.StorageKeys.showInDock) private var showInDock = true

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle(isOn: $showInDock) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show in Dock")
                        Text("Toggle between Dock icon and menu bar only")
                            .font(.caption)
                            .foregroundStyle(ZebraTheme.secondaryText)
                    }
                }
                .onChange(of: showInDock) { _, newValue in
                    NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                }
            }

            Section("Keyboard Shortcuts") {
                LabeledContent("Summon ZebraRedact", value: "⌥⌘Z")
                LabeledContent("Apply & Copy", value: "⌘Return")
                LabeledContent("Dismiss", value: "Escape")
            }

        }
        .formStyle(.grouped)
        .padding(.horizontal)
    }
}

// MARK: - Intelligence

struct IntelligenceSettingsTab: View {
    @AppStorage(ZebraRedactConstants.StorageKeys.detectionEngine) private var detectionEngine = "regex"
    @AppStorage("useSemanticReplacement") private var useSemanticReplacement = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Masking Strategy")
                        .font(.headline)
                    Text("Choose how sensitive data is replaced")
                        .font(.caption)
                        .foregroundStyle(ZebraTheme.secondaryText)
                }
                .padding(.vertical, 4)

                Toggle(isOn: $useSemanticReplacement) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Semantic Abstraction")
                        Text(useSemanticReplacement ?
                            "Replaces with realistic fake data (e.g., john@acme.com → alice.smith@example.com)" :
                            "Replaces with opaque tokens (e.g., john@acme.com → [EMAIL_A1B2])")
                            .font(.caption)
                            .foregroundStyle(ZebraTheme.secondaryText)
                    }
                }
                .toggleStyle(.switch)

                if useSemanticReplacement {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(ZebraTheme.purple.opacity(0.6))
                        Text("Semantic mode preserves context, letting LLMs work with abstracted but realistic data.")
                            .font(.caption2)
                            .foregroundStyle(ZebraTheme.secondaryText)
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Detection Engine")
                        .font(.headline)
                    Text("Choose how ZebraRedact identifies sensitive information")
                        .font(.caption)
                        .foregroundStyle(ZebraTheme.secondaryText)
                }
                .padding(.vertical, 4)

                Picker("", selection: $detectionEngine) {
                    HStack {
                        Image(systemName: "text.magnifyingglass")
                        VStack(alignment: .leading) {
                            Text("Regex (Fast)")
                            Text("Pattern-based detection, instant").font(.caption2).foregroundStyle(ZebraTheme.secondaryText)
                        }
                    }
                    .tag("regex")

                    HStack {
                        Image(systemName: "brain")
                        VStack(alignment: .leading) {
                            Text("NLTagger (Smart)")
                            Text("Apple's semantic detection").font(.caption2).foregroundStyle(ZebraTheme.secondaryText)
                        }
                    }
                    .tag("nltagger")

                    HStack {
                        Image(systemName: "cpu.fill")
                        VStack(alignment: .leading) {
                            Text("MLX (Advanced)")
                            Text("Local AI models (coming soon)").font(.caption2).foregroundStyle(ZebraTheme.secondaryText)
                        }
                    }
                    .tag("mlx")
                }
                .pickerStyle(.inline)
            }

            Section("Active Engine") {
                HStack {
                    Image(systemName: detectionEngine == "regex" ? "text.magnifyingglass" : detectionEngine == "nltagger" ? "brain" : "cpu.fill")
                        .foregroundStyle(ZebraTheme.purple)
                    Text(detectionEngine == "regex" ? "Regex-based (local, instant)" : detectionEngine == "nltagger" ? "NLTagger (semantic)" : "MLX (advanced)")
                    Spacer()
                    Text("Active")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(ZebraTheme.green.opacity(0.2))
                        .foregroundStyle(ZebraTheme.green)
                        .clipShape(Capsule())
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Local AI Models")
                        .font(.headline)
                    Text("Download and manage MLX models for advanced detection")
                        .font(.caption)
                        .foregroundStyle(ZebraTheme.secondaryText)

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
                        Text("\(TokenMappingStore.shared.count) token mappings")
                            .font(.caption)
                            .foregroundStyle(ZebraTheme.secondaryText)
                    }
                    Spacer()
                    Button("Clear All") {
                        TokenMappingStore.shared.clearAll()
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
        VStack(spacing: 12) {
            Spacer()

            Text("ZebraRedact")
                .font(.title.bold())

            Text("Version 1.0.0")
                .font(.caption)
                .foregroundStyle(ZebraTheme.secondaryText)

            Text("Local PII masking for LLM prompts.\nYour data never leaves your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(ZebraTheme.secondaryText)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

#Preview {
    SettingsView()
}
