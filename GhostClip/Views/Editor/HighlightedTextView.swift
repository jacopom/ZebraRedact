import SwiftUI
import AppKit

/// NSTextView-backed view that renders text with colored PII highlights (Hemingway-style).
struct HighlightedTextView: NSViewRepresentable {
    @Binding var text: String
    let piiItems: [PIIItem]
    let isEditable: Bool
    var onTextChange: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindPanel = true
        textView.font = GhostTheme.editorFont
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.backgroundColor = .textBackgroundColor

        textView.string = text
        applyHighlights(to: textView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        // Only update text if it changed externally
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selection)
        }

        applyHighlights(to: textView)
    }

    private func applyHighlights(to textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)

        // Reset to base style
        textStorage.beginEditing()
        textStorage.removeAttribute(.backgroundColor, range: fullRange)
        textStorage.addAttribute(.font, value: GhostTheme.editorFont, range: fullRange)
        textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)

        // Apply highlights for each PII item
        for item in piiItems where item.isMasked {
            let nsRange = NSRange(item.range, in: text)
            guard nsRange.location != NSNotFound,
                  nsRange.location + nsRange.length <= textStorage.length else { continue }

            let bgColor = GhostTheme.nsHighlightColor(for: item.type)
            textStorage.addAttribute(.backgroundColor, value: bgColor, range: nsRange)
        }

        textStorage.endEditing()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightedTextView

        init(_ parent: HighlightedTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onTextChange?(textView.string)
        }
    }
}

/// A read-only text view that shows the ghosted output with tokens styled.
struct GhostedPreviewView: NSViewRepresentable {
    let text: String

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
            string: text,
            attributes: [
                .font: GhostTheme.editorFont,
                .foregroundColor: NSColor.labelColor,
            ]
        )

        // Style [GHOST_XXXX] tokens with a pill-like background
        let pattern = #"\[GHOST_[A-Z0-9]{4}\]"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                attributed.addAttributes([
                    .backgroundColor: NSColor(GhostTheme.purple).withAlphaComponent(0.2),
                    .foregroundColor: NSColor(GhostTheme.purple),
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
                ], range: match.range)
            }
        }

        textView.textStorage?.setAttributedString(attributed)
    }
}

// Utility to convert Range<String.Index> to NSRange
private extension Range where Bound == String.Index {
    func nsRange(in string: String) -> NSRange? {
        return NSRange(self, in: string)
    }
}
