import Foundation
import Combine

// MARK: - Errors

enum PIIError: LocalizedError {
    case rangeOverlap
    case invalidRange
    case emptySelection

    var errorDescription: String? {
        switch self {
        case .rangeOverlap: return "This selection overlaps with existing PII item"
        case .invalidRange: return "Invalid text range selected"
        case .emptySelection: return "Please select text to tag"
        }
    }
}

// MARK: - PIIDetector

@MainActor
final class PIIDetector: ObservableObject {
    @Published var detectedItems: [PIIItem] = []
    @Published var ghostedText: String = ""
    @Published var privacyScore: Int = 100
    @Published var isProcessing: Bool = false
    @Published var enabledCategories: Set<PIIType> = Set(PIIType.allCases)
    @Published var redactionMode: RedactionMode = .semantic
    @Published var semanticContext: SemanticContext?
    /// Maps each item ID → the text actually placed in ghostedText for that item
    @Published var appliedReplacements: [UUID: String] = [:]

    private let detector = NLTaggerDetector()
    private var mlxEngine: MLXContextEngine?
    private var modelManager: ModelManager?

    /// Type-erased FoundationModelEngine (macOS 26+)
    private var foundationEngine: AnyObject?

    init(modelManager: ModelManager? = nil) {
        self.modelManager = modelManager
        if modelManager != nil {
            self.mlxEngine = MLXContextEngine(modelManager: modelManager)
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            foundationEngine = FoundationModelEngine()
        }
        #endif
    }

    // MARK: - Computed Properties

