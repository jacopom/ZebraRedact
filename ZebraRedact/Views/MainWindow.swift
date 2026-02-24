import SwiftUI

struct MainWindow: View {
    @StateObject private var detector = PIIDetector()
    @State private var inputText: String = ""
    @State private var isProcessing: Bool = false
    @State private var selectedToken: PIIItem?
    @State private var dropdownAnchor: Anchor<CGRect>?

    var body: some View {
        ZStack {
            HSplitView {
                // Left Panel: Input
                inputPanel
                    .frame(minWidth: 300)

                // Right Panel: Output
                outputPanel
                    .frame(minWidth: 300)
            }

            // In-window dropdown overlay
            if let token = selectedToken {
                // Backdrop - blocks clicks to content below
                Color.black.opacity(0.3)
                    .contentShape(Rectangle())
                    .allowsHitTesting(true)
                    .onTapGesture {
                        selectedToken = nil
                    }
                    .overlay(alignment: .center) {
                        // Dropdown - compact and positioned
                        AlternativesDropdown(
                            item: token,
                            detector: detector,
                            inputText: $inputText,
                            selectedToken: $selectedToken
                        )
                        .frame(width: 300)
                        .frame(maxHeight: 500)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(10)
                        .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 8)
                        .allowsHitTesting(true)
                        .padding(40)
                    }
            }
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

            // Toolbar with editing tools
            HStack(spacing: 12) {
                // Paste from clipboard
                Button(action: pasteFromClipboard) {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .help("Paste from clipboard")

                Divider()
                    .frame(height: 16)

                // Load sample text
                Button(action: loadSampleText) {
                    Label("Sample", systemImage: "text.document")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .help("Load sample text")

                Divider()
                    .frame(height: 16)

                // Remove line breaks
                Button(action: removeLineBreaks) {
                    Label("Flatten", systemImage: "arrow.left.arrow.right")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .help("Remove extra line breaks")
                .disabled(inputText.isEmpty)

                Divider()
                    .frame(height: 16)

                // Fix spacing
                Button(action: fixSpacing) {
                    Label("Clean", systemImage: "wand.and.stars")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .help("Clean up spacing and formatting")
                .disabled(inputText.isEmpty)

                Spacer()

                // Undo button
                Button(action: { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .help("Undo")
                .disabled(inputText.isEmpty)

                // Redo button
                Button(action: { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .help("Redo")
                .disabled(inputText.isEmpty)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Text input area with highlighting
            InputTextView(
                text: $inputText,
                highlightRange: selectedToken?.range,
                highlightColor: selectedToken?.type.highlightColor ?? .clear,
                onTextChange: { newText in
                    detector.scan(text: newText)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
            }
            .padding(DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.panel)
        }
    }


    // MARK: - Output Panel

    private var outputPanel: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                // Header (simplified - matches Input Text header)
                HStack {
                    Text("Redacted Output")
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.primary)

                    Spacer()
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

            // Compact confidence panel (bottom-right)
            if !detector.detectedItems.isEmpty, let assessment = detector.confidenceAssessment {
                compactConfidenceView(assessment: assessment)
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
            // Redacted text area
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                ClickableTokenTextView(
                    text: detector.redactedText,
                    items: detector.detectedItems,
                    onTokenClick: { item in
                        selectedToken = item
                    }
                )
                .frame(minHeight: 400)
                .cornerRadius(DesignSystem.Radius.md)

                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "hand.tap")
                        .font(.caption)
                        .foregroundColor(DesignSystem.Colors.info)

                    Text("Click any highlighted token to change its redaction")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)

                    Spacer()

                    Button {
                        copyToClipboard(detector.redactedText)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy Redacted")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
        }
    }

    // MARK: - Compact Confidence View

    private func compactConfidenceView(assessment: ConfidenceAssessment) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Status badge
            HStack(spacing: 6) {
                Image(systemName: assessment.statusIcon)
                    .font(.caption)
                Text(assessment.statusText)
                    .font(DesignSystem.Typography.captionEmphasis)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(colorForStatus(assessment.status))
            .cornerRadius(DesignSystem.Radius.lg)

            // Compact metrics card
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Confidence")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                    Spacer()
                    Text("\(assessment.overallConfidence)%")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(colorForStatus(assessment.status))
                }

                Divider()

                // Compact metrics
                HStack(spacing: 4) {
                    compactMetric(label: "Task", value: assessment.taskCompletability)
                    Divider().frame(height: 20)
                    compactMetric(label: "Safe", value: 100 - assessment.hallucinationRisk)
                    Divider().frame(height: 20)
                    compactMetric(label: "Clear", value: assessment.coherence)
                }
            }
            .padding(12)
            .background(DesignSystem.Colors.panel)
            .cornerRadius(DesignSystem.Radius.md)
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        }
        .frame(width: 200)
    }

    private func compactMetric(label: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)%")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colorForMetric(value))
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(DesignSystem.Colors.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Confidence View (unused - keeping for reference)

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

    // MARK: - Toolbar Actions

    private func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            inputText = text
            detector.scan(text: text)
        }
    }

    private func loadSampleText() {
        inputText = """
        Hi team, please update the account for John Smith.

        Email: john.smith@acme-corp.com
        Phone: +1 (555) 867-5309
        Credit Card: 4111-1111-1111-1111
        SSN: 123-45-6789
        Server: 192.168.1.100

        API Key: sk-proj1234567890abcdefghij1234567890

        Thanks,
        Sarah
        """
        detector.scan(text: inputText)
    }

    private func removeLineBreaks() {
        // Replace multiple newlines with single space
        inputText = inputText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        detector.scan(text: inputText)
    }

    private func fixSpacing() {
        // Clean up multiple spaces, tabs, and formatting
        inputText = inputText
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        detector.scan(text: inputText)
    }
}

// MARK: - Alternatives Dropdown (In-Window)

struct AlternativesDropdown: View {
    let item: PIIItem
    @ObservedObject var detector: PIIDetector
    @Binding var inputText: String
    @Binding var selectedToken: PIIItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - Shows which token is being edited
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    // Original value
                    HStack(spacing: 6) {
                        Text("Original:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(item.originalText)
                            .font(.system(.callout, design: .monospaced))
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(item.type.highlightColor.opacity(0.3))
                            .cornerRadius(4)
                    }

                    // Current token
                    HStack(spacing: 6) {
                        Text("Current:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(item.token)
                            .font(.system(.callout, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }

                    Text(item.type.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }

                Spacer()

                Button {
                    selectedToken = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            // Alternatives list
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.alternatives) { alternative in
                        AlternativeRow(
                            alternative: alternative,
                            isSelected: alternative.id == item.selectedAlternativeId,
                            onSelect: {
                                selectAlternative(alternative)
                            }
                        )
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .frame(maxHeight: 450)
        }
        .onHover { _ in
            // Override cursor for entire dropdown
            NSCursor.arrow.set()
        }
    }

    private func selectAlternative(_ alternative: RedactionAlternative) {
        print("selectAlternative called for: \(alternative.text)")

        // Update selection immediately
        if let index = detector.detectedItems.firstIndex(where: { $0.id == item.id }) {
            print("Found item at index \(index), updating selectedAlternativeId")
            detector.detectedItems[index].selectedAlternativeId = alternative.id

            // Regenerate ghosted text WITHOUT rescanning (keeps existing item IDs)
            print("Remasking text with new selection")
            detector.remask(originalText: inputText)

            // Force view refresh
            detector.objectWillChange.send()
        } else {
            print("ERROR: Could not find item in detector.detectedItems")
        }

        // Close dropdown immediately after selection
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            print("Closing dropdown")
            selectedToken = nil
        }
    }
}

struct AlternativeRow: View {
    let alternative: RedactionAlternative
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: {
            print("AlternativeRow clicked: \(alternative.text)")
            onSelect()
        }) {
            HStack(spacing: 12) {
                // Radio button icon
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .gray)
                    .frame(width: 28)

                // Alternative text
                VStack(alignment: .leading, spacing: 3) {
                    Text(alternative.text)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(alternative.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.15) :
                          isHovered ? Color.gray.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Input Text View with Highlighting

struct InputTextView: NSViewRepresentable {
    @Binding var text: String
    let highlightRange: Range<String.Index>?
    let highlightColor: Color
    let onTextChange: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.controlBackgroundColor
        textView.textContainerInset = CGSize(width: 16, height: 16)
        textView.delegate = context.coordinator

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only update text if it actually changed
        let currentText = textView.string
        if currentText != text {
            // Save cursor position
            let selectedRange = textView.selectedRange()
            textView.string = text
            // Restore cursor if text length allows
            if selectedRange.location <= text.count {
                textView.setSelectedRange(selectedRange)
            }
        }

        // Apply highlighting
        if let textStorage = textView.textStorage {
            // Clear all background colors first
            textStorage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: textStorage.length))

            // Apply highlight to specific range if provided
            if let range = highlightRange, text.count > 0 {
                let nsRange = NSRange(range, in: text)
                if nsRange.location != NSNotFound && nsRange.location + nsRange.length <= textStorage.length {
                    let highlightedText = String(text[range])
                    print("Highlighting: '\(highlightedText)' at location: \(nsRange.location), length: \(nsRange.length)")

                    textStorage.addAttribute(
                        .backgroundColor,
                        value: NSColor(highlightColor).withAlphaComponent(0.5),
                        range: nsRange
                    )

                    // Scroll to show the highlight
                    textView.scrollRangeToVisible(nsRange)
                }
            }
        }

        context.coordinator.onTextChange = onTextChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onTextChange: onTextChange)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onTextChange: (String) -> Void

        init(text: Binding<String>, onTextChange: @escaping (String) -> Void) {
            _text = text
            self.onTextChange = onTextChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            onTextChange(textView.string)
        }
    }
}

#Preview {
    MainWindow()
        .frame(width: 900, height: 700)
}
