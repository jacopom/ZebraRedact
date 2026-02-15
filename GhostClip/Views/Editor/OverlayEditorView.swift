import SwiftUI

struct OverlayEditorView: View {
    @StateObject private var detector = PIIDetector()
    @State private var originalText: String
    @State private var showGhosted = false
    @State private var copied = false
    @State private var hoveredType: PIIType?

    let initialText: String
    let onApply: (String) -> Void

    init(initialText: String, onApply: @escaping (String) -> Void) {
        self.initialText = initialText
        self.onApply = onApply
        _originalText = State(initialValue: initialText)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            HStack(spacing: 0) {
                editorArea
                Divider()
                sidebar
                    .frame(width: 240)
            }
            Divider()
            footerBar
        }
        .frame(
            minWidth: GhostClipConstants.Overlay.minWidth,
            minHeight: GhostClipConstants.Overlay.minHeight
        )
        .background(GhostTheme.panelBackground)
        .onAppear {
            detector.scan(text: originalText)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "theatermasks.fill")
                .font(.title2)
                .foregroundStyle(GhostTheme.purple)

            Text("GhostClip")
                .font(GhostTheme.titleFont)
                .foregroundStyle(GhostTheme.purple)

            Spacer()

            // View toggle
            Picker("View", selection: $showGhosted) {
                Text("Highlight").tag(false)
                Text("Preview").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            GhostScoreBadge(score: detector.privacyScore, method: detector.detectionMethod)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Editor Area

    private var editorArea: some View {
        ZStack {
            if showGhosted {
                GhostedPreviewView(text: detector.ghostedText)
            } else if originalText.isEmpty {
                emptyState
            } else {
                HighlightedTextView(
                    text: $originalText,
                    piiItems: detector.detectedItems,
                    isEditable: true,
                    onTextChange: { newText in
                        detector.scan(text: newText)
                    }
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.cursor")
                .font(.system(size: 40))
                .foregroundStyle(GhostTheme.tertiaryText)
            Text("Paste or type text to scan for PII")
                .font(.title3)
                .foregroundStyle(GhostTheme.secondaryText)

            HStack(spacing: 12) {
                Button {
                    if let clip = ClipboardManager.shared.readText(), !clip.isEmpty {
                        originalText = clip
                        detector.scan(text: originalText)
                    }
                } label: {
                    Label("Paste Clipboard", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)
                .tint(GhostTheme.purple)

                Button("Try Sample Text") {
                    originalText = sampleText
                    detector.scan(text: originalText)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private let sampleText = """
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

    // MARK: - Sidebar (Hemingway-style stats)

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Score
                sidebarScore

                Divider()

                // PII breakdown
                sidebarPIIBreakdown

                Divider()

                // Quick actions
                sidebarActions

                Spacer()

                // Help text
                sidebarHelp
            }
            .padding(16)
        }
        .background(GhostTheme.sidebarBackground)
    }

    private var sidebarScore: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy Score")
                .font(.caption.bold())
                .foregroundStyle(GhostTheme.secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(detector.privacyScore)%")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(GhostTheme.scoreColor(for: detector.privacyScore))

                Text(scoreLabel)
                    .font(.caption.bold())
                    .foregroundStyle(GhostTheme.scoreColor(for: detector.privacyScore))
            }

            Text("\(detector.detectedItems.filter(\.isMasked).count) of \(detector.detectedItems.count) items ghosted")
                .font(.caption)
                .foregroundStyle(GhostTheme.secondaryText)
        }
    }

    private var scoreLabel: String {
        switch detector.privacyScore {
        case 100:     return "Clean"
        case 90..<100: return "Safe"
        case 70..<90:  return "Caution"
        default:       return "Unsafe"
        }
    }

    private var sidebarPIIBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Detected PII")
                .font(.caption.bold())
                .foregroundStyle(GhostTheme.secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)

            if detector.detectedItems.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(GhostTheme.green)
                    Text("No PII detected")
                        .font(.callout)
                        .foregroundStyle(GhostTheme.secondaryText)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(piiGrouped, id: \.type) { group in
                    PIICategoryRow(
                        type: group.type,
                        count: group.count,
                        maskedCount: group.maskedCount,
                        isHovered: hoveredType == group.type,
                        onToggle: {
                            toggleAllOfType(group.type)
                        }
                    )
                    .onHover { isHovered in
                        hoveredType = isHovered ? group.type : nil
                    }
                }
            }
        }
    }

    private var sidebarActions: some View {
        VStack(spacing: 8) {
            Button {
                detector.maskAll()
                detector.remask(originalText: originalText)
            } label: {
                Label("Ghost All PII", systemImage: "eye.slash.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(GhostTheme.purple)
            .controlSize(.regular)

            Button {
                detector.unmaskAll()
                detector.remask(originalText: originalText)
            } label: {
                Label("Reveal All", systemImage: "eye.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Button {
                if let clipText = ClipboardManager.shared.readText(), !clipText.isEmpty {
                    originalText = clipText
                    detector.scan(text: originalText)
                }
            } label: {
                Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    private var sidebarHelp: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Highlighted text contains PII.")
                .font(.caption)
                .foregroundStyle(GhostTheme.secondaryText)
            Text("Click a category to toggle ghosting.")
                .font(.caption)
                .foregroundStyle(GhostTheme.secondaryText)
            Text("Switch to Preview to see safe output.")
                .font(.caption)
                .foregroundStyle(GhostTheme.secondaryText)
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            // Character count
            Text("\(originalText.count) chars · \(originalText.split(separator: " ").count) words")
                .font(.caption)
                .foregroundStyle(GhostTheme.tertiaryText)

            Spacer()

            Button("Cancel") {
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Button {
                let output = detector.ghostedText
                onApply(output)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copied = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.clipboard.fill")
                    Text(copied ? "Copied!" : "Copy Safe Text")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(copied ? GhostTheme.green : GhostTheme.purple)
            .keyboardShortcut(.return, modifiers: .command)
            .animation(.easeInOut(duration: 0.2), value: copied)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private struct PIIGroup {
        let type: PIIType
        let count: Int
        let maskedCount: Int
    }

    private var piiGrouped: [PIIGroup] {
        var groups: [PIIType: (total: Int, masked: Int)] = [:]
        for item in detector.detectedItems {
            let current = groups[item.type, default: (0, 0)]
            groups[item.type] = (current.total + 1, current.masked + (item.isMasked ? 1 : 0))
        }
        return groups.map { PIIGroup(type: $0.key, count: $0.value.total, maskedCount: $0.value.masked) }
            .sorted { $0.count > $1.count }
    }

    private func toggleAllOfType(_ type: PIIType) {
        let allMasked = detector.detectedItems.filter { $0.type == type }.allSatisfy(\.isMasked)
        for i in detector.detectedItems.indices where detector.detectedItems[i].type == type {
            detector.detectedItems[i].isMasked = !allMasked
        }
        detector.remask(originalText: originalText)
    }
}

// MARK: - PII Category Row

struct PIICategoryRow: View {
    let type: PIIType
    let count: Int
    let maskedCount: Int
    let isHovered: Bool
    let onToggle: () -> Void

    private var allMasked: Bool { maskedCount == count }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                // Color indicator
                RoundedRectangle(cornerRadius: 3)
                    .fill(GhostTheme.highlightColor(for: type))
                    .frame(width: 16, height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(GhostTheme.legendColor(for: type), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(count) \(type.rawValue)\(count > 1 ? "s" : "")")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(GhostTheme.primaryText)

                    Text(allMasked ? "ghosted" : "\(maskedCount)/\(count) ghosted")
                        .font(.caption2)
                        .foregroundStyle(GhostTheme.secondaryText)
                }

                Spacer()

                Image(systemName: allMasked ? "eye.slash.fill" : "eye.fill")
                    .font(.caption)
                    .foregroundStyle(allMasked ? GhostTheme.purple : GhostTheme.tertiaryText)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? GhostTheme.highlightColor(for: type).opacity(0.3) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OverlayEditorView(
        initialText: """
        Hi, my name is John Smith. Contact me at john.smith@company.com or \
        call me at +1 (555) 123-4567.

        My credit card is 4111-1111-1111-1111 and SSN is 123-45-6789.

        Server IP: 192.168.1.100
        API key: sk-proj1234567890abcdefghij1234567890
        """,
        onApply: { print($0) }
    )
}
