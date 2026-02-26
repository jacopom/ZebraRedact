import SwiftUI
import AppKit

// MARK: - Tokenizable NSTextView Subclass

/// NSTextView subclass that draws spoiler-style censored boxes over tokens,
/// reveals them on hover, and provides a right-click submenu for one-click PII tagging.
final class TokenizableTextView: NSTextView {
    var onManualTag: ((NSRange, PIIType) -> Void)?

    // Spoiler overlay data: (characterRange, accentColor)
    var tokenRanges: [(NSRange, NSColor)] = [] {
        didSet { needsDisplay = true }
    }
    private var hoveredRange: NSRange? = nil

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        guard selectedRange().length > 0 else { return super.menu(for: event) }
        let menu = NSMenu()
        let range = selectedRange()
        for piiType in PIIType.allCases {
            let item = NSMenuItem(
                title: piiType.rawValue,
                action: #selector(tagSelectionAs(_:)),
                keyEquivalent: ""
            )
            item.image = NSImage(systemSymbolName: piiType.icon, accessibilityDescription: nil)
            item.target = self
            item.representedObject = (range, piiType)
            menu.addItem(item)
        }
        return menu
    }

    @objc private func tagSelectionAs(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? (NSRange, PIIType) else { return }
        onManualTag?(pair.0, pair.1)
    }

    // MARK: - Hover tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        let hit = hitTestToken(at: point)
        if hit?.location != hoveredRange?.location || hit?.length != hoveredRange?.length {
            hoveredRange = hit
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if hoveredRange != nil {
            hoveredRange = nil
            needsDisplay = true
        }
    }

    private func hitTestToken(at point: NSPoint) -> NSRange? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let adjusted = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        let glyphIndex = lm.glyphIndex(for: adjusted, in: tc)
        guard glyphIndex < lm.numberOfGlyphs else { return nil }
        let charIndex = lm.characterIndexForGlyph(at: glyphIndex)
        for (range, _) in tokenRanges {
            if NSLocationInRange(charIndex, range) { return range }
        }
        return nil
    }

    // MARK: - Spoiler overlay draw

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawSpoilerOverlays()
    }

    private func drawSpoilerOverlays() {
        guard let lm = layoutManager, let tc = textContainer else { return }
        let inset = NSPoint(x: textContainerInset.width, y: textContainerInset.height)

        for (range, color) in tokenRanges {
            let glyphRange = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rects: [NSRect] = []
            lm.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, lineGlyphRange, _ in
                // Intersect the token's glyphs with this line's glyphs for accurate x/width
                let intersection = NSIntersectionRange(glyphRange, lineGlyphRange)
                guard intersection.length > 0 else { return }
                let tokenBounds = lm.boundingRect(forGlyphRange: intersection, in: tc)
                guard tokenBounds.width > 0 else { return }
                // Use usedRect for consistent bar height; tokenBounds for x/width
                let r = NSRect(x: tokenBounds.minX, y: usedRect.minY,
                               width: tokenBounds.width, height: usedRect.height)
                rects.append(r)
            }
            for rect in rects {
                let box = rect.offsetBy(dx: inset.x, dy: inset.y).insetBy(dx: -1, dy: 3)
                let pill = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)

                let isHovered = hoveredRange.map {
                    NSIntersectionRange($0, range).length > 0
                } ?? false

                let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

                if isHovered {
                    // Semi-transparent accent background
                    color.withAlphaComponent(0.20).setFill()
                    pill.fill()
                    // Accent border
                    color.withAlphaComponent(0.60).setStroke()
                    pill.lineWidth = 1
                    pill.stroke()

                    let tokenText = (string as NSString).substring(with: range)
                    // Dark mode → white text; light mode → accent color text
                    let textColor: NSColor = isDark ? .white : color
                    let textAttrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
                        .foregroundColor: textColor
                    ]
                    let textSize = (tokenText as NSString).size(withAttributes: textAttrs)
                    let textRect = NSRect(
                        x: box.minX + (box.width - textSize.width) / 2,
                        y: box.minY + (box.height - textSize.height) / 2,
                        width: textSize.width,
                        height: textSize.height
                    )
                    (tokenText as NSString).draw(in: textRect, withAttributes: textAttrs)
                } else {
                    // Solid bar: white in dark mode, black in light mode
                    (isDark ? NSColor.white : NSColor.black).setFill()
                    pill.fill()
                }
            }
        }
    }
}

// MARK: - ClickableTokenTextView

/// NSTextView wrapper with clickable token links, spoiler overlay, and right-click PII tagging
struct ClickableTokenTextView: NSViewRepresentable {
    let text: String
    let items: [PIIItem]
    let onTokenClick: (PIIItem) -> Void
    var onManualTag: ((NSRange, PIIType) -> Void)? = nil
    /// Maps item IDs to the text actually placed in the output
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
        // Disable NSTextView's default link styling so our .foregroundColor = .clear is respected
        textView.linkTextAttributes = [:]
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
        textView.onManualTag = onManualTag

        let attributedString = buildAttributedString(appliedTexts: appliedTexts)
        textView.textStorage?.setAttributedString(attributedString)

        // Populate tokenRanges for spoiler overlay
        textView.tokenRanges = collectTokenRanges(in: attributedString, appliedTexts: appliedTexts)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items, onTokenClick: onTokenClick)
    }

    private func buildAttributedString(appliedTexts: [UUID: String]) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text)

        // Default attributes
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 6
        result.addAttributes([
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: para
        ], range: NSRange(location: 0, length: result.length))

        var usedRanges: Set<Int> = []

        for item in items {
            let searchText = appliedTexts[item.id] ?? item.token
            var searchRange = NSRange(location: 0, length: (text as NSString).length)

            while searchRange.location < (text as NSString).length {
                let foundRange = (text as NSString).range(of: searchText, range: searchRange)
                guard foundRange.location != NSNotFound else { break }

                if !usedRanges.contains(foundRange.location) {
                    let accentColor = NSColor(item.type.highlightColor)
                    // Make text invisible — spoiler overlay draws over it
                    result.addAttributes([
                        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                        .foregroundColor: NSColor.clear,
                        .link: item.id.uuidString
                    ], range: foundRange)

                    usedRanges.insert(foundRange.location)
                    _ = accentColor // suppress unused warning
                    break
                }

                searchRange.location = foundRange.location + foundRange.length
                searchRange.length = (text as NSString).length - searchRange.location
            }
        }

        return result
    }

    /// Build the tokenRanges array for the spoiler overlay.
    private func collectTokenRanges(in attrStr: NSAttributedString,
                                     appliedTexts: [UUID: String]) -> [(NSRange, NSColor)] {
        var result: [(NSRange, NSColor)] = []
        var usedRanges: Set<Int> = []

        for item in items {
            let searchText = appliedTexts[item.id] ?? item.token
            var searchRange = NSRange(location: 0, length: (text as NSString).length)

            while searchRange.location < (text as NSString).length {
                let foundRange = (text as NSString).range(of: searchText, range: searchRange)
                guard foundRange.location != NSNotFound else { break }

                if !usedRanges.contains(foundRange.location) {
                    let accentColor = NSColor(item.type.highlightColor)
                    result.append((foundRange, accentColor))
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
