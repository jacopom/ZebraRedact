import Foundation

/// Regex-based PII detector (Free tier). Detects common PII patterns.
final class RegexDetector {
    let name = "Regex"
    let isAvailable = true

    // MARK: - Pattern Definitions

    private static let patterns: [(PIIType, NSRegularExpression)] = {
        let defs: [(PIIType, String)] = [
            // Email
            (.email, #"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}"#),
            // Phone — US/Canada: (415) 555-0192, 415-555-0192, +1 415.555.0192
            // Requires separator between all groups (excludes EINs like 84-3210987,
            // account numbers like 000482991703, and ABA routing like 021000021)
            (.phone, #"(?<!\d)(?:\+?1[\s\-\.]?)?(?:\(\d{3}\)|\d{3})[\s\-\.]\d{3}[\s\-\.]\d{4}(?![\-\d])"#),
            // Phone — International with explicit + prefix: +44 20 7946 0958, +33 6 12 34 56 78
            (.phone, #"\+[1-9]\d{0,2}[\s\-]\d{1,4}(?:[\s\-]\d{2,4}){1,4}\b"#),
            // Phone — European mobile with known country prefixes (no separators required):
            // Italian 3XX (32–39, 10 digits), UK 07XX (11 digits), French 06/07XX (10 digits)
            (.phone, #"(?<!\d)(?:3[2-9]\d{8}|07\d{9}|06\d{8})(?!\d)"#),
            // Phone — labeled bare digits: "Tel: 1234567890", "Mobile: 07911123456"
            (.phone, #"(?i)(?:tel|phone|ph|mobile|mob|cell|fax)[.:\s]+(\d{10,11})(?!\d)"#),
            // Credit Card (Visa, MC, Amex, Discover)
            (.creditCard, #"\b(?:4\d{3}|5[1-5]\d{2}|3[47]\d{2}|6(?:011|5\d{2}))[\s\-]?\d{4}[\s\-]?\d{4}[\s\-]?\d{4}\b"#),
            // SSN: NNN-NN-NNNN (dash-separated, requires dashes, not optional).
            // Negative lookahead (?![-\d]) prevents substring matches inside longer
            // hyphenated numbers like 808-123456-838.
            (.ssn, #"\b\d{3}-\d{2}-\d{4}\b(?![-\d])"#),
            // SSN with spaces: NNN NN NNNN
            (.ssn, #"\b\d{3} \d{2} \d{4}\b(?! \d)"#),
            // IPv4
            (.ipAddress, #"\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b"#),
            // API Keys (common patterns: sk-, pk_, AKIA, ghp_, etc.)
            (.apiKey, #"\b(?:sk-[a-zA-Z0-9]{20,}|pk_[a-zA-Z0-9]{20,}|AKIA[A-Z0-9]{16}|ghp_[a-zA-Z0-9]{36}|xox[baprs]-[a-zA-Z0-9\-]{10,})\b"#),
            // Dates — DD/MM/YYYY, DD-MM-YYYY, DD.MM.YYYY
            (.date, #"\b(?:0?[1-9]|[12]\d|3[01])[\/\-\.](?:0?[1-9]|1[0-2])[\/\-\.](?:19|20)\d{2}\b"#),
            // Dates — MM/DD/YYYY (US)
            (.date, #"\b(?:0?[1-9]|1[0-2])[\/\-](?:0?[1-9]|[12]\d|3[01])[\/\-](?:19|20)\d{2}\b"#),
            // Dates — ISO YYYY-MM-DD
            (.date, #"\b(?:19|20)\d{2}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])\b"#),
            // Dates — "January 12, 1985" or "12 January 1985"
            (.date, #"\b(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},?\s+(?:19|20)\d{2}\b"#),
            (.date, #"\b\d{1,2}\s+(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+(?:19|20)\d{2}\b"#),
            // Street addresses — "123 Main Street", "42 Elm Dr Apt 3B"
            (.address, #"\b\d{1,5}\s+(?:[A-Za-z]+\s+){1,4}(?:Street|St|Avenue|Ave|Boulevard|Blvd|Road|Rd|Drive|Dr|Lane|Ln|Court|Ct|Way|Place|Pl|Circle|Cir|Highway|Hwy|Parkway|Pkwy)\.?(?:\s+(?:Apt|Suite|Ste|Unit|Apartment)\s*[A-Za-z0-9]+)?\b"#),
        ]
        return defs.compactMap { type, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            return (type, regex)
        }
    }()

    // MARK: - Detection

    func detect(in text: String) -> [PIIItem] {
        var items: [PIIItem] = []
        let nsString = text as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)

        for (type, regex) in Self.patterns {
            let matches = regex.matches(in: text, options: [], range: fullRange)
            for match in matches {
                // Use capture group 1 when present (e.g. labeled phone pattern captures just the number)
                let matchNSRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                guard matchNSRange.location != NSNotFound,
                      let swiftRange = Range(matchNSRange, in: text) else { continue }
                let matchedText = String(text[swiftRange])

                // Generate alternatives for this PII type
                let alternatives = PIIItem.generateAlternatives(for: type, original: matchedText)
                let selectedId = alternatives.first?.id ?? UUID()

                let item = PIIItem(
                    type: type,
                    range: swiftRange,
                    originalText: matchedText,
                    alternatives: alternatives,
                    selectedAlternativeId: selectedId,
                    confidence: 1.0,
                    isMasked: true
                )
                items.append(item)
            }
        }

        return items.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    // MARK: - Masking

    func mask(text: String, items: [PIIItem]) -> String {
        var result = text
        // Process in reverse order to preserve indices
        for item in items.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) where item.isMasked {
            result.replaceSubrange(item.range, with: item.token)
        }
        return result
    }
}
