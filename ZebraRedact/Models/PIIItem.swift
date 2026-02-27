import Foundation
import SwiftUI

/// Redaction strategies for PII masking (DeepL-inspired alternatives)
enum RedactionStrategy: String, CaseIterable, Codable {
    case token = "Token"
    case semantic = "Semantic"
    case partial = "Partial"
    case contextual = "Contextual"
    case generic = "Generic"
}

/// Alternative ways to redact a PII item
struct RedactionAlternative: Identifiable, Codable {
    let id: UUID
    let strategy: RedactionStrategy
    let text: String
    let description: String

    init(strategy: RedactionStrategy, text: String, description: String) {
        self.id = UUID()
        self.strategy = strategy
        self.text = text
        self.description = description
    }
}

/// Represents a detected PII (Personally Identifiable Information) item in text.
enum PIIType: String, CaseIterable, Identifiable, Codable {
    case email = "Email"
    case phone = "Phone"
    case creditCard = "Credit Card"
    case ssn = "SSN"
    case ipAddress = "IP Address"
    case apiKey = "API Key"
    case date = "Date"
    case name = "Name"
    case address = "Address"
    case custom = "Custom"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .email: return "envelope.fill"
        case .phone: return "phone.fill"
        case .creditCard: return "creditcard.fill"
        case .ssn: return "lock.shield.fill"
        case .ipAddress: return "network"
        case .apiKey: return "key.fill"
        case .date: return "calendar"
        case .name: return "person.fill"
        case .address: return "mappin.and.ellipse"
        case .custom: return "tag.fill"
        }
    }

    /// Soft pastel palette — legible highlights without visual noise.
    var highlightColor: Color {
        switch self {
        case .email:      return Color(red: 0.60, green: 0.78, blue: 0.98)  // Cornflower blue
        case .phone:      return Color(red: 0.65, green: 0.88, blue: 0.98)  // Sky blue
        case .creditCard: return Color(red: 0.98, green: 0.67, blue: 0.72)  // Rose
        case .ssn:        return Color(red: 0.99, green: 0.87, blue: 0.55)  // Amber
        case .ipAddress:  return Color(red: 0.80, green: 0.72, blue: 0.99)  // Lavender
        case .apiKey:     return Color(red: 0.99, green: 0.95, blue: 0.58)  // Lemon
        case .date:       return Color(red: 0.77, green: 0.71, blue: 0.99)  // Soft lavender
        case .name:       return Color(red: 0.58, green: 0.95, blue: 0.84)  // Mint
        case .address:    return Color(red: 0.64, green: 0.93, blue: 0.70)  // Sage
        case .custom:     return Color(red: 0.82, green: 0.82, blue: 0.86)  // Stone
        }
    }
}

struct PIIItem: Identifiable, Equatable {
    let id: UUID
    let type: PIIType
    let range: Range<String.Index>
    let originalText: String
    var alternatives: [RedactionAlternative]
    var selectedAlternativeId: UUID
    var confidence: Double
    var isMasked: Bool
    var isManual: Bool

    /// The currently selected ghost token
    var token: String {
        alternatives.first { $0.id == selectedAlternativeId }?.text ?? "[REDACTED]"
    }

    /// The currently selected strategy
    var selectedStrategy: RedactionStrategy {
        alternatives.first { $0.id == selectedAlternativeId }?.strategy ?? .token
    }

    init(
        type: PIIType,
        range: Range<String.Index>,
        originalText: String,
        alternatives: [RedactionAlternative],
        selectedAlternativeId: UUID,
        confidence: Double = 1.0,
        isMasked: Bool = true,
        isManual: Bool = false
    ) {
        self.id = UUID()
        self.type = type
        self.range = range
        self.originalText = originalText
        self.alternatives = alternatives
        self.selectedAlternativeId = selectedAlternativeId
        self.confidence = confidence
        self.isMasked = isMasked
        self.isManual = isManual
    }

    /// Copy an item with an updated range, preserving its UUID so that `appliedReplacements`
    /// entries (keyed by `id`) survive a re-scan when the user edits surrounding text.
    func withRange(_ newRange: Range<String.Index>) -> PIIItem {
        PIIItem(preservingId: id, type: type, range: newRange, originalText: originalText,
                alternatives: alternatives, selectedAlternativeId: selectedAlternativeId,
                confidence: confidence, isMasked: isMasked, isManual: isManual)
    }

    /// Internal initializer that preserves an existing UUID (used when re-anchoring
    /// a manual tag after the surrounding text changes).
    init(preservingId existingId: UUID, type: PIIType, range: Range<String.Index>,
         originalText: String, alternatives: [RedactionAlternative],
         selectedAlternativeId: UUID, confidence: Double = 1.0,
         isMasked: Bool = true, isManual: Bool = true) {
        self.id = existingId
        self.type = type
        self.range = range
        self.originalText = originalText
        self.alternatives = alternatives
        self.selectedAlternativeId = selectedAlternativeId
        self.confidence = confidence
        self.isMasked = isMasked
        self.isManual = isManual
    }

    /// Generate default alternatives for this PII type
    static func generateAlternatives(for type: PIIType, original: String) -> [RedactionAlternative] {
        let tokenId = UUID().uuidString.prefix(4).uppercased()

        let prefix: String
        switch type {
        case .email:      prefix = "EMAIL"
        case .phone:      prefix = "PHONE"
        case .creditCard: prefix = "CARD"
        case .ssn:        prefix = "SSN"
        case .ipAddress:  prefix = "IP"
        case .apiKey:     prefix = "APIKEY"
        case .date:       prefix = "DATE"
        case .name:       prefix = "NAME"
        case .address:    prefix = "ADDR"
        case .custom:     prefix = "CUSTOM"
        }

        return [
            RedactionAlternative(strategy: .token, text: "[\(prefix)_\(tokenId)]", description: "Unique identifier token"),
            RedactionAlternative(strategy: .partial, text: partialRedaction(for: type, original: original), description: "Partially masked"),
            RedactionAlternative(strategy: .contextual, text: contextualPlaceholder(for: type), description: "Descriptive placeholder"),
            RedactionAlternative(strategy: .generic, text: "[REDACTED]", description: "Generic redaction")
        ]
    }

    private static func partialRedaction(for type: PIIType, original: String) -> String {
        switch type {
        case .email:
            return "\(original.prefix(1))***@***"
        case .phone, .creditCard, .ssn:
            let last4 = original.count >= 4 ? String(original.suffix(4)) : original
            return "***\(last4)"
        case .apiKey:
            return "\(original.prefix(min(8, original.count)))..."
        case .name:
            return "\(original.prefix(1))***"
        default:
            return "[REDACTED]"
        }
    }

    private static func contextualPlaceholder(for type: PIIType) -> String {
        switch type {
        case .email:      return "[email address]"
        case .phone:      return "[phone number]"
        case .creditCard: return "[credit card]"
        case .ssn:        return "[SSN]"
        case .ipAddress:  return "[IP address]"
        case .apiKey:     return "[API key]"
        case .date:       return "[date]"
        case .name:       return "[person]"
        case .address:    return "[address]"
        case .custom:     return "[custom PII]"
        }
    }

    static func == (lhs: PIIItem, rhs: PIIItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// A vault entry that maps ghost tokens to real values in Keychain.
struct VaultEntry: Identifiable, Codable {
    let id: UUID
    var label: String
    var token: String
    let createdAt: Date

    init(label: String, token: String) {
        self.id = UUID()
        self.label = label
        self.token = token
        self.createdAt = Date()
    }
}
