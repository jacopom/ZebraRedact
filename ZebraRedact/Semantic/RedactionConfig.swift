import Foundation

struct RedactionConfig {
    var enabledCategories: Set<RedactionCategory>
    /// When true, the LLM client is used for Phase 2 (classify ambiguous spans)
    /// and Phase 3 (enhance rule-based replacements). Rules always run regardless.
    var useModel: Bool
    /// Input text is truncated to this many characters before LLM calls
    var maxTextLength: Int

    // MARK: - Presets

    /// Deterministic only — no LLM, covers all structured PII + semantic categories
    static var standard: RedactionConfig {
        RedactionConfig(
            enabledCategories: Set(RedactionCategory.allDeterministic),
            useModel: false,
            maxTextLength: 3000
        )
    }

    /// Full pipeline with LLM for ambiguous spans (customerGroup, custom)
    static var withModel: RedactionConfig {
        RedactionConfig(
            enabledCategories: Set(RedactionCategory.allDeterministic + [.customerGroup]),
            useModel: true,
            maxTextLength: 3000
        )
    }

    /// GDPR — name, contact, financial identifiers
    static var gdpr: RedactionConfig {
        RedactionConfig(
            enabledCategories: [.email, .phone, .ssn, .creditCard, .person, .location],
            useModel: false,
            maxTextLength: 3000
        )
    }

    /// HIPAA — health-oriented: name, contact, SSN, location, dates
    static var hipaa: RedactionConfig {
        RedactionConfig(
            enabledCategories: [.email, .phone, .ssn, .person, .location, .date],
            useModel: false,
            maxTextLength: 3000
        )
    }

    /// Corporate — full pipeline including projects, metrics, customer groups
    static var corporate: RedactionConfig {
        RedactionConfig(
            enabledCategories: Set(RedactionCategory.allDeterministic + [.customerGroup]),
            useModel: true,
            maxTextLength: 3000
        )
    }
}
