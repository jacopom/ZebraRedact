import Foundation

/// Confidence assessment for redacted text
struct ConfidenceAssessment {
    /// Can the LLM still complete the user's intended task?
    let taskCompletability: Int  // 0-100

    /// Risk of LLM fabricating details to fill gaps
    let hallucinationRisk: Int  // 0-100 (lower is better)

    /// Does the redacted text still make logical sense?
    let coherence: Int  // 0-100

    /// Overall confidence: average of the three goodness scores
    var overallConfidence: Int {
        (taskCompletability + (100 - hallucinationRisk) + coherence) / 3
    }

    /// Status based on overall confidence
    var status: ConfidenceStatus {
        overallConfidence > 30 ? .ready : .reviewNeeded
    }

    /// Color for UI display
    var statusColor: String {
        switch status {
        case .ready: return "green"
        case .reviewNeeded: return "orange"
        case .tooDegraded: return "red"
        }
    }

    /// Icon for UI display
    var statusIcon: String {
        switch status {
        case .ready: return "checkmark.circle.fill"
        case .reviewNeeded: return "exclamationmark.triangle.fill"
        case .tooDegraded: return "xmark.circle.fill"
        }
    }

    /// Human-readable status text
    var statusText: String {
        switch status {
        case .ready: return "READY"
        case .reviewNeeded: return "REVIEW NEEDED"
        case .tooDegraded: return "TOO DEGRADED"
        }
    }

    /// Detailed explanation of the assessment
    var explanation: String {
        switch status {
        case .ready:
            return "The redacted text preserves enough context for accurate AI responses."
        case .reviewNeeded:
            return "Some redactions may affect AI accuracy. Review the suggestions below."
        case .tooDegraded:
            return "Too much information was removed. Consider rephrasing or providing safe substitutes."
        }
    }
}

enum ConfidenceStatus {
    case ready          // ≥80% - safe to send
    case reviewNeeded   // 50-79% - flag for review
    case tooDegraded    // <50% - don't send
}

/// Issues that affect confidence
struct ConfidenceIssue: Identifiable {
    let id = UUID()
    let item: PIIItem
    let impact: String
    let suggestion: String
}
