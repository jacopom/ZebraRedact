import SwiftUI
import AppKit

/// NSTextView wrapper with clickable token links
struct ClickableTokenTextView: NSViewRepresentable {
    let text: String
    let items: [PIIItem]
    let onTokenClick: (PIIItem) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        // Configure text view
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = CGSize(width: 12, height: 12)
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.controlBackgroundColor
        textView.delegate = context.coordinator

        // Enable link detection
        textView.isAutomaticLinkDetectionEnabled = false

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        context.coordinator.items = items
        context.coordinator.onTokenClick = onTokenClick

        // Build attributed string with clickable tokens
        let attributedString = buildAttributedString()
        textView.textStorage?.setAttributedString(attributedString)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items, onTokenClick: onTokenClick)
    }

    private func buildAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString(string: text)

        // Default attributes
        let defaultFont = NSFont.systemFont(ofSize: 15)
        let defaultColor = NSColor.labelColor
        result.addAttributes([
            .font: defaultFont,
            .foregroundColor: defaultColor
        ], range: NSRange(location: 0, length: result.length))

        // Style tokens and make them clickable
        for item in items {
            let tokenRange = (text as NSString).range(of: item.ghostToken)
            guard tokenRange.location != NSNotFound else { continue }

            // Token styling
            let tokenFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
            let tokenColor = NSColor.labelColor
            let backgroundColor = nsColor(from: item.type.highlightColor)

            result.addAttributes([
                .font: tokenFont,
                .foregroundColor: tokenColor,
                .backgroundColor: backgroundColor,
                .link: item.id.uuidString, // Use UUID as link
                .underlineStyle: 0 // No underline
            ], range: tokenRange)
        }

        return result
    }

    private func nsColor(from color: Color) -> NSColor {
        // Convert SwiftUI Color to NSColor
        // This is a simplified conversion
        switch color.description {
        default:
            // Extract color components via NSColor
            return NSColor(color)
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var items: [PIIItem]
        var onTokenClick: (PIIItem) -> Void

        init(items: [PIIItem], onTokenClick: @escaping (PIIItem) -> Void) {
            self.items = items
            self.onTokenClick = onTokenClick
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            // Link is the UUID string we stored
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
