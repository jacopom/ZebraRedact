import Foundation
import Combine

@MainActor
final class PIIDetector: ObservableObject {
    @Published var detectedItems: [PIIItem] = []
    @Published var ghostedText: String = ""
    @Published var privacyScore: Int = 100
    @Published var isProcessing: Bool = false
    @Published var enabledCategories: Set<PIIType> = Set(PIIType.allCases)

    private let regexDetector = RegexDetector()

    // MARK: - Scan

    func scan(text: String) {
        isProcessing = true
        defer { isProcessing = false }

        let allItems = regexDetector.detect(in: text)
        // Filter by enabled categories
        detectedItems = allItems.filter { enabledCategories.contains($0.type) }
        ghostedText = regexDetector.mask(text: text, items: detectedItems)
        privacyScore = calculateScore(items: detectedItems)
    }

    // MARK: - Toggle Individual Items

    func toggleItem(_ item: PIIItem) {
        guard let idx = detectedItems.firstIndex(where: { $0.id == item.id }) else { return }
        detectedItems[idx].isMasked.toggle()
    }

    // MARK: - Re-mask After Toggling

    func remask(originalText: String) {
        ghostedText = regexDetector.mask(text: originalText, items: detectedItems)
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

    var detectionMethod: String { "Regex" }
}
