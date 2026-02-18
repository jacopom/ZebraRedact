import Foundation
import NaturalLanguage

/// Semantic PII detection using Apple's NLTagger framework
final class NLTaggerDetector {
    let name = "NLTagger"
    var isAvailable: Bool {
        if #available(macOS 12.0, *) {
            return true
        }
        return false
    }

    func detect(in text: String) -> [PIIItem] {
        guard #available(macOS 12.0, *) else { return [] }

        var items: [PIIItem] = []

        // Use NLTagger to detect named entities (people, organizations, places)
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
            guard let tag = tag else { return true }

            let value = String(text[tokenRange])

            switch tag {
            case .personalName:
                // Person names
                let alternatives = PIIItem.generateAlternatives(for: .name, original: value)
                let selectedId = alternatives.first?.id ?? UUID()
                items.append(PIIItem(
                    type: .name,
                    range: tokenRange,
                    originalText: value,
                    alternatives: alternatives,
                    selectedAlternativeId: selectedId,
                    confidence: 0.85,
                    isMasked: true
                ))

            case .organizationName:
                // Company/org names can be sensitive (use custom for now)
                let alternatives = PIIItem.generateAlternatives(for: .custom, original: value)
                let selectedId = alternatives.first?.id ?? UUID()
                items.append(PIIItem(
                    type: .custom,
                    range: tokenRange,
                    originalText: value,
                    alternatives: alternatives,
                    selectedAlternativeId: selectedId,
                    confidence: 0.80,
                    isMasked: true
                ))

            case .placeName:
                // Location data can be PII
                let alternatives = PIIItem.generateAlternatives(for: .address, original: value)
                let selectedId = alternatives.first?.id ?? UUID()
                items.append(PIIItem(
                    type: .address,
                    range: tokenRange,
                    originalText: value,
                    alternatives: alternatives,
                    selectedAlternativeId: selectedId,
                    confidence: 0.75,
                    isMasked: true
                ))

            default:
                break
            }

            return true
        }

        // Still use regex for structured data (emails, phones, credit cards, SSN, IP, API keys)
        // NLTagger is best for semantic entities, not patterns
        let regexDetector = RegexDetector()
        let structuredItems = regexDetector.detect(in: text)

        // Merge both results, avoiding duplicates
        items.append(contentsOf: structuredItems)

        return deduplicateItems(items)
    }

    /// Remove overlapping/duplicate detections and ensure same entities get same tokens
    private func deduplicateItems(_ items: [PIIItem]) -> [PIIItem] {
        // Step 1: Remove exact position duplicates
        var positionSeen = Set<String>()
        var uniquePositionItems: [PIIItem] = []

        for item in items {
            let key = "\(item.originalText)_\(item.range.lowerBound)"
            if !positionSeen.contains(key) {
                positionSeen.insert(key)
                uniquePositionItems.append(item)
            }
        }

        // Step 2: Ensure same entities get same tokens
        // CRITICAL: Don't include type in key - same text should ALWAYS get same token
        // regardless of whether detected as .name, .custom, .address, etc.
        var entityTokens: [String: [RedactionAlternative]] = [:]
        var result: [PIIItem] = []

        for item in uniquePositionItems {
            // Normalize entity text for matching
            let normalizedText = item.originalText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            // FIX: Use normalized text only as key (no type prefix)
            let entityKey = normalizedText

            // Reuse alternatives if we've seen this entity before
            let alternatives: [RedactionAlternative]
            if let existing = entityTokens[entityKey] {
                alternatives = existing
            } else {
                alternatives = item.alternatives
                entityTokens[entityKey] = alternatives
            }

            // Create new item with shared alternatives
            var deduplicatedItem = item
            deduplicatedItem.alternatives = alternatives
            deduplicatedItem.selectedAlternativeId = alternatives.first?.id ?? item.selectedAlternativeId

            result.append(deduplicatedItem)
        }

        return result
    }
}
