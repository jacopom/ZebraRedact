import Foundation

/// Calculates confidence scores for redacted text (Phase 3 of pipeline)
final class ConfidenceCalculator {

    /// Assess confidence after redaction
    func assess(
        originalText: String,
        redactedText: String,
        detectedItems: [PIIItem]
    ) -> (assessment: ConfidenceAssessment, issues: [ConfidenceIssue]) {

        let maskedItems = detectedItems.filter { $0.isMasked }

        // Calculate 3 metrics
        let taskCompletability = calculateTaskCompletability(
            originalText: originalText,
            redactedText: redactedText,
            maskedCount: maskedItems.count
        )

        let hallucinationRisk = calculateHallucinationRisk(
            maskedItems: maskedItems,
            textLength: originalText.count
        )

        let coherence = calculateCoherence(
            originalText: originalText,
            redactedText: redactedText
        )

        let assessment = ConfidenceAssessment(
            taskCompletability: taskCompletability,
            hallucinationRisk: hallucinationRisk,
            coherence: coherence
        )

        // Identify issues that need review
        let issues = identifyIssues(maskedItems: maskedItems, assessment: assessment)

        return (assessment, issues)
    }

    // MARK: - Metric Calculations

    /// Calculate task completability (0-100)
    /// Can the LLM still complete the user's intended task?
    private func calculateTaskCompletability(
        originalText: String,
        redactedText: String,
        maskedCount: Int
    ) -> Int {
        // If nothing was masked, task is fully completable
        guard maskedCount > 0 else { return 100 }

        // Calculate information retention ratio
        let originalLength = originalText.count
        let redactedLength = redactedText.count

        // If too much was removed, completability drops
        let retentionRatio = Double(redactedLength) / Double(originalLength)

        // Penalize heavily for removing > 50% of content
        if retentionRatio < 0.5 {
            return Int(retentionRatio * 100)
        }

        // Moderate penalty for 3+ masked items (likely removes critical context)
        if maskedCount >= 3 {
            return max(60, Int(retentionRatio * 100) - (maskedCount * 5))
        }

        // Light penalty for 1-2 items
        return max(70, Int(retentionRatio * 100) - (maskedCount * 10))
    }

    /// Calculate hallucination risk (0-100, lower is better)
    /// Will the LLM fabricate details to fill gaps?
    private func calculateHallucinationRisk(
        maskedItems: [PIIItem],
        textLength: Int
    ) -> Int {
        guard !maskedItems.isEmpty else { return 0 }

        var risk = 0

        // High-risk categories that LLMs tend to hallucinate
        let highRiskTypes: Set<PIIType> = [.name, .address, .custom]
        let mediumRiskTypes: Set<PIIType> = [.email, .phone]

        for item in maskedItems {
            if highRiskTypes.contains(item.type) {
                risk += 25  // Names, addresses easily hallucinated
            } else if mediumRiskTypes.contains(item.type) {
                risk += 15  // Contact info sometimes fabricated
            } else {
                risk += 10  // Other types lower risk
            }
        }

        // If text is very short and heavily masked, risk increases
        if textLength < 200 && maskedItems.count >= 2 {
            risk += 20
        }

        return min(100, risk)
    }

    /// Calculate coherence (0-100)
    /// Does the redacted text still make logical sense?
    private func calculateCoherence(
        originalText: String,
        redactedText: String
    ) -> Int {
        // Check if redacted text maintains sentence structure
        let originalSentences = originalText.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let redactedSentences = redactedText.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        // If sentence count changed dramatically, coherence is affected
        if abs(originalSentences.count - redactedSentences.count) > 2 {
            return 50
        }

        // Check for broken grammar patterns (heuristic)
        let brokenPatterns = [
            "  [",  // Double space before token
            "]  ",  // Double space after token
            " ,",   // Space before comma
            " .",   // Space before period
        ]

        var coherenceScore = 100
        for pattern in brokenPatterns {
            if redactedText.contains(pattern) {
                coherenceScore -= 10
            }
        }

        // Check if too many consecutive tokens
        let consecutiveTokens = redactedText.contains("] [")
        if consecutiveTokens {
            coherenceScore -= 15
        }

        return max(50, coherenceScore)
    }

    // MARK: - Issue Identification

    /// Identify specific issues that need human review
    private func identifyIssues(
        maskedItems: [PIIItem],
        assessment: ConfidenceAssessment
    ) -> [ConfidenceIssue] {
        var issues: [ConfidenceIssue] = []

        // Only flag issues if confidence is below threshold
        guard assessment.overallConfidence < 80 else { return issues }

        for item in maskedItems {
            // Flag high-impact types
            if item.type == .name {
                issues.append(ConfidenceIssue(
                    item: item,
                    impact: "Person names help LLMs understand roles and relationships",
                    suggestion: "Consider using a role description (e.g., 'our CEO', 'the project lead')"
                ))
            }

            if item.type == .custom {
                issues.append(ConfidenceIssue(
                    item: item,
                    impact: "This term may be important for context",
                    suggestion: "Consider providing a generic description if safe to do so"
                ))
            }
        }

        // If multiple items of same type, suggest alternatives
        let groupedByType = Dictionary(grouping: maskedItems) { $0.type }
        for (type, items) in groupedByType where items.count >= 2 {
            if type == .email || type == .phone {
                issues.append(ConfidenceIssue(
                    item: items[0],
                    impact: "Multiple \(type.rawValue.lowercased())s were redacted",
                    suggestion: "If these are related (same person/company), mention that relationship"
                ))
            }
        }

        return issues
    }
}
