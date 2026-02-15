import SwiftUI

struct OnboardingView: View {
    @AppStorage(GhostClipConstants.StorageKeys.onboardingComplete) private var onboardingComplete = false
    @State private var currentPage = 0

    var body: some View {
        TabView(selection: $currentPage) {
            // Slide 1: Welcome
            OnboardingSlide(
                icon: "ghost",
                iconFallback: "theatermasks.fill",
                title: "Welcome to GhostClip",
                subtitle: "Local PII masking for LLM prompts",
                detail: "⌥⌘G anywhere. Local-only privacy.",
                buttonTitle: "Next",
                action: { withAnimation { currentPage = 1 } }
            )
            .tag(0)

            // Slide 2: How It Works
            OnboardingSlide(
                icon: "wand.and.stars",
                iconFallback: "wand.and.stars",
                title: "Instant Redaction",
                subtitle: "⌥⌘G summons editor. Mask with one click.",
                detail: "Paste → Highlights → Ghost → Safe for ChatGPT.",
                buttonTitle: "Next",
                action: { withAnimation { currentPage = 2 } }
            )
            .tag(1)

            // Slide 3: Get Started
            OnboardingSlide(
                icon: "checkmark.shield.fill",
                iconFallback: "checkmark.shield.fill",
                title: "Ready?",
                subtitle: "Free: Regex. Pro: AI accuracy.",
                detail: "Pro: MLX + Vault (€19)",
                buttonTitle: "Start Ghosting",
                action: { onboardingComplete = true }
            )
            .tag(2)
        }
        .tabViewStyle(.automatic)
        .frame(width: 560, height: 420)
        .background(GhostTheme.panelBackground)
    }
}

// MARK: - Slide Component

private struct OnboardingSlide: View {
    let icon: String
    let iconFallback: String
    let title: String
    let subtitle: String
    let detail: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: iconFallback)
                .font(.system(size: 64))
                .foregroundStyle(GhostTheme.purple)
                .symbolRenderingMode(.hierarchical)

            Text(title)
                .font(GhostTheme.titleFont)
                .foregroundStyle(GhostTheme.primaryText)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(GhostTheme.secondaryText)
                .multilineTextAlignment(.center)

            Text(detail)
                .font(.callout)
                .foregroundStyle(GhostTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button(action: action) {
                Text(buttonTitle)
                    .font(.headline)
                    .frame(maxWidth: 200)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(GhostTheme.purple)
            .controlSize(.large)

            // Page indicators
            HStack(spacing: 8) {
                ForEach(0..<3) { idx in
                    Circle()
                        .fill(idx == pageIndex ? GhostTheme.purple : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 20)
        }
        .padding()
    }

    private var pageIndex: Int {
        switch buttonTitle {
        case "Start Ghosting": return 2
        case "Next": return title.contains("Welcome") ? 0 : 1
        default: return 0
        }
    }
}

#Preview {
    OnboardingView()
}
