import Foundation
import Combine

// MARK: - DetectionMode

enum DetectionMode: String, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case manual    = "Manual"
    var id: String { rawValue }
}

// MARK: - Errors

enum PIIError: LocalizedError {
    case rangeOverlap
    case invalidRange
    case emptySelection

    var errorDescription: String? {
        switch self {
        case .rangeOverlap: return "This selection overlaps with existing PII item"
        case .invalidRange: return "Invalid text range selected"
        case .emptySelection: return "Please select text to tag"
        }
    }
}

// MARK: - PIIDetector

@MainActor
final class PIIDetector: ObservableObject {
    @Published var detectedItems: [PIIItem] = []
    @Published var redactedText: String = ""
    @Published var privacyScore: Int = 100
    @Published var isProcessing: Bool = false
    @Published var enabledCategories: Set<PIIType> = Set(PIIType.allCases)
    @Published var detectionMode: DetectionMode = .automatic
    /// Maps each item ID → the text actually placed in redactedText for that item
    @Published var appliedReplacements: [UUID: String] = [:]

    private let detector = NLTaggerDetector()

    // MARK: - Computed Properties

    /// Computed confidence assessment
    var confidenceAssessment: ConfidenceAssessment? {
        guard !detectedItems.isEmpty else { return nil }

        let wordCount = max(1.0, Double(redactedText.split(separator: " ").count))
        let redactionRatio = Double(detectedItems.count) / wordCount

        let taskCompletability = max(20, 100 - Int(redactionRatio * 200))
        let hallucinationRisk = min(80, Int(redactionRatio * 150))
        let coherence = max(30, 100 - Int(redactionRatio * 180))

        return ConfidenceAssessment(
            taskCompletability: taskCompletability,
            hallucinationRisk: hallucinationRisk,
            coherence: coherence
        )
    }

    // MARK: - Scan

    func scan(text: String) {
        isProcessing = true

        // Preserve manual tags across re-scans: save them before detection runs.
        let previousManualItems = detectedItems.filter { $0.isManual }

        // In manual mode skip auto-detection — only re-anchor existing manual tags.
        let filtered: [PIIItem]
        if detectionMode == .manual {
            filtered = []
        } else {
            let allItems = detector.detect(in: text)
            filtered = allItems.filter { enabledCategories.contains($0.type) }
        }

        // Re-anchor surviving manual items
        var preserved: [PIIItem] = []
        for manual in previousManualItems {
            guard let newRange = text.range(of: manual.originalText, options: .literal) else { continue }
            let overlaps = filtered.contains { s in
                newRange.lowerBound < s.range.upperBound && s.range.lowerBound < newRange.upperBound
            }
            guard !overlaps else { continue }
            preserved.append(manual.withRange(newRange))
        }

        let combined = (filtered + preserved)
            .sorted { $0.range.lowerBound < $1.range.lowerBound }

        Task {
            await applyMasking(to: text, newItems: combined)
            await MainActor.run {
                isProcessing = false
            }
        }
    }

    /// Switch detection mode. Switching to manual clears all auto-detected items;
    /// switching to automatic re-runs a full scan.
    func setDetectionMode(_ mode: DetectionMode, originalText: String) {
        detectionMode = mode
        if mode == .manual {
            let manualItems = detectedItems.filter { $0.isManual }
            detectedItems = manualItems
            let (text, applied) = buildMaskedText(from: originalText,
                                                   items: manualItems,
                                                   replacements: appliedReplacements)
            redactedText = text
            appliedReplacements = applied
            privacyScore = calculateScore(items: manualItems)
        } else {
            scan(text: originalText)
        }
    }

    private func applyMasking(to text: String, newItems: [PIIItem]) async {
        let items = newItems
        var result = text
        var applied: [UUID: String] = [:]

        for item in items.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) where item.isMasked {
            result.replaceSubrange(item.range, with: item.token)
            applied[item.id] = item.token
        }

