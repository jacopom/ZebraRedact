import Foundation
import NaturalLanguage

/// Semantic PII detection using Apple's NLTagger framework
final class NLTaggerDetector {
    let name = "NLTagger"

    /// Words/abbreviations that NLTagger commonly misclassifies as named entities.
    /// Covers document field labels, legal suffixes, and financial routing labels.
    private static let entityBlocklist: Set<String> = [
        // Document field labels (appear as column/row headers in financial docs)
        "beneficiary", "remitter", "originator", "correspondent", "intermediary",
        "sender", "recipient", "payer", "payee", "account", "reference",
        "memo", "purpose", "currency", "amount", "date", "description",
        // Legal/corporate suffixes that appear standalone after fragmentation
        "ltd", "llc", "inc", "corp", "co", "plc", "gmbh", "sa", "nv", "bv", "ag", "lp",
        // Financial routing/format labels
        "aba", "swift", "bic", "iban", "sepa", "eft", "ach", "wire",
        // Address-component words misclassified as personal names
        "unit", "floor", "suite", "building", "apt",
    ]

    var isAvailable: Bool {
        if #available(macOS 12.0, *) {
            return true
        }
        return false
    }

    func detect(in text: String) -> [PIIItem] {
        guard #available(macOS 12.0, *) else { return [] }

        var items: [PIIItem] = []

        // Run NLTagger on the capitalized form so lowercase words like "jacopo"
        // or "milano" are recognised as proper nouns. Capitalization preserves
        // character offsets (no length change), so ranges map back to `text` unchanged.
        let taggerInput = text.capitalized

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = taggerInput

        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]

        tagger.enumerateTags(in: taggerInput.startIndex..<taggerInput.endIndex, unit: .word, scheme: .nameType, options: options) { tag, capitalizedRange in
            guard let tag = tag else { return true }
            // Map the range from taggerInput back to original text via UTF-16 offsets.
            // Capitalization is length-preserving for ASCII/Latin characters so the
            // NSRange offsets are identical between taggerInput and text.
            let nsRange = NSRange(capitalizedRange, in: taggerInput)
            guard let tokenRange = Range(nsRange, in: text) else { return true }

            let value = String(text[tokenRange])
            // Skip document labels, legal suffixes, and financial acronyms
            let normalized = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !Self.entityBlocklist.contains(normalized) else { return true }

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

        // Fallback: detect names in email signature blocks that NLTagger may miss
        // due to minimal context (e.g. "Best regards,\nIngrid Sörensen\nHR Manager")
        let signatureItems = detectSignatureNames(in: text)
        items.append(contentsOf: signatureItems)

        // Merge hyphen-adjacent name/address pairs that are actually compound surnames
        // e.g. NLTagger splits "Tanaka-Hoffman" into Name("Tanaka") + Address("Hoffman")
        let merged = mergeHyphenatedNames(items: items, in: text)

        return deduplicateItems(merged)
    }

    /// Detect personal names that appear immediately after email signature openers
    /// (e.g. "Best regards,\nIngrid Sörensen"). NLTagger often fails in short-context blocks.
    private func detectSignatureNames(in text: String) -> [PIIItem] {
        // Opener: "Best regards", "Regards", "Sincerely", "Thanks", "Cheers", etc.
        // Name: two or more capitalized Unicode words (supports ä, ö, ü, ñ, é, etc.)
        // \p{Lu} = Unicode uppercase letter, \p{L} = any Unicode letter
        let pattern = #"(?:Best\s+regards|Kind\s+regards|Regards|Sincerely|Many\s+thanks|Thanks|Cheers|Best\s+wishes|Warm\s+regards|Yours\s+(?:sincerely|faithfully|truly))[,.]?[ \t]*\n(\p{Lu}\p{L}+(?:-\p{Lu}\p{L}+)?(?:[ \t]+\p{Lu}\p{L}+(?:-\p{Lu}\p{L}+)?)+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var result: [PIIItem] = []
        for match in regex.matches(in: text, range: fullRange) {
            guard match.numberOfRanges > 1 else { continue }
            let nameNSRange = match.range(at: 1)
            guard let nameRange = Range(nameNSRange, in: text) else { continue }
            let nameText = String(text[nameRange])
            let alternatives = PIIItem.generateAlternatives(for: .name, original: nameText)
            result.append(PIIItem(
                type: .name,
                range: nameRange,
                originalText: nameText,
                alternatives: alternatives,
                selectedAlternativeId: alternatives.first?.id ?? UUID(),
                confidence: 0.88,
                isMasked: true
            ))
        }
        return result
    }

    /// Merge adjacent items separated by a single hyphen into a unified Name item.
    /// Handles compound surnames like "Tanaka-Hoffman" that NLTagger splits at the boundary.
    private func mergeHyphenatedNames(items: [PIIItem], in text: String) -> [PIIItem] {
        let sorted = items.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var result: [PIIItem] = []
        var i = 0
        while i < sorted.count {
            let current = sorted[i]
            if i + 1 < sorted.count {
                let next = sorted[i + 1]
                // Check if the gap between items is exactly "-"
                if current.range.upperBound <= next.range.lowerBound {
                    let gap = String(text[current.range.upperBound..<next.range.lowerBound])
                    let bothAreNameLike = (current.type == .name || current.type == .address || current.type == .custom)
                                      && (next.type == .name || next.type == .address || next.type == .custom)
                    if gap == "-" && bothAreNameLike {
                        let mergedText = String(text[current.range.lowerBound..<next.range.upperBound])
                        let mergedRange = current.range.lowerBound..<next.range.upperBound
                        let alternatives = PIIItem.generateAlternatives(for: .name, original: mergedText)
                        result.append(PIIItem(
                            type: .name,
                            range: mergedRange,
                            originalText: mergedText,
                            alternatives: alternatives,
                            selectedAlternativeId: alternatives.first?.id ?? UUID(),
                            confidence: 0.85,
                            isMasked: true
                        ))
                        i += 2
                        continue
                    }
                }
            }
            result.append(current)
            i += 1
        }
        return result
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
        var deduped: [PIIItem] = []

        for item in uniquePositionItems {
            // Normalize entity text for matching
            let normalizedText = item.originalText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
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

            deduped.append(deduplicatedItem)
        }

        // Step 3: Remove overlapping items — sort by start position, keep first of any
        // overlapping pair. This prevents double-detection (e.g. a number matched by
        // both the phone regex and SSN regex simultaneously).
        let sortedByStart = deduped.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var result: [PIIItem] = []
        var lastUpperBound: String.Index? = nil

        for item in sortedByStart {
            if let last = lastUpperBound, item.range.lowerBound < last {
                // Overlapping with the previous kept item — skip
                continue
            }
            result.append(item)
            lastUpperBound = item.range.upperBound
        }

        return result
    }
}
