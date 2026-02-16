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
            // Phone (international & US formats)
            (.phone, #"(?:\+?\d{1,3}[\s\-]?)?\(?\d{2,4}\)?[\s\-]?\d{3,4}[\s\-]?\d{3,4}"#),
            // Credit Card (Visa, MC, Amex, Discover)
            (.creditCard, #"\b(?:4\d{3}|5[1-5]\d{2}|3[47]\d{2}|6(?:011|5\d{2}))[\s\-]?\d{4}[\s\-]?\d{4}[\s\-]?\d{4}\b"#),
            // SSN
            (.ssn, #"\b\d{3}[\-\s]?\d{2}[\-\s]?\d{4}\b"#),
            // IPv4
            (.ipAddress, #"\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b"#),
            // API Keys (common patterns: sk-, pk_, AKIA, ghp_, etc.)
            (.apiKey, #"\b(?:sk-[a-zA-Z0-9]{20,}|pk_[a-zA-Z0-9]{20,}|AKIA[A-Z0-9]{16}|ghp_[a-zA-Z0-9]{36}|xox[baprs]-[a-zA-Z0-9\-]{10,})\b"#),
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
                guard let swiftRange = Range(match.range, in: text) else { continue }
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
            result.replaceSubrange(item.range, with: item.ghostToken)
        }
        return result
    }
}
