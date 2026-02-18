import Foundation

/// Orchestrates the four-phase pipeline:
///   Phase 1 — PatternDetector (regex + NLTagger, deterministic)
///   Phase 2 — LLM classification of ambiguous spans (optional, config.useModel)
///   Phase 3 — Semantic replacement (rule-based first, LLM enhancement optional)
///   Phase 4 — SufficiencyScorer
final class SemanticRedactorImpl: SemanticRedactor {

    private let patternDetector = PatternDetector()
    var llmClient: any LocalLLMClient

    init(llmClient: any LocalLLMClient = NullLLMClient()) {
        self.llmClient = llmClient
    }

    // MARK: - analyzeAndRedact

    func analyzeAndRedact(_ request: RedactionRequest) async throws -> RedactionResult {
        let text = String(request.text.prefix(request.config.maxTextLength))

        // Phase 1: Deterministic pattern detection
        var spans = patternDetector.detect(in: text)
            .filter { request.config.enabledCategories.contains($0.category) }

        // Phase 2: LLM-based classification of ambiguous candidate spans
        if request.config.useModel {
            let extra = await classifyAmbiguousSpans(
                text: text,
                existingSpans: spans,
                task: request.taskDescription,
                config: request.config
            )
            if !extra.isEmpty {
                spans = mergeAndSort(spans, extra)
            }
        }

        // Phase 3: LLM replacement enhancement (overrides rule-based when better)
        if request.config.useModel {
            spans = await enhanceReplacements(spans: spans, text: text, task: request.taskDescription)
        }

        // Build redacted text (apply in reverse order to preserve ranges)
        var redactedText = text
        for span in spans.filter({ $0.sensitivity == .sensitive })
                         .sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            redactedText.replaceSubrange(span.range, with: span.effectiveReplacement)
        }

        // Phase 4: Score
        let scores = SufficiencyScorer.score(
            original: text,
            redacted: redactedText,
            spans: spans,
            task: request.taskDescription
        )

        return RedactionResult(
            originalText: text,
            redactedText: redactedText,
            spans: spans.filter { $0.sensitivity == .sensitive }
                        .sorted { $0.range.lowerBound < $1.range.lowerBound },
            taskDescription: request.taskDescription,
            scores: scores
        )
    }

    // MARK: - Phase 2: Classify Ambiguous Spans

    /// Scans the text for spans that the model should classify as potentially sensitive.
    /// Currently the model identifies customer groups and internal tool names.
    private func classifyAmbiguousSpans(
        text: String,
        existingSpans: [RedactionSpan],
        task: String?,
        config: RedactionConfig
    ) async -> [RedactionSpan] {
        // Heuristic: extract noun phrases not yet covered by regex
        // For a real implementation this would use NLP chunking or sliding window
        // Here we check a curated list of patterns that benefit from semantic context
        let candidatePatterns: [NSRegularExpression] = [
            // "top N <adj> customers/clients/accounts"
            try! NSRegularExpression(pattern: #"\btop\s+\d+\s+\w+\s+(?:customers?|clients?|accounts?|enterprises?)\b"#, options: .caseInsensitive),
            // "<region> customers/clients"
            try! NSRegularExpression(pattern: #"\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)?\s+(?:customers?|clients?)\b"#),
        ]

        var candidates: [(range: Range<String.Index>, text: String)] = []
        let nsRange = NSRange(text.startIndex..., in: text)
        for pattern in candidatePatterns {
            for match in pattern.matches(in: text, range: nsRange) {
                guard let range = Range(match.range, in: text) else { continue }
                let spanText = String(text[range])
                // Skip if already covered
                let alreadyCovered = existingSpans.contains { s in
                    range.lowerBound < s.range.upperBound && s.range.lowerBound < range.upperBound
                }
                guard !alreadyCovered else { continue }
                candidates.append((range, spanText))
            }
        }

        // Ask model to classify each candidate
        var newSpans: [RedactionSpan] = []
        var customerGroupCount = existingSpans.filter { $0.category == .customerGroup }.count

        for candidate in candidates {
            let classification = await llmClient.classifySpan(
                span: candidate.text,
                context: text,
                task: task
            )
            guard classification.isSensitive,
                  let category = classification.category,
                  config.enabledCategories.contains(category)
            else { continue }

            customerGroupCount += 1
            let placeholder = "[\(category.placeholderPrefix)_\(customerGroupCount)]"
            let semantic = await llmClient.proposeReplacement(
                original: candidate.text,
                category: category,
                context: text,
                task: task
            ) ?? SemanticSynthesizer.synthesize(original: candidate.text, category: category, spanIndex: customerGroupCount - 1)

            newSpans.append(RedactionSpan(
                range: candidate.range,
                original: candidate.text,
                category: category,
                sensitivity: .sensitive,
                placeholder: placeholder,
                semanticReplacement: semantic,
                notes: classification.rationale
            ))
        }

        return newSpans
    }

    // MARK: - Phase 3: LLM Replacement Enhancement

    /// For spans where the rule-based replacement might be generic, ask the model for better wording.
    private func enhanceReplacements(
        spans: [RedactionSpan],
        text: String,
        task: String?
    ) async -> [RedactionSpan] {
        var enhanced = spans
        for i in enhanced.indices {
            let span = enhanced[i]
            // Only enhance if there's no high-quality rule-based replacement
            // (model enhancement is most valuable for .organization, .person with title context)
            guard span.category == .organization || span.semanticReplacement == nil else { continue }
            if let proposed = await llmClient.proposeReplacement(
                original: span.original,
                category: span.category,
                context: text,
                task: task
            ) {
                enhanced[i] = RedactionSpan(
                    id: span.id,
                    range: span.range,
                    original: span.original,
                    category: span.category,
                    sensitivity: span.sensitivity,
                    placeholder: span.placeholder,
                    semanticReplacement: proposed,
                    notes: span.notes
                )
            }
        }
        return enhanced
    }

    // MARK: - Helpers

    private func mergeAndSort(_ a: [RedactionSpan], _ b: [RedactionSpan]) -> [RedactionSpan] {
        var result = a
        for span in b {
            let overlaps = result.contains { s in
                span.range.lowerBound < s.range.upperBound && s.range.lowerBound < span.range.upperBound
            }
            if !overlaps { result.append(span) }
        }
        return result.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
}
