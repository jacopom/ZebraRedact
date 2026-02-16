import SwiftUI
import AppKit

/// NSTextView wrapper with clickable token links and context menu
struct ClickableTokenTextView: NSViewRepresentable {
    let text: String
    let items: [PIIItem]
    @Binding var inputText: String
    let detector: PIIDetector

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
        context.coordinator.inputText = $inputText
        context.coordinator.detector = detector

        // Build attributed string with clickable tokens
        let attributedString = buildAttributedString()
        textView.textStorage?.setAttributedString(attributedString)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items, inputText: $inputText, detector: detector)
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
        var inputText: Binding<String>
        var detector: PIIDetector

        init(items: [PIIItem], inputText: Binding<String>, detector: PIIDetector) {
            self.items = items
            self.inputText = inputText
            self.detector = detector
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            // Link is the UUID string we stored
            guard let uuidString = link as? String,
                  let uuid = UUID(uuidString: uuidString),
                  let item = items.first(where: { $0.id == uuid }) else {
                return false
            }

            // Show context menu at cursor position
            showContextMenu(for: item, in: textView)
            return true
        }

        private func showContextMenu(for item: PIIItem, in textView: NSTextView) {
            let menu = NSMenu()

            // Add menu items for each alternative
            for alternative in item.alternatives {
                let menuItem = NSMenuItem(
                    title: alternative.text,
                    action: #selector(selectAlternative(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = (item, alternative)

                // Show checkmark for selected alternative
                if alternative.id == item.selectedAlternativeId {
                    menuItem.state = .on
                }

                // Add subtitle with strategy description
                menuItem.toolTip = alternative.description

                menu.addItem(menuItem)
            }

            // Show menu at mouse location
            if let event = NSApp.currentEvent {
                NSMenu.popUpContextMenu(menu, with: event, for: textView)
            }
        }

        @objc private func selectAlternative(_ sender: NSMenuItem) {
            guard let (item, alternative) = sender.representedObject as? (PIIItem, RedactionAlternative),
                  let index = detector.detectedItems.firstIndex(where: { $0.id == item.id }) else {
                return
            }

            // Update selected alternative
            detector.detectedItems[index].selectedAlternativeId = alternative.id
            // Regenerate ghosted text
            detector.scan(text: inputText.wrappedValue)
        }
    }
}
