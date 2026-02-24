import SwiftUI

struct RehydrateSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rehydrateInput = ""
    @State private var rehydrateOutput = ""
    @State private var rehydrateTokenCount = 0
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.title2)
                    .foregroundStyle(ZebraTheme.green)

                Text("Rehydrate LLM Response")
                    .font(ZebraTheme.titleFont)
                    .foregroundStyle(ZebraTheme.primaryText)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(ZebraTheme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            // Main content
            HStack(spacing: 0) {
                // Left: Input area
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("LLM Response (with tokens)", systemImage: "text.bubble")
                            .font(.caption.bold())
                            .foregroundStyle(ZebraTheme.secondaryText)
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

                    TextEditor(text: $rehydrateInput)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(ZebraTheme.panelBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(ZebraTheme.secondaryText.opacity(0.2), lineWidth: 1)
                        )
                        .onChange(of: rehydrateInput) {
                            performRehydration()
                        }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // Right: Output area
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Rehydrated Output", systemImage: "checkmark.circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(ZebraTheme.green)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        if rehydrateTokenCount > 0 {
                            Text("\(rehydrateTokenCount) token\(rehydrateTokenCount == 1 ? "" : "s") restored")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(ZebraTheme.green.opacity(0.15))
                                .foregroundStyle(ZebraTheme.green)
                                .clipShape(Capsule())
                        }

                        Spacer()
                    }

                    RehydratedTextView(
                        originalText: rehydrateInput,
                        rehydratedText: rehydrateOutput,
                        mappings: TokenMappingStore.shared.findTokens(in: rehydrateInput)
                    )
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ZebraTheme.green.opacity(0.02))
            }

            Divider()

            // Info section
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(TokenMappingStore.shared.count) tokens stored", systemImage: "key.fill")
                        .font(.caption)
                        .foregroundStyle(ZebraTheme.secondaryText)

                    Label("\(rehydrateTokenCount) found in text", systemImage: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(rehydrateTokenCount > 0 ? ZebraTheme.green : ZebraTheme.tertiaryText)
                }

                Spacer()

                // Token list preview
                if !rehydrateInput.isEmpty {
                    let tokens = TokenMappingStore.shared.findTokens(in: rehydrateInput)
                    if !tokens.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(tokens.prefix(3)) { mapping in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(ZebraTheme.highlightColor(for: mapping.type))
                                        .frame(width: 8, height: 8)
                                    Text(mapping.token)
                                        .font(.caption2.monospaced().bold())
                                        .foregroundStyle(ZebraTheme.purple)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(ZebraTheme.highlightColor(for: mapping.type).opacity(0.15))
                                )
                            }
                            if tokens.count > 3 {
                                Text("+\(tokens.count - 3) more")
                                    .font(.caption2)
                                    .foregroundStyle(ZebraTheme.tertiaryText)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(ZebraTheme.sidebarBackground)

            Divider()

            // Footer actions
            HStack {
                Button {
                    TokenMappingStore.shared.clearAll()
                    performRehydration()
                } label: {
                    Label("Clear History", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

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
                .tint(copied ? ZebraTheme.green : ZebraTheme.purple)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(rehydrateOutput.isEmpty)
                .animation(.easeInOut(duration: 0.2), value: copied)
            }
            .padding(20)
        }
        .frame(width: 900, height: 600)
        .background(ZebraTheme.panelBackground)
    }

    private func performRehydration() {
        rehydrateOutput = TokenMappingStore.shared.rehydrate(rehydrateInput)
        rehydrateTokenCount = TokenMappingStore.shared.rehydrationCount(in: rehydrateInput)
    }
}

// MARK: - Rehydrated Text View (highlights replaced tokens)

struct RehydratedTextView: NSViewRepresentable {
    let originalText: String
    let rehydratedText: String
    let mappings: [TokenMapping]

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = ZebraTheme.editorFont
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
                .font: ZebraTheme.editorFont,
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
