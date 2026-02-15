import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            DetectionSettingsTab()
                .tabItem {
                    Label("Detection", systemImage: "eye.trianglebadge.exclamationmark")
                }

            AboutSettingsTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 400)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @AppStorage(GhostClipConstants.StorageKeys.onboardingComplete) private var onboardingComplete = true

    var body: some View {
        Form {
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

// MARK: - Detection

struct DetectionSettingsTab: View {
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

            Section("Detection Engine") {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundStyle(GhostTheme.purple)
                    Text("Regex-based (local, instant)")
                    Spacer()
                    Text("Active")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(GhostTheme.green.opacity(0.2))
                        .clipShape(Capsule())
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
