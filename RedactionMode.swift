import Foundation

/// Redaction strategies for PII masking
enum RedactionMode: String, CaseIterable, Codable {
    case token = "Token"
    case semantic = "Semantic"
    case llmAware = "LLM-Aware"

    var title: String { rawValue }

    var description: String {
        switch self {
        case .token: return "Maximum privacy"
        case .semantic: return "Balanced approach"
        case .llmAware: return "Apple Intelligence"
        }
    }
}
