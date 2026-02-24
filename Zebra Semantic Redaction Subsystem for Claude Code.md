<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

# Zebra Semantic Redaction Subsystem for Claude Code

**Status**: Ready for implementation
**Date**: 2026-02-18
**Goal**: Fix the semantic redaction feature that "doesn't work well" by implementing a robust, testable subsystem.

***

## 🎯 Task Summary

Implement **SemanticRedactor**, a self-contained module that:

1. **Detects** sensitive spans beyond basic regex (projects, metrics, people, etc.)
2. **Replaces** them with **context-preserving paraphrases** or typed placeholders
3. **Scores** the result for LLM-usefulness (task completability, hallucination risk, coherence)

**Key constraint**: Fully local, hybrid rules-first + model-second approach. Model is optional; rules must work perfectly without it.

**Output**: Xcode project module with:

- Pure Swift API (structs/protocols)
- Unit tests with the exact examples below
- Mock `LocalLLMClient` for testing
- TODOs for MLX/Ollama integration

***

## 📋 API Contract

```swift
// Input
struct RedactionRequest {
    let text: String
    let taskDescription: String?        // "Summarize Q3 performance"
    let config: RedactionConfig         // Base PII + custom categories
}

// Output
struct RedactionSpan: Identifiable, Codable {
    let id = UUID()
    let range: Range<String.Index>
    let original: String
    let category: RedactionCategory     // .email, .metric, .project, etc.
    let sensitivity: SensitivityLevel   // .safe, .sensitive, .ambiguous
    let placeholder: String             // "[PROJECT_1]"
    let semanticReplacement: String?    // "single-digit growth" (preferred)
    let notes: String?                  // "Qualitative replacement preserves trend direction"
}

enum SensitivityLevel { case safe, sensitive, ambiguous }
enum RedactionCategory {
    case email, phone, metric, project, person, organization, date, custom(String)
}

struct RedactionResult: Codable {
    let originalText: String
    let redactedText: String
    let spans: [RedactionSpan]
    let taskDescription: String?
    let scores: SufficiencyScores
}

struct SufficiencyScores {
    let taskCompletability: Int     // 0-100
    let hallucinationRisk: Int      // 0-100 (lower better)
    let coherence: Int              // 0-100
    var overall: Int { min(taskCompletability, 100 - hallucinationRisk, coherence) }
}

// Usage
protocol SemanticRedactor {
    func analyzeAndRedact(_ request: RedactionRequest) async throws -> RedactionResult
}
```


***

## 🔄 Processing Pipeline (Rules-First)

```
Input text → [Phase 1: Pattern Detection] → [Phase 2: Semantic Classify] → [Phase 3: Replace] → [Phase 4: Score]
```


### Phase 1: Pattern Detection (Regex + NLTagger) – **MUST be deterministic**

- Email, phone, SSN, API keys, IP → `.sensitive` with `.email`, `.phone`, etc.
- Numbers with %/\$, dates (Q3 2024), project codes (PROJ-123) → candidate spans.
- NLTagger for names (.name), orgs (.organizationName).
- **Model cannot override**: pattern matches are always sensitive.


### Phase 2: Semantic Classification (Model or rules)

For non-exact pattern matches, classify with:

```
"Is this sensitive in corporate context? → yes/no
If yes, category? → .metric | .project | .person | .org | .customer | .internalTool"
```


### Phase 3: Semantic Replacement

```
Sensitive span → Typed placeholder + semantic alternative

"7% growth" → "[METRIC_1]" + "single-digit growth"
"Project Zebra" → "[PROJECT_1]" + "[PROJECT_1]" (keep visible)
"Laura Bianchi" → "[PERSON_1]" + "a sales team member"
```


### Phase 4: Sufficiency Scoring (Heuristics)

- **Task completability**: penalize if key slots wiped, reward qualitative surrogates.
- **Hallucination risk**: penalize exact numbers/dates without qualifiers ("around", "recent").
- **Coherence**: check grammar flow.

**Thresholds**: ≥80% = READY ✅, 50-79% = REVIEW ⚠️, <50% = STOP 🛑

***

## 🧪 Required Test Examples

Claude MUST pass these unit tests exactly:

### Test 1: Metric + Project (Primary Example)

```swift
let input = """
In Q3 2024, Project Zebra delivered 7% growth in MRR for our top 10 enterprise customers compared to Q2 2023.
"""

let task = "Summarize performance trends by project."

let expectedSpans = [
    RedactionSpan(original: "Q3 2024", category: .date, placeholder: "[QUARTER_1]", semanticReplacement: "a recent quarter"),
    RedactionSpan(original: "Project Zebra", category: .project, placeholder: "[PROJECT_1]"),
    RedactionSpan(original: "7%", category: .metric, placeholder: "[METRIC_1]", semanticReplacement: "single-digit growth"),
    RedactionSpan(original: "top 10 enterprise customers", category: .customerGroup, placeholder: "[CUSTOMERS_1]", semanticReplacement: "a set of key enterprise customers"),
    RedactionSpan(original: "Q2 2023", category: .date, placeholder: "[QUARTER_2]", semanticReplacement: "the previous period")
]

let expectedOutput = """
In a recent quarter, [PROJECT_1] delivered single-digit growth in MRR for a set of key enterprise customers compared to the previous period.
"""

let expectedScores = SufficiencyScores(taskCompletability: 90, hallucinationRisk: 20, coherence: 90) // overall: 80 ✅
```


