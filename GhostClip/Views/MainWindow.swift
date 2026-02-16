import SwiftUI

struct MainWindow: View {
    @StateObject private var detector = PIIDetector()
    @State private var inputText: String = ""
    @State private var isProcessing: Bool = false

    var body: some View {
        HSplitView {
            // Left Panel: Input
            inputPanel
                .frame(minWidth: 300)

            // Right Panel: Output
            outputPanel
                .frame(minWidth: 300)
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(DesignSystem.Colors.background)
    }

    // MARK: - Input Panel

    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Input Text")
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.primary)

                Spacer()

                if !inputText.isEmpty {
                    Button("Clear") {
                        inputText = ""
                        detector.detectedItems = []
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.panel)

            Divider()

            // Text input area
            TextEditor(text: $inputText)
                .font(DesignSystem.Typography.body)
                .lineSpacing(DesignSystem.Typography.lineSpacing)
                .padding(DesignSystem.Spacing.sm)
                .scrollContentBackground(.hidden)
                .onChange(of: inputText) { _, newValue in
                    // Live detection as user types
                    detector.scan(text: newValue)
                }

            Divider()

            // Footer with stats
            HStack {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "character.cursor.ibeam")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.tertiary)

                    Text("\(inputText.count) characters")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                }

                if !detector.detectedItems.isEmpty {
                    Circle()
                        .fill(DesignSystem.Colors.tertiary)
                        .frame(width: 3, height: 3)

                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "eye.fill")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.warning)

                        Text("\(detector.detectedItems.count) PII items")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondary)
                    }
                }

                Spacer()

                Button {
                    detector.scan(text: inputText)
                } label: {
                    Label("Scan", systemImage: "magnifyingglass")
                        .font(DesignSystem.Typography.bodyEmphasis)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(inputText.isEmpty)
            }
            .padding(DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.panel)
        }
    }


    // MARK: - Output Panel

    private var outputPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Redacted Output")
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.primary)

                    if !detector.detectedItems.isEmpty {
                        Text("\(detector.detectedItems.count) items • \(detector.privacyScore)% privacy score")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondary)
                    }
                }

                Spacer()

                if !detector.ghostedText.isEmpty {
                    Button {
                        copyToClipboard(detector.ghostedText)
                    } label: {
                        Label("Copy", systemImage: "doc.on.clipboard")
                            .font(DesignSystem.Typography.bodyEmphasis)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.panel)

            Divider()

            // Results area
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    if inputText.isEmpty {
                        emptyState
                    } else if detector.detectedItems.isEmpty {
                        noDetectionsState
                    } else {
                        detectionsView
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Enter text to detect PII")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("Paste or type text in the input panel to scan for sensitive information")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - No Detections State

    private var noDetectionsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("No PII Detected")
                .font(.title3)
                .foregroundColor(.primary)

            Text("Your text appears safe to share")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detections View

    private var detectionsView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            // Clickable inline tokens (NSTextView-based)
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack {
                    Text("Redacted Text")
                        .font(DesignSystem.Typography.bodyEmphasis)
                        .foregroundColor(DesignSystem.Colors.secondary)

                    Spacer()

                    Text("\(detector.detectedItems.count) items")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.tertiary)
                }

                ClickableTokenTextView(
                    text: detector.ghostedText,
                    items: detector.detectedItems,
                    inputText: $inputText,
                    detector: detector
                )
                .frame(minHeight: 250)
                .cornerRadius(DesignSystem.Radius.md)

                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "hand.tap")
                        .font(.caption)
                        .foregroundColor(DesignSystem.Colors.info)

                    Text("Click any highlighted token to change its redaction")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                }
            }

            // Confidence Assessment
            if let assessment = detector.confidenceAssessment {
                confidenceView(assessment: assessment)
            }
        }
    }

    // MARK: - Confidence View

    private func confidenceView(assessment: ConfidenceAssessment) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // Header with status badge
            HStack {
                Text("Confidence Assessment")
                    .font(DesignSystem.Typography.headline)

                Spacer()

                // Status badge
                HStack(spacing: 6) {
                    Image(systemName: assessment.statusIcon)
                    Text(assessment.statusText)
                        .font(DesignSystem.Typography.captionEmphasis)
                }
                .foregroundColor(.white)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, 6)
                .background(colorForStatus(assessment.status))
                .cornerRadius(DesignSystem.Radius.lg)
            }

            // Overall confidence gauge
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Overall Confidence")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.secondary)

                    Spacer()

                    Text("\(assessment.overallConfidence)%")
                        .font(DesignSystem.Typography.title)
                        .fontWeight(.bold)
                        .foregroundColor(colorForStatus(assessment.status))
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                            .fill(DesignSystem.Colors.secondary.opacity(0.15))

                        // Filled portion
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                            .fill(colorForStatus(assessment.status))
                            .frame(width: geometry.size.width * CGFloat(assessment.overallConfidence) / 100.0)
                    }
                }
                .frame(height: 8)
            }

            // Explanation
            Text(assessment.explanation)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondary)
                .padding(.vertical, 4)

            Divider()

            // Metric breakdown
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Score Breakdown")
                    .font(DesignSystem.Typography.bodyEmphasis)

                metricRow(
                    label: "Task Completability",
                    value: assessment.taskCompletability,
                    description: "LLM can still complete the task"
                )

                metricRow(
                    label: "Hallucination Risk",
                    value: 100 - assessment.hallucinationRisk,
                    description: "Low risk of LLM fabricating details",
                    isInverted: true
                )

                metricRow(
                    label: "Coherence",
                    value: assessment.coherence,
                    description: "Text structure remains logical"
                )
            }

            // Issues section (if any)
            if !detector.confidenceIssues.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(DesignSystem.Colors.warning)
                        Text("Review Suggestions")
                            .font(DesignSystem.Typography.bodyEmphasis)
                    }

                    ForEach(detector.confidenceIssues) { issue in
                        issueRow(issue: issue)
                    }
                }
            }
        }
        .cardStyle()
    }

    private func metricRow(label: String, value: Int, description: String, isInverted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.primary)

                Spacer()

                Text("\(value)%")
                    .font(DesignSystem.Typography.captionEmphasis)
                    .foregroundColor(colorForMetric(value))
            }

            // Mini progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DesignSystem.Colors.secondary.opacity(0.15))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorForMetric(value))
                        .frame(width: geometry.size.width * CGFloat(value) / 100.0)
                }
            }
            .frame(height: 4)

            Text(description)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.tertiary)
        }
    }

    private func issueRow(issue: ConfidenceIssue) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(issue.item.type.highlightColor)
                    .frame(width: 8, height: 8)

                Text(issue.item.originalText)
                    .font(DesignSystem.Typography.monoSmall)
                    .fontWeight(.medium)
            }

            Text(issue.impact)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondary)

            HStack(spacing: 4) {
                Image(systemName: "arrow.right")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.tertiary)

                Text(issue.suggestion)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.info)
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.warning.opacity(0.1))
        .cornerRadius(DesignSystem.Radius.sm)
    }

    private func colorForStatus(_ status: ConfidenceStatus) -> Color {
        switch status {
        case .ready: return DesignSystem.Colors.success
        case .reviewNeeded: return DesignSystem.Colors.warning
        case .tooDegraded: return DesignSystem.Colors.error
        }
    }

    private func colorForMetric(_ value: Int) -> Color {
        switch value {
        case 80...100: return DesignSystem.Colors.success
        case 50..<80: return DesignSystem.Colors.warning
        default: return DesignSystem.Colors.error
        }
    }

    // MARK: - Helpers

    private var scoreColor: Color {
        switch detector.privacyScore {
        case 90...100: return DesignSystem.Colors.success
        case 70..<90: return DesignSystem.Colors.warning
        default: return DesignSystem.Colors.error
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

#Preview {
    MainWindow()
        .frame(width: 900, height: 700)
}
