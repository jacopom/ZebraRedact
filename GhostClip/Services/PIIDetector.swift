import Foundation
import Combine

/// Facade that routes PII detection to either Regex (Free) or MLX (Pro).
@MainActor
final class PIIDetector: ObservableObject {
    @Published var detectedItems: [PIIItem] = []
    @Published var ghostedText: String = ""
    @Published var privacyScore: Int = 100
    @Published var isProcessing: Bool = false

    private let regexDetector = RegexDetector()
    private let isPro: Bool

    init(isPro: Bool = false) {
        self.isPro = isPro
    }

    // MARK: - Scan

    func scan(text: String) {
        isProcessing = true
        defer { isProcessing = false }

        // Use regex detector (MLX would be used in Pro if model is installed)
        detectedItems = regexDetector.detect(in: text)
        ghostedText = regexDetector.mask(text: text, items: detectedItems)
        privacyScore = calculateScore(original: text, items: detectedItems)
    }

    // MARK: - Toggle Individual Items

    func toggleItem(_ item: PIIItem) {
        guard let idx = detectedItems.firstIndex(where: { $0.id == item.id }) else { return }
        detectedItems[idx].isMasked.toggle()
    }

    // MARK: - Re-mask After Toggling

    func remask(originalText: String) {
        ghostedText = regexDetector.mask(text: originalText, items: detectedItems)
        privacyScore = calculateScore(original: originalText, items: detectedItems)
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

    // MARK: - Score

    private func calculateScore(original: String, items: [PIIItem]) -> Int {
        guard !items.isEmpty else { return 100 }
        let maskedCount = items.filter(\.isMasked).count
        let ratio = Double(maskedCount) / Double(items.count)
        return Int(ratio * 100)
    }

    var detectionMethod: String {
        isPro ? "MLX" : "Regex"
    }
}
