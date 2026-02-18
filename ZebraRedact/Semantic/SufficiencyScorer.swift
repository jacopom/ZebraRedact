import Foundation

/// Phase 4: heuristic scoring of the redacted text for LLM usefulness.
///
/// Thresholds (from spec):
///   ≥80% overall → .ready ✅
///   50–79%       → .review ⚠️
///   <50%         → .stop 🛑
enum SufficiencyScorer {

    static func score(
        original: String,
        redacted: String,
        spans: [RedactionSpan],
        task: String?
    ) -> SufficiencyScores {
        SufficiencyScores(
            taskCompletability: taskCompletability(spans: spans, redacted: redacted),
            hallucinationRisk: hallucinationRisk(spans: spans, redacted: redacted),
            coherence: coherence(redacted: redacted, original: original)
        )
    }

    // MARK: - Task Completability (higher is better)

    private static func taskCompletability(spans: [RedactionSpan], redacted: String) -> Int {
        guard !spans.isEmpty else { return 100 }

        let wordCount = max(1.0, Double(redacted.split(separator: " ").count))
        let redactionRatio = Double(spans.count) / wordCount

        // Reward qualitative replacements — they preserve semantic content
        let hasQualitative = spans.contains { $0.semanticReplacement != nil }
        let qualitativeBonus = hasQualitative ? 10 : 0

        // Heavy redaction degrades task completability
        let base = max(20, 100 - Int(redactionRatio * 200))
        return min(100, base + qualitativeBonus)
    }

    // MARK: - Hallucination Risk (lower is better)

    private static func hallucinationRisk(spans: [RedactionSpan], redacted: String) -> Int {
        var risk = 0

        // Exact numbers without qualifiers in the redacted text are hallucination bait
        let orphanNumberPattern = try! NSRegularExpression(
            pattern: #"\b\d+(?:\.\d+)?\b"#
        )
        let nsRange = NSRange(redacted.startIndex..., in: redacted)
        let orphanCount = orphanNumberPattern.numberOfMatches(in: redacted, range: nsRange)
        risk += min(40, orphanCount * 8)

        // More redactions → higher risk of context gaps the LLM fills in
        let wordCount = max(1.0, Double(redacted.split(separator: " ").count))
        let redactionRatio = Double(spans.count) / wordCount
        risk += min(40, Int(redactionRatio * 120))

        return min(80, risk)
    }

    // MARK: - Coherence (higher is better)

    private static func coherence(redacted: String, original: String) -> Int {
        let originalWords = Double(max(1, original.split(separator: " ").count))
        let redactedWords = Double(max(1, redacted.split(separator: " ").count))

        // If too many words were dropped, coherence suffers
        let retentionRatio = redactedWords / originalWords

        // Check for placeholder density — too many brackets break readability
        let bracketCount = redacted.components(separatedBy: "[").count - 1
        let bracketRatio = Double(bracketCount) / redactedWords
        let bracketPenalty = min(40, Int(bracketRatio * 200))

        let base = max(30, Int(retentionRatio * 100))
        return min(100, max(0, base - bracketPenalty))
    }
}
