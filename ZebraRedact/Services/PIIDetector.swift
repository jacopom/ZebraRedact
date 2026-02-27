import Foundation
import Combine

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

// MARK: - MaskingLevel

enum MaskingLevel: String, CaseIterable, Identifiable {
    case manualOnly    = "Manual"
    case highConfidence = "High"
    case all           = "All"

    var id: String { rawValue }

    /// Items with confidence below this value are detected but not auto-masked.
    var confidenceThreshold: Double {
        switch self {
        case .manualOnly:     return 1.1   // Above any auto-detection score
        case .highConfidence: return 0.85  // Regex (1.0) + NLTagger names (0.85, 0.88)
        case .all:            return 0.0
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
    @Published var maskingLevel: MaskingLevel = .all
    /// Maps each item ID → the text actually placed in redactedText for that item
    @Published var appliedReplacements: [UUID: String] = [:]

    private let detector = NLTaggerDetector()

    // MARK: - Computed Properties

    /// Computed confidence assessment
    var confidenceAssessment: ConfidenceAssessment? {
        guard !detectedItems.isEmpty else { return nil }

        let wordCount = max(1.0, Double(redactedText.split(separator: " ").count))
        // Use only masked items so quality reflects what's actually being hidden
        let redactionRatio = Double(detectedItems.filter(\.isMasked).count) / wordCount

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

        let allItems = detector.detect(in: text)
        let filtered = allItems.filter { enabledCategories.contains($0.type) }

        // Apply masking level: items below the threshold are detected but not auto-masked
        let threshold = maskingLevel.confidenceThreshold
        let thresholded = filtered.map { item -> PIIItem in
            guard !item.isManual else { return item }
            var copy = item
            copy.isMasked = item.confidence >= threshold
            return copy
        }

        // Re-anchor surviving manual items
        var preserved: [PIIItem] = []
        for manual in previousManualItems {
            guard let newRange = text.range(of: manual.originalText, options: .literal) else { continue }
            let overlaps = thresholded.contains { s in
                newRange.lowerBound < s.range.upperBound && s.range.lowerBound < newRange.upperBound
            }
            guard !overlaps else { continue }
            preserved.append(manual.withRange(newRange))
        }

        let combined = (thresholded + preserved)
            .sorted { $0.range.lowerBound < $1.range.lowerBound }

        Task {
            await applyMasking(to: text, newItems: combined)
            await MainActor.run {
                isProcessing = false
            }
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

    // MARK: - Masking Level

    /// Switch masking level and re-apply without re-running detection.
    func setMaskingLevel(_ level: MaskingLevel, originalText: String) {
        maskingLevel = level
        let threshold = level.confidenceThreshold
        detectedItems = detectedItems.map { item in
            guard !item.isManual else { return item }
            var copy = item
            copy.isMasked = item.confidence >= threshold
            return copy
        }
        remask(originalText: originalText)
    }

    // MARK: - Score

    private func calculateScore(items: [PIIItem]) -> Int {
        guard !items.isEmpty else { return 100 }
        let maskedCount = items.filter(\.isMasked).count
        let ratio = Double(maskedCount) / Double(items.count)
        return Int(ratio * 100)
    }

}
