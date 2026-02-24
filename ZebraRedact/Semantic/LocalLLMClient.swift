import Foundation

// MARK: - Semantic Classification

struct SemanticClassificationResult {
    let isSensitive: Bool
    let category: RedactionCategory?
    let rationale: String
}

// MARK: - Protocol

protocol LocalLLMClient {
    /// Classify whether a span is sensitive in the given corporate context.
    /// Model CANNOT override pattern-matched spans (they are always .sensitive).
    func classifySpan(span: String, context: String, task: String?) async -> SemanticClassificationResult

    /// Propose a natural-language replacement for a sensitive span.
    /// Returns nil if the placeholder should be used as-is.
    func proposeReplacement(
        original: String,
        category: RedactionCategory,
        context: String,
        task: String?
    ) async -> String?
}

// MARK: - Null Client (no model configured)

final class NullLLMClient: LocalLLMClient {
    func classifySpan(span: String, context: String, task: String?) async -> SemanticClassificationResult {
        SemanticClassificationResult(isSensitive: false, category: nil, rationale: "No model configured")
    }

    func proposeReplacement(original: String, category: RedactionCategory, context: String, task: String?) async -> String? {
        nil
    }
}

// MARK: - Mock Client (unit tests)

final class MockLLMClient: LocalLLMClient {
    private let classifications: [String: SemanticClassificationResult]
    private let replacements: [String: String]

    init(
        classifications: [String: SemanticClassificationResult] = [:],
        replacements: [String: String] = [:]
    ) {
        self.classifications = classifications
        self.replacements = replacements
    }

    func classifySpan(span: String, context: String, task: String?) async -> SemanticClassificationResult {
        classifications[span] ?? SemanticClassificationResult(
            isSensitive: false, category: nil, rationale: "Mock: no canned answer for '\(span)'"
        )
    }

    func proposeReplacement(original: String, category: RedactionCategory, context: String, task: String?) async -> String? {
        replacements[original]
    }

    // MARK: - Canned Clients for Unit Tests

    /// Test 1: metric + project (Q3 example)
    static var test1Client: MockLLMClient {
        MockLLMClient(
            classifications: [
                "our top 10 enterprise customers": SemanticClassificationResult(
                    isSensitive: true,
                    category: .customerGroup,
                    rationale: "Customer group reveals business scale and segment"
                ),
            ],
            replacements: [
                "our top 10 enterprise customers": "a set of key enterprise customers",
            ]
        )
    }

    /// Test 2: people + decision
    static var test2Client: MockLLMClient {
        MockLLMClient(
            classifications: [
                "LATAM customers": SemanticClassificationResult(
                    isSensitive: true,
                    category: .customerGroup,
                    rationale: "Regional customer segment reveals market coverage"
                ),
            ],
            replacements: [
                "LATAM customers": "a regional customer segment",
            ]
        )
    }

    /// Test 3: over-redaction avoidance (outages + environments)
    static var test3Client: MockLLMClient {
        MockLLMClient(
            classifications: [
                "our staging environment": SemanticClassificationResult(
                    isSensitive: true,
                    category: .custom("environment"),
                    rationale: "Internal infrastructure reference"
                ),
                "staging environment": SemanticClassificationResult(
                    isSensitive: true,
                    category: .custom("environment"),
                    rationale: "Internal infrastructure reference"
                ),
                "production": SemanticClassificationResult(
                    isSensitive: true,
                    category: .custom("environment"),
                    rationale: "Live system reference"
                ),
            ],
            replacements: [
                "our staging environment": "a non-production environment",
                "staging environment": "a non-production environment",
                "production": "the live system",
            ]
        )
    }
}

// MARK: - Ollama Adapter (TODO: wire to existing OllamaEngine)
//
// Uncomment and complete to use real Ollama inference:
//
// final class OllamaSemanticClient: LocalLLMClient {
//
//     // Classification prompt template (from spec):
//     private func classificationPrompt(span: String, context: String, task: String?) -> String {
//         """
//         You are a security assistant redacting corporate text.
//
//         Text: \"\"\"\(context)\"\"\"
//         Span: \"\"\"\(span)\"\"\"
//         Task: \"\"\"\(task ?? "General LLM assistance")\"\"\"
//
//         Classify:
//         1. is_sensitive: true/false
//         2. category: "metric" | "project" | "person" | "org" | "customer" | "internalTool" | null
//         3. rationale: one sentence
//
//         JSON only: {"is_sensitive": true, "category": "metric", "rationale": "Percentage growth is confidential KPI"}
//         """
//     }
//
//     // Replacement prompt template (from spec):
//     private func replacementPrompt(original: String, category: RedactionCategory, sentence: String, task: String?) -> String {
//         """
//         Redact WITHOUT breaking usefulness.
//
//         Original sentence: \"\"\"\(sentence)\"\"\"
//         Sensitive span: \"\"\"\(original)\"\"\"
//         Category: \(category.placeholderPrefix)
//         Task: \"\"\"\(task ?? "General")\"\"\"
//
//         Examples:
//         "7% growth" → "single-digit growth"
//         "$1.2M revenue" → "low seven figures in revenue"
//         "Q3 2024" → "a recent quarter"
//         "Project Atlas" → "[PROJECT_1]"
//         "ACME Corp" → "an enterprise customer"
//
//         Replacement for span only:
//         """
//     }
//
//     func classifySpan(span: String, context: String, task: String?) async -> SemanticClassificationResult {
//         guard let model = OllamaEngine.activeModel else {
//             return SemanticClassificationResult(isSensitive: false, category: nil, rationale: "No model")
//         }
//         let prompt = classificationPrompt(span: span, context: context, task: task)
//         guard let raw = try? await OllamaEngine.generate(model: model, prompt: prompt),
//               let data = OllamaEngine.extractJSONObject(from: raw),
//               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
//               let isSensitive = json["is_sensitive"] as? Bool else {
//             return SemanticClassificationResult(isSensitive: false, category: nil, rationale: "Parse failed")
//         }
//         let cat = (json["category"] as? String).flatMap { RedactionCategory(ollamaLabel: $0) }
//         let rationale = json["rationale"] as? String ?? ""
//         return SemanticClassificationResult(isSensitive: isSensitive, category: cat, rationale: rationale)
//     }
//
//     func proposeReplacement(original: String, category: RedactionCategory, context: String, task: String?) async -> String? {
//         guard let model = OllamaEngine.activeModel else { return nil }
//         let prompt = replacementPrompt(original: original, category: category, sentence: context, task: task)
//         return try? await OllamaEngine.generate(model: model, prompt: prompt)
//             .trimmingCharacters(in: .whitespacesAndNewlines)
//     }
// }
