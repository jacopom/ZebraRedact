import Foundation

// MARK: - RedactionResult → PIIItem Bridge
//
// This file is the migration adapter.
// When you're ready to switch PIIDetector's .semantic mode to the new pipeline:
//
//   1. Call `SemanticRedactorImpl(llmClient: ...).analyzeAndRedact(request)`
//   2. Convert the result with `result.toPIIItems(in: text)`
//   3. Use `result.toAppliedReplacements(piiItems:)` for the appliedReplacements dict
//
// See the commented-out block in PIIDetector.applyMasking for the exact drop-in.

extension RedactionResult {

    /// Convert each span to a PIIItem compatible with the existing detection pipeline.
    /// The semantic replacement (if any) becomes the preferred alternative.
    func toPIIItems(in text: String) -> [PIIItem] {
        return spans.map { span in
            let piiType = span.category.asPIIType

            // Build alternatives: semantic first (preferred), then token placeholder
            var alts: [RedactionAlternative] = []
            if let semantic = span.semanticReplacement {
                alts.append(RedactionAlternative(
                    strategy: .semantic,
                    text: semantic,
                    description: "Qualitative replacement"
                ))
            }
            alts.append(RedactionAlternative(
                strategy: .token,
                text: span.placeholder,
                description: "Token placeholder"
            ))

            return PIIItem(
                type: piiType,
                range: span.range,
                originalText: span.original,
                alternatives: alts,
                selectedAlternativeId: alts.first!.id,
                confidence: 0.9,
                isMasked: true
            )
        }
    }

    /// Build the appliedReplacements dictionary from a matched set of PIIItems.
    /// Items and spans must be in the same order (both sorted by position).
    func toAppliedReplacements(piiItems: [PIIItem]) -> [UUID: String] {
        Dictionary(
            uniqueKeysWithValues: zip(piiItems, spans).map { item, span in
                (item.id, span.effectiveReplacement)
            }
        )
    }
}

// MARK: - PIIDetector Migration Comment
//
// To replace the current .semantic path in PIIDetector.applyMasking with the new
// SemanticRedactorImpl, substitute the existing `case .semantic:` block with:
//
// case .semantic:
//     let llmClient: any LocalLLMClient = OllamaEngine.activeModel != nil
//         ? NullLLMClient()   // swap in OllamaSemanticClient() once wired
//         : NullLLMClient()
//     let config = RedactionConfig(
//         enabledCategories: Set(items.map(\.type).map { _ in RedactionCategory.person }),  // map from enabledCategories
//         useModel: OllamaEngine.activeModel != nil,
//         maxTextLength: 3000
//     )
//     let request = RedactionRequest(text: text, taskDescription: nil, config: .withModel)
//     let impl = SemanticRedactorImpl(llmClient: llmClient)
//     if let result = try? await impl.analyzeAndRedact(request) {
//         let newItems = result.toPIIItems(in: text)
//         let newApplied = result.toAppliedReplacements(piiItems: newItems)
//         await MainActor.run {
//             detectedItems = newItems
//             redactedText = result.redactedText
//             appliedReplacements = newApplied
//             privacyScore = calculateScore(items: newItems)
//             TokenMappingStore.shared.storeBatch(items: newItems)
//         }
//         return
//     }
//     // fallback to existing logic below...
