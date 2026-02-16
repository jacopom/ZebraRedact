import SwiftUI
import AppKit

/// NSTextView wrapper with clickable token links and context menu
struct ClickableTokenTextView: NSViewRepresentable {
    let text: String
    let items: [PIIItem]
    @Binding var inputText: String
    @Binding var selectedItemId: UUID?
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
        context.coordinator.selectedItemId = $selectedItemId
        context.coordinator.detector = detector

        // Build attributed string with clickable tokens
        let attributedString = buildAttributedString()
        textView.textStorage?.setAttributedString(attributedString)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items, inputText: $inputText, selectedItemId: $selectedItemId, detector: detector)
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
        var selectedItemId: Binding<UUID?>
        var detector: PIIDetector

        init(items: [PIIItem], inputText: Binding<String>, selectedItemId: Binding<UUID?>, detector: PIIDetector) {
            self.items = items
            self.inputText = inputText
            self.selectedItemId = selectedItemId
            self.detector = detector
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            // Link is the UUID string we stored
            guard let uuidString = link as? String,
                  let uuid = UUID(uuidString: uuidString),
                  let item = items.first(where: { $0.id == uuid }) else {
                return false
            }

            // Set selected item for highlighting in input
            selectedItemId.wrappedValue = item.id

            // Show context menu at cursor position
            showContextMenu(for: item, in: textView)
            return true
        }

        private func showContextMenu(for item: PIIItem, in textView: NSTextView) {
            let menu = NSMenu()
            menu.autoenablesItems = false

            // Add header showing original text
            let header = NSMenuItem(title: "Change '\(item.originalText)' to:", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(NSMenuItem.separator())

            // Add menu items for each alternative with descriptions
            for alternative in item.alternatives {
                let menuItem = NSMenuItem(
                    title: alternative.text,
                    action: #selector(selectAlternative(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = (item, alternative)
                menuItem.isEnabled = true

                // Show checkmark for selected alternative
                if alternative.id == item.selectedAlternativeId {
                    menuItem.state = .on
                }

                // Create attributed title with description
                let attrString = NSMutableAttributedString()
                attrString.append(NSAttributedString(string: alternative.text, attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .medium)
                ]))
                attrString.append(NSAttributedString(string: "\n", attributes: [:]))
                attrString.append(NSAttributedString(string: alternative.description, attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]))
                menuItem.attributedTitle = attrString

                menu.addItem(menuItem)
            }

            // Show menu at click position using current mouse location
            let mouseLocation = NSEvent.mouseLocation
            let windowPoint = textView.window?.convertPoint(fromScreen: mouseLocation) ?? .zero
            let viewPoint = textView.convert(windowPoint, from: nil)

            menu.popUp(positioning: nil, at: viewPoint, in: textView)
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
