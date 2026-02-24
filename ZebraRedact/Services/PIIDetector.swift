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
    @Published var redactionMode: RedactionMode = .token {
        didSet {
            UserDefaults.standard.set(redactionMode.rawValue, forKey: "redactionMode")
        }
    }
    @Published var semanticContext: SemanticContext?
    /// Maps each item ID → the text actually placed in ghostedText for that item
    @Published var appliedReplacements: [UUID: String] = [:]

    private let detector = NLTaggerDetector()
    private var mlxEngine: MLXContextEngine?
    private var modelManager: ModelManager?

    /// Type-erased FoundationModelEngine (macOS 26+)
    private var foundationEngine: AnyObject?

    /// Cache of LLM-Aware results keyed by input text — avoids re-running the LLM
    /// when the user switches away from LLM-Aware mode and then back.
    private var llmResultCache: (inputText: String, items: [PIIItem], ghosted: String, applied: [UUID: String])? = nil

    init(modelManager: ModelManager? = nil) {
        self.modelManager = modelManager
        // Always initialize mlxEngine — SemanticAnalyzer (NaturalLanguage-based) works
        // without a model manager and produces context-aware structural replacements
        // (e.g. "project lead", "email address") that are distinct from Fake Data's random pool.
        self.mlxEngine = MLXContextEngine(modelManager: modelManager)
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            foundationEngine = FoundationModelEngine()
        }
        #endif
        // Restore the last-used mode; default is .token on first launch.
        if let saved = UserDefaults.standard.string(forKey: "redactionMode"),
           let mode = RedactionMode(rawValue: saved) {
            redactionMode = mode
        }
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

        // Preserve manual tags across re-scans: save them before detection runs.
        // After detecting auto items, we re-anchor each manual tag by searching
        // for its original text in the new input.  Tags whose text was deleted
        // are dropped; tags for text still present are re-added with their
        // existing UUID (so appliedReplacements entries survive unchanged).
        let previousManualItems = detectedItems.filter { $0.isManual }

        // Invalidate LLM cache whenever the source text changes
        if llmResultCache?.inputText != text { llmResultCache = nil }

        let allItems = detector.detect(in: text)
        let filtered = allItems.filter { enabledCategories.contains($0.type) }

        // Re-anchor surviving manual items
        var preserved: [PIIItem] = []
        for manual in previousManualItems {
            guard let newRange = text.range(of: manual.originalText, options: .literal) else { continue }
            let overlaps = filtered.contains { s in
                newRange.lowerBound < s.range.upperBound && s.range.lowerBound < newRange.upperBound
            }
            guard !overlaps else { continue }
            preserved.append(manual.withRange(newRange))
        }

        let combined = (filtered + preserved)
            .sorted { $0.range.lowerBound < $1.range.lowerBound }

        // Don't update detectedItems here — update it atomically with ghostedText
        // in applyMasking to avoid a window where items exist but text is stale.
        Task {
            await applyMasking(to: text, newItems: combined)
            await MainActor.run {
                isProcessing = false
            }
        }
    }

    private func applyMasking(to text: String, newItems: [PIIItem]) async {
        var items = newItems
        var result = text
        var applied: [UUID: String] = [:]

        switch redactionMode {
        case .token:
            for item in items.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) where item.isMasked {
                result.replaceSubrange(item.range, with: item.ghostToken)
                applied[item.id] = item.ghostToken
            }

        case .semantic:
            for item in items.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) where item.isMasked {
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
                        existingItems: items
                    )
                    if !additionalItems.isEmpty {
                        items = (items + additionalItems)
                            .sorted { $0.range.lowerBound < $1.range.lowerBound }
                    }

                    // Generate context-preserving replacements
                    let replacements = try await engine.generateContextAwareReplacements(
                        text: text,
                        items: items
                    )
                    for item in items.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) where item.isMasked {
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
                            existingItems: items
                        )
                        if !additionalItems.isEmpty {
                            items = (items + additionalItems)
                                .sorted { $0.range.lowerBound < $1.range.lowerBound }
                        }
                        let replacements = try await OllamaEngine.generateContextAwareReplacements(
                            text: text,
                            items: items
                        )
                        for item in items.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) where item.isMasked {
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
                            items: items
                        )
                        for item in items.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) where item.isMasked {
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
                    // Priority 4: Semantic fallback
                    for item in items.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) where item.isMasked {
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
            // Cache LLM-Aware results so re-entering the mode doesn't re-run the LLM.
            if redactionMode == .llmAware {
                llmResultCache = (inputText: text, items: items, ghosted: result, applied: applied)
            }
            // Update detectedItems and ghostedText together so ClickableTokenTextView
            // always sees a consistent state — no window where items exist in a stale text.
            detectedItems = items
            ghostedText = result
            appliedReplacements = applied
            privacyScore = calculateScore(items: items)
            // Store the ACTUAL replacement (not ghostToken) so re-hydration can reverse
            // semantic/LLM replacements like "Emma Wilson" back to the original name.
            for item in items where item.isMasked {
                let replacement = applied[item.id] ?? item.ghostToken
                GhostMappingStore.shared.store(token: replacement, original: item.originalText, type: item.type)
            }
        }
    }

    // MARK: - Remask on Mode Switch

    /// Re-render the output for the current `redactionMode` without re-running detection.
    /// For LLM-Aware mode, uses the cached result if the input text is unchanged.
    func remaskCurrentItems(originalText: String) {
        guard !originalText.isEmpty else { return }

        // LLM-Aware: use the cache — avoid paying the LLM cost again
        if redactionMode == .llmAware,
           let cache = llmResultCache,
           cache.inputText == originalText {
            detectedItems = cache.items
            ghostedText = cache.ghosted
            appliedReplacements = cache.applied
            privacyScore = calculateScore(items: cache.items)
            return
        }

        // All other modes: just re-apply masking to existing items (no re-detection)
        isProcessing = true
        Task {
            await applyMasking(to: originalText, newItems: detectedItems)
            await MainActor.run { isProcessing = false }
        }
    }

    // MARK: - Remove Item (untokenize)

    /// Remove a PII item and rebuild the output text, restoring the original value.
    func removeItem(_ item: PIIItem, originalText: String) {
        appliedReplacements.removeValue(forKey: item.id)
        detectedItems.removeAll { $0.id == item.id }
        let (text, applied) = buildMaskedText(from: originalText,
                                              items: detectedItems,
                                              replacements: appliedReplacements)
        ghostedText = text
        appliedReplacements = applied
        privacyScore = calculateScore(items: detectedItems)
    }

    // MARK: - Toggle Individual Items

    func toggleItem(_ item: PIIItem) {
        guard let idx = detectedItems.firstIndex(where: { $0.id == item.id }) else { return }
        detectedItems[idx].isMasked.toggle()
    }

    // MARK: - Re-mask After Toggling

    /// Rebuild ghostedText from originalText, preserving existing replacements from
    /// appliedReplacements (semantic fakes, LLM output, etc.) and falling back to
    /// item.ghostToken for any item that has no existing entry.
    /// Always updates appliedReplacements so ClickableTokenTextView stays in sync.
    func remask(originalText: String) {
        let (text, applied) = buildMaskedText(from: originalText,
                                              items: detectedItems,
                                              replacements: appliedReplacements)
        ghostedText = text
        appliedReplacements = applied
        privacyScore = calculateScore(items: detectedItems)
    }

    /// Build the redacted string by walking *forward* through `originalText` and
    /// substituting each masked item's replacement inline.
    ///
    /// This avoids the crash-prone "reverse replaceSubrange" pattern: after each
    /// replaceSubrange call the underlying buffer can be reallocated, and String.Index
    /// values from the original string may become out-of-bounds in the mutated copy
    /// when accumulated length deltas push a later item's upperBound past endIndex.
    /// By always indexing into the immutable `originalText` we guarantee every
    /// stored Range<String.Index> is valid for the lifetime of the loop.
    private func buildMaskedText(from originalText: String,
                                 items: [PIIItem],
                                 replacements: [UUID: String]) -> (text: String, applied: [UUID: String]) {
        let sorted = items
            .filter { $0.isMasked }
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
        var result = ""
        var applied: [UUID: String] = [:]
        var cursor = originalText.startIndex
        for item in sorted {
            guard item.range.lowerBound >= cursor,
                  item.range.upperBound <= originalText.endIndex else { continue }
            result += originalText[cursor..<item.range.lowerBound]
            let replacement = replacements[item.id] ?? item.ghostToken
            result += replacement
            applied[item.id] = replacement
            cursor = item.range.upperBound
        }
        result += originalText[cursor...]
        return (result, applied)
    }

    /// Change one item's replacement to a specific alternative, then rebuild.
    func applySelectedAlternative(_ alternative: RedactionAlternative,
                                  forItemId itemId: UUID,
                                  originalText: String) {
        guard let index = detectedItems.firstIndex(where: { $0.id == itemId }) else { return }
        detectedItems[index].selectedAlternativeId = alternative.id
        appliedReplacements[itemId] = alternative.text   // must happen BEFORE remask
        remask(originalText: originalText)
    }

    // MARK: - Retag (change type of existing item)

    /// Change the PII type of an existing item, regenerate its alternatives, and remask.
    /// Returns the updated PIIItem so the caller can refresh any binding pointing at the old value.
    @discardableResult
    func retagItem(_ item: PIIItem, as newType: PIIType, originalText: String) -> PIIItem? {
        guard let index = detectedItems.firstIndex(where: { $0.id == item.id }) else { return nil }
        let newAlts = PIIItem.generateAlternatives(for: newType, original: item.originalText)
        guard let firstAlt = newAlts.first else { return nil }

        let retagged = PIIItem(
            preservingId: item.id,
            type: newType,
            range: item.range,
            originalText: item.originalText,
            alternatives: newAlts,
            selectedAlternativeId: firstAlt.id,
            confidence: item.confidence,
            isMasked: item.isMasked,
            isManual: item.isManual
        )
        detectedItems[index] = retagged
        appliedReplacements[item.id] = firstAlt.text
        remask(originalText: originalText)
        GhostMappingStore.shared.store(token: firstAlt.text, original: item.originalText, type: newType)
        return retagged
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

        // Compute the replacement for this new item based on the current mode,
        // and seed it into appliedReplacements BEFORE calling remask so that
        // remask (which reads appliedReplacements) sees it immediately.
        let newReplacement: String
        switch redactionMode {
        case .token:
            newReplacement = manualItem.ghostToken
        case .semantic, .llmAware:
            newReplacement = manualItem.alternatives.first(where: { $0.strategy == .semantic })?.text
                ?? manualItem.ghostToken
        }
        appliedReplacements[manualItem.id] = newReplacement

        detectedItems.append(manualItem)
        detectedItems.sort { $0.range.lowerBound < $1.range.lowerBound }

        remask(originalText: text)

        GhostMappingStore.shared.store(
            token: newReplacement,
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
