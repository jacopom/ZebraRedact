import Foundation

/// Redaction strategy for PII masking — token mode only
enum RedactionMode: String, CaseIterable, Codable {
    case token = "Token"

    var description: String { "Maximum privacy" }
}
