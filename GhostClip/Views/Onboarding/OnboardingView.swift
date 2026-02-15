import SwiftUI

struct OnboardingView: View {
    @AppStorage(GhostClipConstants.StorageKeys.onboardingComplete) private var onboardingComplete = false
    @State private var currentPage = 0

    var body: some View {
        VStack(spacing: 0) {
            // Content
            Group {
                switch currentPage {
                case 0: welcomeSlide
                case 1: demoSlide
                case 2: readySlide
                default: readySlide
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.slide)
            .animation(.easeInOut(duration: 0.3), value: currentPage)

            Divider()

            // Navigation
            HStack {
                // Page dots
                HStack(spacing: 8) {
                    ForEach(0..<3) { idx in
                        Circle()
                            .fill(idx == currentPage ? GhostTheme.purple : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                Spacer()

                if currentPage < 2 {
                    Button("Next") {
                        withAnimation { currentPage += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(GhostTheme.purple)
                    .controlSize(.large)
                } else {
                    Button("Start Ghosting") {
                        onboardingComplete = true
                        NSApp.keyWindow?.close()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(GhostTheme.purple)
                    .controlSize(.large)
                }
            }
            .padding(20)
        }
        .frame(width: 580, height: 460)
        .background(GhostTheme.panelBackground)
    }

    // MARK: - Slide 1: Welcome

    private var welcomeSlide: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "theatermasks.fill")
                .font(.system(size: 56))
                .foregroundStyle(GhostTheme.purple)

            Text("Welcome to GhostClip")
                .font(.system(.title, design: .rounded, weight: .bold))

            Text("Hide personal data before pasting into AI.")
                .font(.title3)
                .foregroundStyle(GhostTheme.secondaryText)

            VStack(alignment: .leading, spacing: 8) {
                featureRow(icon: "keyboard", text: "Press ⌥⌘G from anywhere to summon")
                featureRow(icon: "eye.slash.fill", text: "Emails, phones, cards highlighted & masked")
                featureRow(icon: "lock.shield.fill", text: "100% local — nothing leaves your Mac")
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(32)
    }

    // MARK: - Slide 2: Live Demo

    private var demoSlide: some View {
        VStack(spacing: 16) {
            Text("See it in action")
                .font(.system(.title2, design: .rounded, weight: .bold))

            HStack(spacing: 0) {
                // Before
                VStack(alignment: .leading, spacing: 6) {
                    Text("BEFORE")
                        .font(.caption.bold())
                        .foregroundStyle(GhostTheme.red)
                        .tracking(1)

                    Text(demoAttributedBefore)
                        .font(.system(.body, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity)
                .padding(.trailing, 8)

                // After
                VStack(alignment: .leading, spacing: 6) {
                    Text("AFTER")
                        .font(.caption.bold())
                        .foregroundStyle(GhostTheme.green)
                        .tracking(1)

                    Text(demoAfterText)
                        .font(.system(.body, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity)
                .padding(.leading, 8)
            }
            .padding(.horizontal, 24)

            Text("Emails, phones, and API keys are replaced with safe tokens.")
                .font(.callout)
                .foregroundStyle(GhostTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    // MARK: - Slide 3: Ready

    private var readySlide: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(GhostTheme.green)

            Text("You're all set!")
                .font(.system(.title, design: .rounded, weight: .bold))

            Text("Press ⌥⌘G anytime to ghost your clipboard.")
                .font(.title3)
                .foregroundStyle(GhostTheme.secondaryText)

            HStack(spacing: 24) {
                KeyboardShortcutBadge(keys: ["⌥", "⌘", "G"], label: "Summon")
                KeyboardShortcutBadge(keys: ["⌘", "⏎"], label: "Apply")
                KeyboardShortcutBadge(keys: ["esc"], label: "Dismiss")
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(32)
    }

    // MARK: - Helpers

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(GhostTheme.purple)
                .frame(width: 24)
            Text(text)
                .font(.body)
        }
    }

    private var demoAttributedBefore: AttributedString {
        var str = AttributedString("Contact john@acme.com\nor call 555-867-5309\nAPI: sk-proj12345abcdef67890xyz")
        // Highlight emails
        if let range = str.range(of: "john@acme.com") {
            str[range].backgroundColor = Color(hex: 0xFCA5A5)
        }
        if let range = str.range(of: "555-867-5309") {
            str[range].backgroundColor = Color(hex: 0xFDE68A)
        }
        if let range = str.range(of: "sk-proj12345abcdef67890xyz") {
            str[range].backgroundColor = Color(hex: 0xFDBA74)
        }
        return str
    }

    private var demoAfterText: String {
        "Contact [GHOST_A1B2]\nor call [GHOST_C3D4]\nAPI: [GHOST_E5F6]"
    }
}

// MARK: - Keyboard Shortcut Badge

struct KeyboardShortcutBadge: View {
    let keys: [String]
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(GhostTheme.secondaryText)
        }
    }
}