        await MainActor.run {
            detectedItems = items
            redactedText = result
            appliedReplacements = applied
            privacyScore = calculateScore(items: items)
            for item in items where item.isMasked {
                let replacement = applied[item.id] ?? item.token
                TokenMappingStore.shared.store(token: replacement, original: item.originalText, type: item.type)
            }
        }
    }

    // MARK: - Remove Item (untokenize)

    /// Remove a PII item and rebuild the output text, restoring the original value.
    func removeItem(_ item: PIIItem, originalText: String) {
        appliedReplacements.removeValue(forKey: item.id)
        detectedItems.removeAll { $0.id == item.id }
        let (text, applied) = buildMaskedText(from: originalText,
                                              items: detectedItems,
                                              replacements: appliedReplacements)
        redactedText = text
        appliedReplacements = applied
        privacyScore = calculateScore(items: detectedItems)
    }

    // MARK: - Toggle Individual Items

    func toggleItem(_ item: PIIItem) {
        guard let idx = detectedItems.firstIndex(where: { $0.id == item.id }) else { return }
        detectedItems[idx].isMasked.toggle()
    }

    // MARK: - Re-mask After Toggling

    func remask(originalText: String) {
        let (text, applied) = buildMaskedText(from: originalText,
                                              items: detectedItems,
                                              replacements: appliedReplacements)
        redactedText = text
        appliedReplacements = applied
        privacyScore = calculateScore(items: detectedItems)
    }

    private func buildMaskedText(from originalText: String,
                                 items: [PIIItem],
                                 replacements: [UUID: String]) -> (text: String, applied: [UUID: String]) {
        let sorted = items
            .filter { $0.isMasked }
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
        var result = ""
        var applied: [UUID: String] = [:]
        var cursor = originalText.startIndex
        for item in sorted {
            guard item.range.lowerBound >= cursor,
                  item.range.upperBound <= originalText.endIndex else { continue }
            result += originalText[cursor..<item.range.lowerBound]
            let replacement = replacements[item.id] ?? item.token
            result += replacement
            applied[item.id] = replacement
            cursor = item.range.upperBound
        }
        result += originalText[cursor...]
        return (result, applied)
    }

    /// Change one item's replacement to a specific alternative, then rebuild.
    func applySelectedAlternative(_ alternative: RedactionAlternative,
                                  forItemId itemId: UUID,
                                  originalText: String) {
        guard let index = detectedItems.firstIndex(where: { $0.id == itemId }) else { return }
        detectedItems[index].selectedAlternativeId = alternative.id
        appliedReplacements[itemId] = alternative.text
        remask(originalText: originalText)
    }

    // MARK: - Retag (change type of existing item)

    @discardableResult
    func retagItem(_ item: PIIItem, as newType: PIIType, originalText: String) -> PIIItem? {
        guard let index = detectedItems.firstIndex(where: { $0.id == item.id }) else { return nil }
        let newAlts = PIIItem.generateAlternatives(for: newType, original: item.originalText)
        guard let firstAlt = newAlts.first else { return nil }

        let retagged = PIIItem(
            preservingId: item.id,
            type: newType,
            range: item.range,
            originalText: item.originalText,
            alternatives: newAlts,
            selectedAlternativeId: firstAlt.id,
            confidence: item.confidence,
            isMasked: item.isMasked,
            isManual: item.isManual
        )
        detectedItems[index] = retagged
        appliedReplacements[item.id] = firstAlt.text
        remask(originalText: originalText)
        TokenMappingStore.shared.store(token: firstAlt.text, original: item.originalText, type: newType)
        return retagged
    }

    // MARK: - Manual Tagging

    /// Maps an NSRange in redactedText back to a Range<String.Index> in the original inputText.
    /// If the selection overlaps a token, the boundaries snap to that token's input range.
    func inputRange(forRedactedNSRange nsRange: NSRange, inputText: String) -> Range<String.Index>? {
        guard nsRange.length > 0 else { return nil }

        let sorted = detectedItems
            .filter { $0.isMasked }
            .sorted { $0.range.lowerBound < $1.range.lowerBound }

        let selStart = nsRange.location
        let selEnd   = nsRange.location + nsRange.length

        var redOff    = 0
        var inpCursor = inputText.startIndex
        var mappedStart: String.Index? = nil
        var mappedEnd:   String.Index? = nil

        for item in sorted {
            guard item.range.upperBound > inpCursor else { continue }

            // Plain text segment before this token
            if inpCursor < item.range.lowerBound {
                let plain      = String(inputText[inpCursor..<item.range.lowerBound])
                let plainNSLen = (plain as NSString).length

                if mappedStart == nil && selStart >= redOff && selStart < redOff + plainNSLen,
                   let r = Range(NSRange(location: selStart - redOff, length: 0), in: plain) {
                    let dist = plain.distance(from: plain.startIndex, to: r.lowerBound)
                    mappedStart = inputText.index(inpCursor, offsetBy: dist)
                }
                if mappedEnd == nil && selEnd > redOff && selEnd <= redOff + plainNSLen,
                   let r = Range(NSRange(location: selEnd - redOff, length: 0), in: plain) {
                    let dist = plain.distance(from: plain.startIndex, to: r.lowerBound)
                    mappedEnd = inputText.index(inpCursor, offsetBy: dist)
                }
                redOff    += plainNSLen
                inpCursor  = item.range.lowerBound
            }

            // Token segment — snap selection boundaries to input token boundaries
            let tokenText  = appliedReplacements[item.id] ?? item.token
            let tokenNSLen = (tokenText as NSString).length

            if mappedStart == nil && selStart >= redOff && selStart < redOff + tokenNSLen {
                mappedStart = item.range.lowerBound
            }
            if mappedEnd == nil && selEnd > redOff && selEnd <= redOff + tokenNSLen {
                mappedEnd = item.range.upperBound
            }

            redOff    += tokenNSLen
            inpCursor  = item.range.upperBound
        }

        // Trailing plain text after the last token
        if inpCursor <= inputText.endIndex {
            let plain      = String(inputText[inpCursor...])
            let plainNSLen = (plain as NSString).length

            if mappedStart == nil && selStart >= redOff && selStart <= redOff + plainNSLen,
               let r = Range(NSRange(location: selStart - redOff, length: 0), in: plain) {
                let dist = plain.distance(from: plain.startIndex, to: r.lowerBound)
                mappedStart = inputText.index(inpCursor, offsetBy: dist)
            }
            if mappedEnd == nil && selEnd > redOff && selEnd <= redOff + plainNSLen,
               let r = Range(NSRange(location: selEnd - redOff, length: 0), in: plain) {
                let dist = plain.distance(from: plain.startIndex, to: r.lowerBound)
                mappedEnd = inputText.index(inpCursor, offsetBy: dist)
            }
        }

        guard let start = mappedStart, let end = mappedEnd, start <= end else { return nil }
        return start..<end
    }

    /// Tag a selection given as an NSRange in redactedText, absorbing any overlapping
    /// existing items into the new tag instead of throwing a rangeOverlap error.
    func addManualTagMergingOverlaps(redactedNSRange nsRange: NSRange,
                                     type: PIIType,
                                     inputText: String) {
        guard let range = inputRange(forRedactedNSRange: nsRange, inputText: inputText) else { return }

        // Remove existing items whose input ranges overlap with the target range
        let toRemove = detectedItems.filter {
            range.lowerBound < $0.range.upperBound && $0.range.lowerBound < range.upperBound
        }
        for item in toRemove { appliedReplacements.removeValue(forKey: item.id) }
        detectedItems.removeAll { item in toRemove.contains { $0.id == item.id } }

        try? addManualTag(range: range, type: type, in: inputText)
    }

    func addManualTag(range: Range<String.Index>, type: PIIType, in text: String) throws {
        guard range.lowerBound >= text.startIndex && range.upperBound <= text.endIndex else {
            throw PIIError.invalidRange
        }
        guard range.lowerBound < range.upperBound else {
            throw PIIError.emptySelection
        }
        guard !hasOverlap(newRange: range, with: detectedItems) else {
            throw PIIError.rangeOverlap
        }

        let selectedText = String(text[range])
        let alternatives = PIIItem.generateAlternatives(for: type, original: selectedText)

        let manualItem = PIIItem(
            type: type,
            range: range,
            originalText: selectedText,
            alternatives: alternatives,
            selectedAlternativeId: alternatives.first?.id ?? UUID(),
            confidence: 1.0,
            isMasked: true,
            isManual: true
        )

        let newReplacement = manualItem.token
        appliedReplacements[manualItem.id] = newReplacement

        detectedItems.append(manualItem)
        detectedItems.sort { $0.range.lowerBound < $1.range.lowerBound }

        remask(originalText: text)

        TokenMappingStore.shared.store(
            token: newReplacement,
            original: selectedText,
            type: type
        )
    }

    private func hasOverlap(newRange: Range<String.Index>, with items: [PIIItem]) -> Bool {
        items.contains { item in
            newRange.lowerBound < item.range.upperBound &&
            item.range.lowerBound < newRange.upperBound
        }
    }

    // MARK: - Category Management

    func toggleCategory(_ type: PIIType) {
        if enabledCategories.contains(type) {
            enabledCategories.remove(type)
        } else {
            enabledCategories.insert(type)
        }
    }

    // MARK: - Score

    private func calculateScore(items: [PIIItem]) -> Int {
        guard !items.isEmpty else { return 100 }
        let maskedCount = items.filter(\.isMasked).count
        let ratio = Double(maskedCount) / Double(items.count)
        return Int(ratio * 100)
    }

}
