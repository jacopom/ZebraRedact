import SwiftUI

// MARK: - Main Window Sidebar

struct MainWindowSidebar: View {
    @ObservedObject var detector: PIIDetector
    @Binding var redactionMode: RedactionMode
    @Binding var privacyLevel: Double // 0.0 = max privacy, 1.0 = max context
    @Binding var inputText: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                redactionModeSection
                privacyLevelSection
                piiFiltersSection
                privacyScoreSection
            }
            .padding(DesignSystem.Spacing.md)
        }
        .frame(width: 240)
        .background(DesignSystem.Colors.panel)
    }

    // MARK: - Redaction Mode Section

    private var redactionModeSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionHeader("REDACTION MODE")

            ForEach(RedactionMode.allCases, id: \.self) { mode in
                RadioButton(
                    title: mode.title,
                    subtitle: mode.description,
                    isSelected: redactionMode == mode,
                    action: { redactionMode = mode }
                )
            }
        }
    }

    // MARK: - Privacy Level Section

    private var privacyLevelSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionHeader("PRIVACY vs CONTEXT")

            VStack(spacing: 4) {
                Slider(value: $privacyLevel, in: 0...1)
                    .onChange(of: privacyLevel) { _, newValue in
                        updatePIIFiltersFromLevel(newValue)
                    }

                HStack {
                    Text("Max Privacy")
                        .font(.caption2)
                        .foregroundColor(DesignSystem.Colors.secondary)
                    Spacer()
                    Text("Max Context")
                        .font(.caption2)
                        .foregroundColor(DesignSystem.Colors.secondary)
                }
            }
        }
    }

    // MARK: - PII Filters Section

    private var piiFiltersSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionHeader("PII TYPE FILTERS")

            ForEach(PIIType.allCases, id: \.self) { type in
                PIIFilterRow(
                    type: type,
                    isEnabled: detector.enabledCategories.contains(type),
                    count: detector.detectedItems.filter { $0.type == type }.count,
                    onToggle: {
                        togglePIIType(type)
                    }
                )
            }
        }
    }

    // MARK: - Privacy Score Section

    private var privacyScoreSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionHeader("PRIVACY SCORE")

            VStack(spacing: 8) {
                Text("\(detector.privacyScore)%")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(scoreColor)

                Text(scoreLabel)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.Radius.md)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(DesignSystem.Colors.tertiary)
            .tracking(0.5)
    }

    private var scoreColor: Color {
        switch detector.privacyScore {
        case 90...100: return DesignSystem.Colors.success
        case 70..<90: return DesignSystem.Colors.warning
        default: return DesignSystem.Colors.error
        }
    }

    private var scoreLabel: String {
        switch detector.privacyScore {
        case 90...100: return "Ready to share"
        case 70..<90: return "Review needed"
        default: return "Too exposed"
        }
    }

    private func togglePIIType(_ type: PIIType) {
        detector.toggleCategory(type)
        detector.remask(originalText: inputText)
    }

    private func updatePIIFiltersFromLevel(_ level: Double) {
        switch level {
        case 0...0.33:  // Max Privacy - enable all types
            detector.enabledCategories = Set(PIIType.allCases)
            redactionMode = .token

        case 0.34...0.66:  // Balanced
            detector.enabledCategories = [.email, .phone, .creditCard, .ssn, .ipAddress, .apiKey]
            redactionMode = .semantic

        case 0.67...1.0:  // Max Context - only highly sensitive
            detector.enabledCategories = [.creditCard, .ssn, .apiKey]
            redactionMode = .llmAware

        default:
            break
        }

        detector.scan(text: inputText)
    }
}

// MARK: - Radio Button Component

struct RadioButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "circle.circle.fill" : "circle")
                    .foregroundColor(isSelected ? DesignSystem.Colors.info : DesignSystem.Colors.tertiary)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignSystem.Typography.bodyEmphasis)
                        .foregroundColor(DesignSystem.Colors.primary)

                    Text(subtitle)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                }

                Spacer()
            }
            .padding(DesignSystem.Spacing.sm)
            .background(isSelected ? DesignSystem.Colors.info.opacity(0.1) : Color.clear)
            .cornerRadius(DesignSystem.Radius.sm)
        }
        .buttonStyle(.plain)
    }
}
