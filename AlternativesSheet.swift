import SwiftUI

/// Sheet for selecting redaction alternatives (DeepL-inspired)
struct AlternativesSheet: View {
    let item: PIIItem
    @ObservedObject var detector: PIIDetector
    @Binding var inputText: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.type.rawValue)
                        .font(DesignSystem.Typography.captionEmphasis)
                        .foregroundColor(DesignSystem.Colors.secondary)

                    Text(item.originalText)
                        .font(DesignSystem.Typography.mono)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(item.type.highlightColor)
                        .cornerRadius(DesignSystem.Radius.sm)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.panel)

            Divider()

            // Alternatives list
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Text("Redaction Options")
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.primary)

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        ForEach(item.alternatives) { alternative in
                            alternativeButton(alternative)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }
        }
        .frame(width: 500, height: 400)
        .background(DesignSystem.Colors.background)
    }

    private func alternativeButton(_ alternative: RedactionAlternative) -> some View {
        Button {
            selectAlternative(alternative)
        } label: {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                // Selection indicator
                Image(systemName: alternative.id == item.selectedAlternativeId ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(alternative.id == item.selectedAlternativeId ? DesignSystem.Colors.info : DesignSystem.Colors.tertiary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    // Redacted text
                    Text(alternative.text)
                        .font(DesignSystem.Typography.mono)
                        .foregroundColor(DesignSystem.Colors.primary)

                    // Description
                    Text(alternative.description)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Strategy badge
                    Text(alternative.strategy.rawValue)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.secondary.opacity(0.15))
                        .cornerRadius(DesignSystem.Radius.sm)
                }

                Spacer()
            }
            .padding(DesignSystem.Spacing.md)
            .background(alternative.id == item.selectedAlternativeId ? DesignSystem.Colors.info.opacity(0.1) : DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .stroke(
                        alternative.id == item.selectedAlternativeId ? DesignSystem.Colors.info : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func selectAlternative(_ alternative: RedactionAlternative) {
        if let index = detector.detectedItems.firstIndex(where: { $0.id == item.id }) {
            detector.detectedItems[index].selectedAlternativeId = alternative.id
            // Regenerate ghosted text
            detector.scan(text: inputText)
        }
    }
}

#Preview {
    AlternativesSheet(
        item: PIIItem(
            type: .email,
            range: "test@example.com".startIndex..<"test@example.com".endIndex,
            originalText: "test@example.com",
            alternatives: [],
            selectedAlternativeId: UUID(),
            confidence: 0.95,
            isMasked: true
        ),
        detector: PIIDetector(),
        inputText: .constant("Test text")
    )
}
