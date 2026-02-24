import SwiftUI
import AppKit

// MARK: - Tokenizable NSTextView Subclass

/// NSTextView subclass that adds right-click "Tag as PII…" context menu for selected text
final class TokenizableTextView: NSTextView {
    var onTokenizeSelection: ((String) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard selectedRange().length > 0 else { return super.menu(for: event) }
        let menu = NSMenu()
        let tagItem = NSMenuItem(
            title: "Tag as PII…",
            action: #selector(tagSelection),
            keyEquivalent: ""
        )
        tagItem.target = self
        menu.addItem(tagItem)
        return menu
    }

    @objc private func tagSelection() {
        let text = (string as NSString).substring(with: selectedRange())
        onTokenizeSelection?(text)
    }
}

// MARK: - ClickableTokenTextView

/// NSTextView wrapper with clickable token links and right-click PII tagging
struct ClickableTokenTextView: NSViewRepresentable {
    let text: String
    let items: [PIIItem]
    let onTokenClick: (PIIItem) -> Void
    var onTextSelection: ((String) -> Void)? = nil
    /// Maps item IDs to the text actually placed in the output (varies by redaction mode)
    var appliedTexts: [UUID: String] = [:]

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = TokenizableTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = CGSize(width: 12, height: 12)
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.controlBackgroundColor
        textView.delegate = context.coordinator
        textView.isAutomaticLinkDetectionEnabled = false
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? TokenizableTextView else { return }

        context.coordinator.items = items
        context.coordinator.onTokenClick = onTokenClick
        textView.onTokenizeSelection = onTextSelection

        let attributedString = buildAttributedString(appliedTexts: appliedTexts)
        textView.textStorage?.setAttributedString(attributedString)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items, onTokenClick: onTokenClick)
    }

    private func buildAttributedString(appliedTexts: [UUID: String]) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text)

        // Default attributes
        result.addAttributes([
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor
        ], range: NSRange(location: 0, length: result.length))

        // Style tokens and make them clickable
        // Track used positions to avoid duplicate links
        var usedRanges: Set<Int> = []

        for item in items {
            // Search for the text that was actually placed in the output for this item
            let searchText = appliedTexts[item.id] ?? item.token
            var searchRange = NSRange(location: 0, length: (text as NSString).length)

            while searchRange.location < (text as NSString).length {
                let foundRange = (text as NSString).range(of: searchText, range: searchRange)
                guard foundRange.location != NSNotFound else { break }

                if !usedRanges.contains(foundRange.location) {
                    // Pastel background — use dark foreground so it's legible in both
                    // light and dark mode (the pastel chips are always light-toned).
                    let accentColor = NSColor(item.type.highlightColor)
                    let bgColor = accentColor.withAlphaComponent(0.90)
                    let textColor = NSColor(white: 0.08, alpha: 1.0)
                    result.addAttributes([
                        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                        .foregroundColor: textColor,
                        .backgroundColor: bgColor,
                        .link: item.id.uuidString,
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .underlineColor: accentColor
                    ], range: foundRange)

                    usedRanges.insert(foundRange.location)
                    break
                }

                searchRange.location = foundRange.location + foundRange.length
                searchRange.length = (text as NSString).length - searchRange.location
            }
        }

        return result
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var items: [PIIItem]
        var onTokenClick: (PIIItem) -> Void

        init(items: [PIIItem], onTokenClick: @escaping (PIIItem) -> Void) {
            self.items = items
            self.onTokenClick = onTokenClick
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let uuidString = link as? String,
                  let uuid = UUID(uuidString: uuidString),
                  let item = items.first(where: { $0.id == uuid }) else {
                return false
            }
            onTokenClick(item)
            return true
        }
    }
}