    /// Whether Foundation Models is active for the current mode
    var isFoundationModelsActive: Bool {
        guard redactionMode == .llmAware else { return false }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return FoundationModelEngine.isAvailable
        }
        #endif
        return false
    }

    /// Whether Ollama is configured (active model set) for LLM-Aware mode
    var isOllamaActive: Bool {
        guard redactionMode == .llmAware else { return false }
        return OllamaEngine.activeModel != nil
    }

    /// Computed confidence assessment
    var confidenceAssessment: ConfidenceAssessment? {
        guard !detectedItems.isEmpty else { return nil }

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

        let allItems = detector.detect(in: text)
        detectedItems = allItems.filter { enabledCategories.contains($0.type) }

        Task {
            await applyMasking(to: text)
            await MainActor.run {
                isProcessing = false
            }
        }
    }

    private func applyMasking(to text: String) async {
        var result = text
        var applied: [UUID: String] = [:]

        switch redactionMode {
        case .token:
            for item in detectedItems.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) where item.isMasked {
                result.replaceSubrange(item.range, with: item.ghostToken)
                applied[item.id] = item.ghostToken
            }

        case .semantic:
            for item in detectedItems.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) where item.isMasked {
                if let semanticAlt = item.alternatives.first(where: { $0.strategy == .semantic }) {
                    result.replaceSubrange(item.range, with: semanticAlt.text)
                    applied[item.id] = semanticAlt.text
                } else {
                    result.replaceSubrange(item.range, with: item.ghostToken)
                    applied[item.id] = item.ghostToken
                }
            }

        case .llmAware:
            var handled = false

            // Priority 1: Foundation Models (macOS 26+)
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *),
               let engine = foundationEngine as? FoundationModelEngine,
               FoundationModelEngine.isAvailable {
                do {
                    // Augment detection with entities NLTagger/regex may have missed
                    let additionalItems = try await engine.augmentDetection(
                        text: text,
                        existingItems: detectedItems
                    )
                    if !additionalItems.isEmpty {
                        detectedItems = (detectedItems + additionalItems)
                            .sorted { $0.range.lowerBound < $1.range.lowerBound }
                    }

                    // Generate context-preserving replacements
                    let replacements = try await engine.generateContextAwareReplacements(
                        text: text,
                        items: detectedItems
                    )
                    for item in detectedItems.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) where item.isMasked {
                        let replacement = replacements[item.id] ?? item.ghostToken
                        result.replaceSubrange(item.range, with: replacement)
                        applied[item.id] = replacement
                    }
                    handled = true
                } catch {
                    print("Foundation Models error: \(error), falling back")
                }
            }
            #endif

            if !handled {
                // Priority 2: Ollama (if running + active model configured)
                if let model = OllamaEngine.activeModel {
                    do {
                        let additionalItems = try await OllamaEngine.augmentDetection(
                            text: text,
                            existingItems: detectedItems
                        )
                        if !additionalItems.isEmpty {
                            detectedItems = (detectedItems + additionalItems)
                                .sorted { $0.range.lowerBound < $1.range.lowerBound }
                        }
                        let replacements = try await OllamaEngine.generateContextAwareReplacements(
                            text: text,
                            items: detectedItems
                        )
                        for item in detectedItems.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) where item.isMasked {
                            let replacement = replacements[item.id]
                                ?? item.alternatives.first(where: { $0.strategy == .semantic })?.text
                                ?? item.ghostToken
                            result.replaceSubrange(item.range, with: replacement)
                            applied[item.id] = replacement
                        }
                        handled = true
                    } catch {
                        print("Ollama error (\(model)): \(error), falling back")
                    }
                }
            }

            if !handled {
                // Priority 3: MLX engine (if installed)
                if let mlxEngine = mlxEngine {
                    do {
                        let replacements = try await mlxEngine.generateContextAwareReplacements(
                            text: text,
                            items: detectedItems
                        )
                        for item in detectedItems.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) where item.isMasked {
                            let replacement = replacements[item.id] ?? item.ghostToken
                            result.replaceSubrange(item.range, with: replacement)
                            applied[item.id] = replacement
                        }
                        handled = true
                    } catch {
                        print("MLX error: \(error), falling back to semantic")
                    }
                }

                if !handled {
                    // Priority 3: Semantic fallback
                    for item in detectedItems.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) where item.isMasked {
                        if let semanticAlt = item.alternatives.first(where: { $0.strategy == .semantic }) {
                            result.replaceSubrange(item.range, with: semanticAlt.text)
                            applied[item.id] = semanticAlt.text
                        } else {
                            result.replaceSubrange(item.range, with: item.ghostToken)
                            applied[item.id] = item.ghostToken
                        }
                    }
                }
            }
        }

        await MainActor.run {
            ghostedText = result
            appliedReplacements = applied
            privacyScore = calculateScore(items: detectedItems)
            GhostMappingStore.shared.storeBatch(items: detectedItems)
        }
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

    // MARK: - Manual Tagging

    /// Add a manually-tagged PII item at the specified range
    func addManualTag(range: Range<String.Index>, type: PIIType, in text: String) throws {
        guard range.lowerBound >= text.startIndex && range.upperBound <= text.endIndex else {
            throw PIIError.invalidRange
        }
        guard range.lowerBound < range.upperBound else {
            throw PIIError.emptySelection
        }
        guard !hasOverlap(newRange: range, with: detectedItems) else {
            throw PIIError.rangeOverlap
        }

        let selectedText = String(text[range])
        let alternatives = PIIItem.generateAlternatives(for: type, original: selectedText)

        let manualItem = PIIItem(
            type: type,
            range: range,
            originalText: selectedText,
            alternatives: alternatives,
            selectedAlternativeId: alternatives.first?.id ?? UUID(),
            confidence: 1.0,
            isMasked: true,
            isManual: true
        )

        detectedItems.append(manualItem)
        detectedItems.sort { $0.range.lowerBound < $1.range.lowerBound }

        remask(originalText: text)

        GhostMappingStore.shared.store(
            token: manualItem.ghostToken,
            original: selectedText,
            type: type
        )
    }

    /// Check if a new range overlaps with any existing PII items
    private func hasOverlap(newRange: Range<String.Index>, with items: [PIIItem]) -> Bool {
        items.contains { item in
            newRange.lowerBound < item.range.upperBound &&
            item.range.lowerBound < newRange.upperBound
        }
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
