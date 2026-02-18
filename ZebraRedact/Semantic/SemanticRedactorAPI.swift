import Foundation

// MARK: - Sensitivity Level

enum SensitivityLevel: String, Codable {
    case safe       // never redact
    case sensitive  // always redact (pattern-matched — model cannot override)
    case ambiguous  // needs LLM classification
}

// MARK: - Redaction Category

enum RedactionCategory {
    // Standard PII
    case email
    case phone
    case ssn
    case creditCard
    case ipAddress
    case apiKey
    // Semantic / corporate
    case metric        // "7% growth", "$1.2M revenue"
    case project       // "Project Zebra", "PROJ-123"
    case person        // personal names
    case organization  // company / org names
    case date          // "Q3 2024", "H1 2025", "January 2024"
    case customerGroup // "top 10 enterprise customers"
    case location      // addresses, cities, regions
    case custom(String)
}

extension RedactionCategory: Hashable {
    static func == (lhs: RedactionCategory, rhs: RedactionCategory) -> Bool {
        switch (lhs, rhs) {
        case (.email, .email), (.phone, .phone), (.ssn, .ssn), (.creditCard, .creditCard),
             (.ipAddress, .ipAddress), (.apiKey, .apiKey), (.metric, .metric),
             (.project, .project), (.person, .person), (.organization, .organization),
             (.date, .date), (.customerGroup, .customerGroup), (.location, .location):
            return true
        case let (.custom(a), .custom(b)):
            return a == b
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .email:         hasher.combine(0)
        case .phone:         hasher.combine(1)
        case .ssn:           hasher.combine(2)
        case .creditCard:    hasher.combine(3)
        case .ipAddress:     hasher.combine(4)
        case .apiKey:        hasher.combine(5)
        case .metric:        hasher.combine(6)
        case .project:       hasher.combine(7)
        case .person:        hasher.combine(8)
        case .organization:  hasher.combine(9)
        case .date:          hasher.combine(10)
        case .customerGroup: hasher.combine(11)
        case .location:      hasher.combine(12)
        case .custom(let s): hasher.combine(99); hasher.combine(s)
        }
    }
}

extension RedactionCategory {
    /// Bracket prefix used in placeholder tokens, e.g. "PROJECT" → "[PROJECT_1]"
    var placeholderPrefix: String {
        switch self {
        case .email:         return "EMAIL"
        case .phone:         return "PHONE"
        case .ssn:           return "SSN"
        case .creditCard:    return "CARD"
        case .ipAddress:     return "IP"
        case .apiKey:        return "KEY"
        case .metric:        return "METRIC"
        case .project:       return "PROJECT"
        case .person:        return "PERSON"
        case .organization:  return "ORG"
        case .date:          return "QUARTER"
        case .customerGroup: return "CUSTOMERS"
        case .location:      return "LOCATION"
        case .custom(let s): return s.uppercased().replacingOccurrences(of: " ", with: "_")
        }
    }

    /// Whether this category is detected by deterministic rules (no model needed)
    var isDeterministic: Bool {
        switch self {
        case .customerGroup, .custom: return false
        default: return true
        }
    }

    /// Map to existing PIIType for bridge compatibility
    var asPIIType: PIIType {
        switch self {
        case .email:        return .email
        case .phone:        return .phone
        case .ssn:          return .ssn
        case .creditCard:   return .creditCard
        case .ipAddress:    return .ipAddress
        case .apiKey:       return .apiKey
        case .person:       return .name
        case .location:     return .address
        default:            return .custom
        }
    }

    /// All deterministic categories (no LLM required)
    static var allDeterministic: [RedactionCategory] {
        [.email, .phone, .ssn, .creditCard, .ipAddress, .apiKey,
         .metric, .project, .person, .organization, .date, .location]
    }
}

// MARK: - Redaction Span

struct RedactionSpan: Identifiable {
    let id: UUID
    let range: Range<String.Index>
    let original: String
    let category: RedactionCategory
    let sensitivity: SensitivityLevel
    /// Token-style placeholder: "[PROJECT_1]"
    let placeholder: String
    /// Preferred natural-language replacement: "single-digit growth" (nil → use placeholder)
    let semanticReplacement: String?
    let notes: String?

    init(
        id: UUID = UUID(),
        range: Range<String.Index>,
        original: String,
        category: RedactionCategory,
        sensitivity: SensitivityLevel = .sensitive,
        placeholder: String,
        semanticReplacement: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.range = range
        self.original = original
        self.category = category
        self.sensitivity = sensitivity
        self.placeholder = placeholder
        self.semanticReplacement = semanticReplacement
        self.notes = notes
    }

    /// Text placed in the redacted output: semantic replacement preferred, placeholder fallback
    var effectiveReplacement: String {
        semanticReplacement ?? placeholder
    }
}

// MARK: - Request / Result

struct RedactionRequest {
    let text: String
    let taskDescription: String?
    let config: RedactionConfig

    init(text: String, taskDescription: String? = nil, config: RedactionConfig = .standard) {
        self.text = text
        self.taskDescription = taskDescription
        self.config = config
    }
}

struct RedactionResult {
    let originalText: String
    let redactedText: String
    /// Sensitive spans sorted by position in originalText
    let spans: [RedactionSpan]
    let taskDescription: String?
    let scores: SufficiencyScores
}

// MARK: - Sufficiency Scores

struct SufficiencyScores {
    let taskCompletability: Int  // 0-100 (higher better)
    let hallucinationRisk: Int   // 0-100 (lower better)
    let coherence: Int           // 0-100 (higher better)

    var overall: Int {
        min(taskCompletability, 100 - hallucinationRisk, coherence)
    }

    var status: SufficiencyStatus {
        switch overall {
        case 80...100: return .ready
        case 50..<80:  return .review
        default:       return .stop
        }
    }
}

enum SufficiencyStatus {
    case ready   // ≥80% ✅
    case review  // 50-79% ⚠️
    case stop    // <50%  🛑
}

// MARK: - Protocol

protocol SemanticRedactor {
    func analyzeAndRedact(_ request: RedactionRequest) async throws -> RedactionResult
}
