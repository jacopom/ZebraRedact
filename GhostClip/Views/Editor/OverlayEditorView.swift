import SwiftUI

/// The main editor overlay: split-pane with Original (left), Toolbar (center), Ghosted Preview (right).
struct OverlayEditorView: View {
    @StateObject private var detector = PIIDetector()
    @State private var originalText = ""
    @State private var showSettings = false
    @Environment(\.dismiss) private var dismiss

    let initialText: String
    let onApply: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            headerBar
                .padding(.horizontal, 20)
                .padding(.top, 16)

            Divider().padding(.top, 8)

            // MARK: - Editor Panes
            HStack(spacing: 0) {
                // Left: Original text
                originalPane
                    .frame(maxWidth: .infinity)

                // Center: Toolbar
                toolbarPane
                    .frame(width: 160)

                // Right: Ghosted preview
                previewPane
                    .frame(maxWidth: .infinity)
            }
            .padding(16)

            Divider()

            // MARK: - Footer
            footerBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(
            minWidth: GhostClipConstants.Overlay.minWidth,
            minHeight: GhostClipConstants.Overlay.minHeight
        )
        .background(GhostTheme.panelBackground)
        .onAppear {
            originalText = initialText
            detector.scan(text: originalText)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "theatermasks.fill")
                    .foregroundStyle(GhostTheme.purple)
                    .font(.title2)
                Text("GhostClip")
                    .font(GhostTheme.titleFont)
                    .foregroundStyle(GhostTheme.purple)
            }

            Spacer()

            GhostScoreBadge(score: detector.privacyScore, method: detector.detectionMethod)

            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showSettings) {
                SettingsView()
                    .frame(width: 400, height: 500)
            }
        }
    }

    // MARK: - Original Pane

    private var originalPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Original")
                .font(GhostTheme.headlineFont)
                .foregroundStyle(GhostTheme.secondaryText)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $originalText)
                    .font(GhostTheme.codeFont)
                    .scrollContentBackground(.hidden)
                    .background(GhostTheme.editorBackground)
                    .border(Color.gray.opacity(0.2), width: 1)
                    .onChange(of: originalText) {
                        detector.scan(text: originalText)
                    }

                // PII highlight overlays
                highlightOverlay
            }

            Text("\(detector.detectedItems.count) PII item(s) detected")
                .font(.caption)
                .foregroundStyle(GhostTheme.secondaryText)
        }
    }

    // MARK: - Highlight Overlay (simplified)

    private var highlightOverlay: some View {
        // PII items listed as chips below the editor
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(detector.detectedItems) { item in
                    Button {
                        detector.toggleItem(item)
                        detector.remask(originalText: originalText)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: item.type.icon)
                                .font(.caption2)
                            Text(item.originalText.prefix(20) + (item.originalText.count > 20 ? "..." : ""))
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            item.isMasked
                                ? GhostTheme.red.opacity(0.2)
                                : Color.gray.opacity(0.1)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(item.isMasked ? "\(item.type.rawValue) – Click to unmask" : "\(item.type.rawValue) – Click to mask")
                }
            }
        }
        .padding(.top, 4)
        .allowsHitTesting(true)
        .frame(maxWidth: .infinity, maxHeight: 30, alignment: .topLeading)
        .offset(y: -30) // position above editor
        .opacity(detector.detectedItems.isEmpty ? 0 : 1)
    }

    // MARK: - Toolbar Pane

    private var toolbarPane: some View {
        VStack(spacing: 16) {
            Spacer()

            Button {
                detector.maskAll()
                detector.remask(originalText: originalText)
            } label: {
                Label("Ghost All", systemImage: "theatermasks.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(GhostTheme.purple)
            .controlSize(.large)

            Button {
                detector.unmaskAll()
                detector.remask(originalText: originalText)
            } label: {
                Label("Reveal All", systemImage: "eye.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Detected")
                    .font(.caption.bold())
                    .foregroundStyle(GhostTheme.secondaryText)

                ForEach(PIIType.allCases) { type in
                    let count = detector.detectedItems.filter { $0.type == type }.count
                    if count > 0 {
                        HStack {
                            Image(systemName: type.icon)
                                .font(.caption2)
                                .frame(width: 14)
                            Text("\(type.rawValue): \(count)")
                                .font(.caption)
                        }
                        .foregroundStyle(GhostTheme.primaryText)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Preview Pane

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ghosted Preview")
                .font(GhostTheme.headlineFont)
                .foregroundStyle(GhostTheme.secondaryText)

            ScrollView {
                Text(detector.ghostedText)
                    .font(GhostTheme.codeFont)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(8)
            }
            .background(GhostTheme.editorBackground)
            .border(Color.gray.opacity(0.2), width: 1)

            Text("Note: [GHOST_X] tokens are safe to share. No inference possible.")
                .font(.caption)
                .foregroundStyle(GhostTheme.secondaryText)
                .italic()
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Button {
                onApply(detector.ghostedText)
                dismiss()
            } label: {
                Label("Copy Safe Text", systemImage: "doc.on.clipboard.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(GhostTheme.purple)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }
}

#Preview {
    OverlayEditorView(
        initialText: "Contact me at john@example.com or call 555-123-4567. API key: sk-proj1234567890abcdefghij",
        onApply: { print($0) }
    )
}