### Test 2: People + Decision

```swift
let input = """
Sarah Chen (Head of Sales) and Miguel Torres (VP, Product) agreed that we should sunset Project Atlas for our LATAM customers in H1 2025.
"""

let expectedOutput = """
[PERSON_1] and [PERSON_2], senior leaders in sales and product, agreed that we should sunset [PROJECT_1] for a regional customer segment in the first half of a recent year.
"""
```


### Test 3: Over-Redaction Avoidance

```swift
let input = """
We saw 3 outages in January, all caused by configuration drift in our staging environment, not production.
"""

let expectedOutput = """
We saw several outages in a recent month, all caused by configuration drift in a non-production environment, not the live system.
"""
```

**Claude instruction**: Write `testProjectMetric()`, `testPeopleDecision()`, `testOutageExample()` that assert the above exactly.

***

## 🤖 Local Model Client (Mock + Real)

```swift
protocol LocalLLMClient {
    func classifySpan(span: String, context: String, task: String?) async -> SemanticClassification
    func proposeReplacement(original: String, category: RedactionCategory, context: String, task: String?) async -> String
}

struct SemanticClassification {
    let isSensitive: Bool
    let category: RedactionCategory?
    let rationale: String
}
```


### Exact Prompt Templates

**Classification** (always JSON):

```
You are a security assistant redacting corporate text.

Text: """\(context)"""
Span: """\(span)"""
Task: """\(task ?? "General LLM assistance")"""

Classify:
1. is_sensitive: true/false
2. category: "metric" | "project" | "person" | "org" | "customer" | "internalTool" | null
3. rationale: one sentence

JSON only: {"is_sensitive": true, "category": "metric", "rationale": "Percentage growth is confidential KPI"}
```

**Replacement** (natural text only):

```
Redact WITHOUT breaking usefulness.

Original sentence: """\(sentence)"""
Sensitive span: """\(span)"""
Category: \(category)
Task: """\(task ?? "General")"""

Examples:
"7% growth" → "single-digit growth"
"$1.2M revenue" → "low seven figures in revenue"
"Q3 2024" → "a recent quarter"
"Project Atlas" → "[PROJECT_1]"
"ACME Corp" → "an enterprise customer"

Replacement for span only:
```


### Mock Implementation for Tests

```swift
class MockLLMClient: LocalLLMClient {
    func classifySpan(...) async -> SemanticClassification {
        // Return exact answers matching test expectations
    }
}
```

**Real TODO**: Shell-out to Ollama (`ollama run llama3.1:3b`) or MLX Swift. Temperature=0.1, max_tokens=100.

***

## 🏗️ Implementation Order

1. **SemanticRedactorImpl.swift**: Orchestrate pipeline (rules → model → replace → score).
2. **PatternDetector.swift**: Regex + NLTagger (deterministic).
3. **MockLocalLLMClient.swift**: For tests.
4. **SemanticSynthesizer.swift**: Generate replacements (model or rule-based lookup).
5. **SufficiencyScorer.swift**: Heuristic scoring.
6. Unit tests with examples above.
7. `RedactionConfig.swift` with industry templates.

**Constraints**:

- Model optional: `config.useModel = false` → pure rules.
- Never let model override regex PII → sensitive.
- Tests must pass without model.

***

## 🚀 Paste This to Claude Code

```
Implement SemanticRedactor for Zebra macOS app using the exact API, pipeline, examples, and prompts above.

1. Create all structs/protocols exactly as specified.
2. Write unit tests that pass the 3 examples verbatim.
3. MockLLMClient returns canned answers matching tests.
4. Rules-first: regex/NLTagger always sensitive, model only for ambiguous.
5. Output: Xcode folder ready to drop into Zebra project.

Focus ONLY on this subsystem. No UI.
```

This gives Claude a narrow, testable problem with exact success criteria.[^1][^2][^3][^4][^5][^6][^7]

<div align="center">⁂</div>

[^1]: https://blog.philterd.ai/why-using-an-llm-to-identify-and-redact-pii-and-phi-is-a-bad-idea/

[^2]: https://openredaction.com

[^3]: https://github.com/OpenPipe/pii-redaction

[^4]: https://openpipe.ai/blog/pii-redact

[^5]: https://arxiv.org/html/2411.05978v1

[^6]: https://redactor.ai/blog/data-redaction-accuracy-without-losing-data-value

[^7]: https://www.caviard.ai/blog/how-to-redact-chatgpt-data-while-preserving-context-and-functionality

