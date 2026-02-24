import SwiftUI
import AppKit

/// NSTextView-backed view that renders text with colored PII highlights (Hemingway-style).
struct HighlightedTextView: NSViewRepresentable {
    @Binding var text: String
    let piiItems: [PIIItem]
    let isEditable: Bool
    var onTextChange: ((String) -> Void)?
    var onManualTag: ((NSRange, PIIType) -> Void)?

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
        textView.font = ZebraTheme.editorFont
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
        textStorage.addAttribute(.font, value: ZebraTheme.editorFont, range: fullRange)
        textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)

        // Apply highlights for each PII item
        for item in piiItems where item.isMasked {
            let nsRange = NSRange(item.range, in: text)
            guard nsRange.location != NSNotFound,
                  nsRange.location + nsRange.length <= textStorage.length else { continue }

            let bgColor = ZebraTheme.nsHighlightColor(for: item.type)
            textStorage.addAttribute(.backgroundColor, value: bgColor, range: nsRange)

            // Add dotted underline for manual tags
            if item.isManual {
                textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.single.rawValue, range: nsRange)
                textStorage.addAttribute(.underlineColor, value: NSColor(item.type.highlightColor.opacity(0.8)), range: nsRange)
            }
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

        // MARK: - Context Menu for Manual Tagging

        func textView(_ textView: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            let selectedRange = textView.selectedRange()

            // Only add "Tag as PII" if text is selected
            guard selectedRange.length > 0 else { return menu }

            menu.addItem(NSMenuItem.separator())

            let tagMenuItem = NSMenuItem(title: "Tag as PII", action: nil, keyEquivalent: "")
            let submenu = NSMenu()

            for piiType in PIIType.allCases {
                let item = NSMenuItem(
                    title: piiType.rawValue,
                    action: #selector(tagSelection(_:)),
                    keyEquivalent: ""
                )
                item.image = NSImage(systemSymbolName: piiType.icon, accessibilityDescription: nil)
                item.target = self
                item.representedObject = (selectedRange, piiType)
                submenu.addItem(item)
            }

            tagMenuItem.submenu = submenu
            menu.addItem(tagMenuItem)
            return menu
        }

        @objc func tagSelection(_ sender: NSMenuItem) {
            guard let (nsRange, piiType) = sender.representedObject as? (NSRange, PIIType) else { return }
            parent.onManualTag?(nsRange, piiType)
        }
    }
}

/// A read-only text view that shows the ghosted output with tokens styled.
struct RedactedPreviewView: NSViewRepresentable {
    let text: String

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
            string: text,
            attributes: [
                .font: ZebraTheme.editorFont,
                .foregroundColor: NSColor.labelColor,
            ]
        )

        // Style [TOKEN] tokens with a pill-like background
        let pattern = #"\[[A-Z]+_[A-Z0-9]{4}\]"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                attributed.addAttributes([
                    .backgroundColor: NSColor(ZebraTheme.purple).withAlphaComponent(0.2),
                    .foregroundColor: NSColor(ZebraTheme.purple),
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
