import Foundation
import Combine

@MainActor
final class PIIDetector: ObservableObject {
    @Published var detectedItems: [PIIItem] = []
    @Published var ghostedText: String = ""
    @Published var privacyScore: Int = 100
    @Published var isProcessing: Bool = false
    @Published var enabledCategories: Set<PIIType> = Set(PIIType.allCases)

    private let detector = NLTaggerDetector()

    /// Computed confidence assessment
    var confidenceAssessment: ConfidenceAssessment? {
        guard !detectedItems.isEmpty else { return nil }

        // Simple heuristic: more redactions = lower confidence
        let wordCount = max(1.0, Double(ghostedText.split(separator: " ").count))
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

    /// Issues that might affect confidence
    var confidenceIssues: [ConfidenceIssue] {
        guard let assessment = confidenceAssessment, assessment.status != .ready else {
            return []
        }

        // Generate issues for problematic items
        return detectedItems.prefix(3).map { item in
            ConfidenceIssue(
                item: item,
                impact: "Removing \(item.type.rawValue) may reduce context",
                suggestion: "Consider using semantic or partial redaction"
            )
        }
    }

    // MARK: - Scan

    func scan(text: String) {
        isProcessing = true
        defer { isProcessing = false }

        let allItems = detector.detect(in: text)
        detectedItems = allItems.filter { enabledCategories.contains($0.type) }

        // Mask text with detected items
        var result = text
        for item in detectedItems.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) where item.isMasked {
            result.replaceSubrange(item.range, with: item.ghostToken)
        }
        ghostedText = result

        privacyScore = calculateScore(items: detectedItems)

        // Save token→original mappings for rehydration
        GhostMappingStore.shared.storeBatch(items: detectedItems)
    }

    // MARK: - Toggle Individual Items

    func toggleItem(_ item: PIIItem) {
        guard let idx = detectedItems.firstIndex(where: { $0.id == item.id }) else { return }
        detectedItems[idx].isMasked.toggle()
    }

    // MARK: - Re-mask After Toggling

    func remask(originalText: String) {
        var result = originalText
        for item in detectedItems.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) where item.isMasked {
            result.replaceSubrange(item.range, with: item.ghostToken)
        }
        ghostedText = result
        privacyScore = calculateScore(items: detectedItems)
    }

    // MARK: - Mask All / Unmask All

    func maskAll() {
        for i in detectedItems.indices {
            detectedItems[i].isMasked = true
        }
    }

    func unmaskAll() {
        for i in detectedItems.indices {
            detectedItems[i].isMasked = false
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

    var detectionMethod: String { "NLTagger + Regex" }
}
