import Foundation
import NaturalLanguage

/// Phase 1 of the pipeline: deterministic detection via regex + NLTagger.
/// Pattern-matched spans are always .sensitive — the model cannot override this.
final class PatternDetector {

    // MARK: - Regex Patterns

    private struct RawPattern {
        let regex: NSRegularExpression
        let category: RedactionCategory
    }

    private static let patterns: [RawPattern] = buildPatterns()

    private static func buildPatterns() -> [RawPattern] {
        func make(_ pattern: String, _ cat: RedactionCategory) -> RawPattern {
            // All patterns are case-insensitive
            let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            return RawPattern(regex: regex, category: cat)
        }
        return [
            // --- Structured PII (must remain .sensitive, immutable) ---
            make(#"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}"#, .email),
            make(#"(\+?\d{1,3}[\s\-]?)?\(?\d{3}\)?[\s\-]\d{3}[\s\-]\d{4}\b"#, .phone),
            make(#"\b\d{3}-\d{2}-\d{4}\b"#, .ssn),
            make(#"\b(?:\d{4}[\-\s]){3}\d{4}\b"#, .creditCard),
            make(#"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, .ipAddress),
            make(#"\b(?:sk-|pk_live_|pk_test_|AKIA|ghp_|gho_|ghu_|glpat-)[a-zA-Z0-9\-_]{16,}"#, .apiKey),
            // --- Metrics ---
            // Match "7% growth" as a unit (avoids "single-digit growth growth" double-word)
            make(#"\b\d+(?:\.\d+)?%(?:\s+growth)?"#, .metric),
            make(#"\$[\d,]+(?:\.\d+)?[KMBkmb]?\b"#, .metric),
            // Small bare integers that carry operational significance (e.g. "3 outages")
            make(#"\b[1-9]\b"#, .metric),
            // --- Dates (longer patterns first so Q3 2024 wins over bare month) ---
            make(#"\bQ[1-4]\s+\d{4}\b"#, .date),
            make(#"\bH[12]\s+\d{4}\b"#, .date),
            make(#"\b(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{4}\b"#, .date),
            make(#"\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{4}\b"#, .date),
            // Standalone month name (no year) — lower specificity, listed after year variants
            make(#"\b(?:January|February|March|April|May|June|July|August|September|October|November|December)\b"#, .date),
            // --- Projects ---
            make(#"\bProject\s+[A-Z][a-zA-Z]+"#, .project),
            make(#"\b[A-Z]{2,6}-\d{2,6}\b"#, .project),  // PROJ-123 style codes
        ]
    }

    // MARK: - Detect

    func detect(in text: String) -> [RedactionSpan] {
        var candidates: [(range: Range<String.Index>, category: RedactionCategory)] = []

        // Phase 1a: Regex-based patterns
        let nsRange = NSRange(text.startIndex..., in: text)
        for pattern in Self.patterns {
            for match in pattern.regex.matches(in: text, range: nsRange) {
                guard let range = Range(match.range, in: text) else { continue }
                candidates.append((range, pattern.category))
            }
        }

        // Phase 1b: NLTagger for names, orgs, locations
        candidates.append(contentsOf: detectWithNLTagger(in: text))

        // Sort by position, remove overlaps (first/leftmost match wins)
        candidates.sort { $0.range.lowerBound < $1.range.lowerBound }
        candidates = removeOverlaps(candidates)

        // Assign sequential placeholder numbers per category and build spans
        var counters: [RedactionCategory: Int] = [:]
        return candidates.map { candidate in
            let idx = counters[candidate.category, default: 0]
            counters[candidate.category] = idx + 1
            let original = String(text[candidate.range])
            let placeholder = "[\(candidate.category.placeholderPrefix)_\(idx + 1)]"
            let semantic = SemanticSynthesizer.synthesize(
                original: original,
                category: candidate.category,
                spanIndex: idx
            )
            return RedactionSpan(
                range: candidate.range,
                original: original,
                category: candidate.category,
                sensitivity: .sensitive,
                placeholder: placeholder,
                semanticReplacement: semantic
            )
        }
    }

    // MARK: - NLTagger

    private func detectWithNLTagger(in text: String) -> [(range: Range<String.Index>, category: RedactionCategory)] {
        guard #available(macOS 12.0, *) else { return [] }
        var results: [(Range<String.Index>, RedactionCategory)] = []
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitPunctuation, .omitWhitespace, .joinNames]
        ) { tag, range in
            guard let tag else { return true }
            let category: RedactionCategory
            switch tag {
            case .personalName:    category = .person
            case .organizationName: category = .organization
            case .placeName:       category = .location
            default: return true
            }
            results.append((range, category))
            return true
        }
        return results
    }

    // MARK: - Overlap Removal

    private func removeOverlaps(
        _ candidates: [(range: Range<String.Index>, category: RedactionCategory)]
    ) -> [(range: Range<String.Index>, category: RedactionCategory)] {
        var result: [(Range<String.Index>, RedactionCategory)] = []
        for c in candidates {
            let overlaps = result.contains { existing in
                c.range.lowerBound < existing.0.upperBound &&
                existing.0.lowerBound < c.range.upperBound
            }
            if !overlaps { result.append((c.range, c.category)) }
        }
        return result
    }
}
