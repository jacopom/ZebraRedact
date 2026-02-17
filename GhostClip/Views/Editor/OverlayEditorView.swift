import SwiftUI

enum EditorMode: String, CaseIterable {
    case highlight = "Ghost"
    case preview = "Preview"
    case rehydrate = "Rehydrate"
}

struct OverlayEditorView: View {
    @StateObject private var detector = PIIDetector()
    @State private var originalText: String
    @State private var editorMode: EditorMode = .highlight
    @State private var copied = false
    @State private var hoveredType: PIIType?

    // Rehydrate state
    @State private var rehydrateInput = ""
    @State private var rehydrateOutput = ""
    @State private var rehydrateTokenCount = 0

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
            minWidth: ZebraRedactConstants.Overlay.minWidth,
            minHeight: ZebraRedactConstants.Overlay.minHeight
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

            Text("ZebraRedact")
                .font(GhostTheme.titleFont)
                .foregroundStyle(GhostTheme.purple)

            Spacer()

            // 3-way mode picker
            Picker("Mode", selection: $editorMode) {
                ForEach(EditorMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)

            if editorMode != .rehydrate {
                GhostScoreBadge(score: detector.privacyScore, method: detector.detectionMethod)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Editor Area

    private var editorArea: some View {
        ZStack {
            switch editorMode {
            case .highlight:
                if originalText.isEmpty {
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
            case .preview:
                GhostedPreviewView(text: detector.ghostedText)
            case .rehydrate:
                rehydrateArea
            }
        }
    }

    // MARK: - Rehydrate Area

    private var rehydrateArea: some View {
        VStack(spacing: 0) {
            // Top: paste LLM response
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("LLM Response", systemImage: "text.bubble")
                        .font(.caption.bold())
                        .foregroundStyle(GhostTheme.secondaryText)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    Button {
                        if let clip = ClipboardManager.shared.readText() {
                            rehydrateInput = clip
                            performRehydration()
                        }
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                TextEditor(text: $rehydrateInput)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .onChange(of: rehydrateInput) {
                        performRehydration()
                    }
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Bottom: rehydrated output
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Rehydrated Output", systemImage: "arrow.uturn.backward.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(GhostTheme.green)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    if rehydrateTokenCount > 0 {
                        Text("\(rehydrateTokenCount) token\(rehydrateTokenCount == 1 ? "" : "s") restored")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(GhostTheme.green.opacity(0.15))
                            .foregroundStyle(GhostTheme.green)
                            .clipShape(Capsule())
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                RehydratedTextView(
                    originalText: rehydrateInput,
                    rehydratedText: rehydrateOutput,
                    mappings: GhostMappingStore.shared.findTokens(in: rehydrateInput)
                )
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: .infinity)
            .background(GhostTheme.green.opacity(0.02))
        }
    }

    private func performRehydration() {
        rehydrateOutput = GhostMappingStore.shared.rehydrate(rehydrateInput)
        rehydrateTokenCount = GhostMappingStore.shared.rehydrationCount(in: rehydrateInput)
    }

    // MARK: - Empty State

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

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if editorMode == .rehydrate {
                    sidebarRehydrateInfo
                } else {
                    sidebarScore
                    Divider()
                    sidebarPIIBreakdown
                }
                Divider()
                sidebarActions
                Spacer()
                sidebarHelp
            }
            .padding(16)
        }
        .background(GhostTheme.sidebarBackground)
    }

    // MARK: - Sidebar: Rehydrate Info

    private var sidebarRehydrateInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rehydrate")
                .font(.caption.bold())
                .foregroundStyle(GhostTheme.secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: 6) {
                Label("\(GhostMappingStore.shared.count) tokens stored", systemImage: "key.fill")
                    .font(.callout)

                Label("\(rehydrateTokenCount) found in text", systemImage: "magnifyingglass")
                    .font(.callout)
                    .foregroundStyle(rehydrateTokenCount > 0 ? GhostTheme.green : GhostTheme.secondaryText)
            }

            Divider()

            Text("How it works")
                .font(.caption.bold())
                .foregroundStyle(GhostTheme.secondaryText)

            VStack(alignment: .leading, spacing: 8) {
                flowStep(num: "1", text: "Ghost your text (Ghost tab)")
                flowStep(num: "2", text: "Paste safe text into LLM")
                flowStep(num: "3", text: "Copy LLM response here")
                flowStep(num: "4", text: "Tokens get replaced back")
            }

            Divider()

            // Token list
            if !rehydrateInput.isEmpty {
                let tokens = GhostMappingStore.shared.findTokens(in: rehydrateInput)
                if !tokens.isEmpty {
                    Text("Matched Tokens")
                        .font(.caption.bold())
                        .foregroundStyle(GhostTheme.secondaryText)

                    ForEach(tokens) { mapping in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(GhostTheme.highlightColor(for: mapping.type))
                                .frame(width: 12, height: 12)

                            VStack(alignment: .leading, spacing: 0) {
                                Text(mapping.token)
                                    .font(.caption2.monospaced().bold())
                                    .foregroundStyle(GhostTheme.purple)
                                Text("→ " + mapping.originalValue.prefix(20) + (mapping.originalValue.count > 20 ? "..." : ""))
                                    .font(.caption2)
                                    .foregroundStyle(GhostTheme.secondaryText)
                            }
                        }
                    }
                }
            }
        }
    }

    private func flowStep(num: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.caption2.bold())
                .frame(width: 18, height: 18)
                .background(GhostTheme.purple.opacity(0.15))
                .clipShape(Circle())
                .foregroundStyle(GhostTheme.purple)
            Text(text)
                .font(.caption)
                .foregroundStyle(GhostTheme.secondaryText)
        }
    }

    // MARK: - Sidebar: Score

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
        case 100:      return "Clean"
        case 90..<100: return "Safe"
        case 70..<90:  return "Caution"
        default:       return "Unsafe"
        }
    }

    // MARK: - Sidebar: PII Breakdown

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
                        onToggle: { toggleAllOfType(group.type) }
                    )
                    .onHover { isHovered in
                        hoveredType = isHovered ? group.type : nil
                    }
                }
            }
        }
    }

    // MARK: - Sidebar: Actions

    private var sidebarActions: some View {
        VStack(spacing: 8) {
            if editorMode == .rehydrate {
                Button {
                    ClipboardManager.shared.writeText(rehydrateOutput)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copied!" : "Copy Rehydrated Text", systemImage: copied ? "checkmark" : "doc.on.clipboard.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(copied ? GhostTheme.green : GhostTheme.purple)
                .controlSize(.regular)
                .disabled(rehydrateOutput.isEmpty)
                .animation(.easeInOut(duration: 0.2), value: copied)

                Button {
                    GhostMappingStore.shared.clearAll()
                    performRehydration()
                } label: {
                    Label("Clear Token History", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            } else {
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
    }

    // MARK: - Sidebar: Help

    private var sidebarHelp: some View {
        VStack(alignment: .leading, spacing: 4) {
            if editorMode == .rehydrate {
                Text("Paste the AI response above.")
                    .font(.caption)
                    .foregroundStyle(GhostTheme.secondaryText)
                Text("[GHOST_X] tokens will be restored.")
                    .font(.caption)
                    .foregroundStyle(GhostTheme.secondaryText)
            } else {
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
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            if editorMode == .rehydrate {
                Text("\(rehydrateTokenCount) token\(rehydrateTokenCount == 1 ? "" : "s") replaced")
                    .font(.caption)
                    .foregroundStyle(GhostTheme.tertiaryText)
            } else {
                Text("\(originalText.count) chars · \(originalText.split(separator: " ").count) words")
                    .font(.caption)
                    .foregroundStyle(GhostTheme.tertiaryText)
            }

            Spacer()

            Button("Cancel") {
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut(.escape, modifiers: [])

            if editorMode == .rehydrate {
                Button {
                    ClipboardManager.shared.writeText(rehydrateOutput)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.clipboard.fill")
                        Text(copied ? "Copied!" : "Copy Rehydrated")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(copied ? GhostTheme.green : GhostTheme.purple)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(rehydrateOutput.isEmpty)
                .animation(.easeInOut(duration: 0.2), value: copied)
            } else {
                Button {
                    let output = detector.ghostedText
                    onApply(output)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
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

// MARK: - Rehydrated Text View (highlights replaced tokens)

struct RehydratedTextView: NSViewRepresentable {
    let originalText: String
    let rehydratedText: String
    let mappings: [GhostMapping]

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = GhostTheme.editorFont
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.backgroundColor = .textBackgroundColor
        applyStyledText(to: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        applyStyledText(to: textView)
    }

    private func applyStyledText(to textView: NSTextView) {
        let attributed = NSMutableAttributedString(
            string: rehydratedText,
            attributes: [
                .font: GhostTheme.editorFont,
                .foregroundColor: NSColor.labelColor,
            ]
        )

        // Highlight restored values with a green background
        for mapping in mappings {
            let value = mapping.originalValue
            var searchRange = rehydratedText.startIndex..<rehydratedText.endIndex
            while let range = rehydratedText.range(of: value, range: searchRange) {
                let nsRange = NSRange(range, in: rehydratedText)
                attributed.addAttributes([
                    .backgroundColor: NSColor.systemGreen.withAlphaComponent(0.2),
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: NSColor.systemGreen.withAlphaComponent(0.5),
                ], range: nsRange)
                searchRange = range.upperBound..<rehydratedText.endIndex
            }
        }

        textView.textStorage?.setAttributedString(attributed)
    }
}
