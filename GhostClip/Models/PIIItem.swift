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
        case .name: return "person.fill"
        case .address: return "mappin.and.ellipse"
        case .custom: return "tag.fill"
        }
    }

    /// Hemingway-style muted highlight colors
    var highlightColor: Color {
        switch self {
        case .email: return Color(red: 0.95, green: 0.85, blue: 0.7, opacity: 0.4)     // Muted orange
        case .phone: return Color(red: 0.7, green: 0.85, blue: 0.95, opacity: 0.4)     // Muted blue
        case .creditCard: return Color(red: 0.95, green: 0.7, blue: 0.7, opacity: 0.4) // Muted red
        case .ssn: return Color(red: 0.95, green: 0.7, blue: 0.85, opacity: 0.4)       // Muted pink
        case .ipAddress: return Color(red: 0.8, green: 0.75, blue: 0.95, opacity: 0.4) // Muted purple
        case .apiKey: return Color(red: 0.95, green: 0.9, blue: 0.7, opacity: 0.4)     // Muted yellow
        case .name: return Color(red: 0.75, green: 0.95, blue: 0.8, opacity: 0.4)      // Muted green
        case .address: return Color(red: 0.85, green: 0.9, blue: 0.75, opacity: 0.4)   // Muted lime
        case .custom: return Color(red: 0.85, green: 0.85, blue: 0.85, opacity: 0.4)   // Muted gray
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

    /// The currently selected ghost token
    var ghostToken: String {
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
        isMasked: Bool = true
    ) {
        self.id = UUID()
        self.type = type
        self.range = range
        self.originalText = originalText
        self.alternatives = alternatives
        self.selectedAlternativeId = selectedAlternativeId
        self.confidence = confidence
        self.isMasked = isMasked
    }

    /// Generate default alternatives for this PII type
    static func generateAlternatives(for type: PIIType, original: String) -> [RedactionAlternative] {
        let tokenId = UUID().uuidString.prefix(4).uppercased()

        switch type {
        case .email:
            return [
                RedactionAlternative(strategy: .token, text: "[EMAIL_\(tokenId)]", description: "Unique identifier token"),
                RedactionAlternative(strategy: .semantic, text: "user@example.com", description: "Realistic fake email"),
                RedactionAlternative(strategy: .partial, text: "\(original.prefix(1))***@***", description: "Show first character only"),
                RedactionAlternative(strategy: .contextual, text: "[email address]", description: "Descriptive placeholder"),
                RedactionAlternative(strategy: .generic, text: "[REDACTED]", description: "Generic redaction")
            ]

        case .phone:
            return [
                RedactionAlternative(strategy: .token, text: "[PHONE_\(tokenId)]", description: "Unique identifier token"),
                RedactionAlternative(strategy: .semantic, text: "(555) 123-4567", description: "Realistic fake number"),
                RedactionAlternative(strategy: .partial, text: "***-***-\(original.suffix(4))", description: "Show last 4 digits"),
                RedactionAlternative(strategy: .contextual, text: "[phone number]", description: "Descriptive placeholder"),
                RedactionAlternative(strategy: .generic, text: "[REDACTED]", description: "Generic redaction")
            ]

        case .creditCard:
            return [
                RedactionAlternative(strategy: .token, text: "[CARD_\(tokenId)]", description: "Unique identifier token"),
                RedactionAlternative(strategy: .partial, text: "****-****-****-\(original.suffix(4))", description: "Show last 4 digits"),
                RedactionAlternative(strategy: .contextual, text: "[credit card]", description: "Descriptive placeholder"),
                RedactionAlternative(strategy: .generic, text: "[REDACTED]", description: "Generic redaction")
            ]

        case .ssn:
            return [
                RedactionAlternative(strategy: .token, text: "[SSN_\(tokenId)]", description: "Unique identifier token"),
                RedactionAlternative(strategy: .partial, text: "***-**-\(original.suffix(4))", description: "Show last 4 digits"),
                RedactionAlternative(strategy: .contextual, text: "[SSN]", description: "Descriptive placeholder"),
                RedactionAlternative(strategy: .generic, text: "[REDACTED]", description: "Generic redaction")
            ]

        case .ipAddress:
            return [
                RedactionAlternative(strategy: .token, text: "[IP_\(tokenId)]", description: "Unique identifier token"),
                RedactionAlternative(strategy: .semantic, text: "192.168.1.1", description: "Private IP address"),
                RedactionAlternative(strategy: .contextual, text: "[IP address]", description: "Descriptive placeholder"),
                RedactionAlternative(strategy: .generic, text: "[REDACTED]", description: "Generic redaction")
            ]

        case .apiKey:
            return [
                RedactionAlternative(strategy: .token, text: "[APIKEY_\(tokenId)]", description: "Unique identifier token"),
                RedactionAlternative(strategy: .partial, text: "\(original.prefix(8))...", description: "Show first 8 characters"),
                RedactionAlternative(strategy: .contextual, text: "[API key]", description: "Descriptive placeholder"),
                RedactionAlternative(strategy: .generic, text: "[REDACTED]", description: "Generic redaction")
            ]

        case .name:
            return [
                RedactionAlternative(strategy: .token, text: "[NAME_\(tokenId)]", description: "Unique identifier token"),
                RedactionAlternative(strategy: .semantic, text: "John Doe", description: "Generic placeholder name"),
                RedactionAlternative(strategy: .partial, text: "\(original.prefix(1))***", description: "Show first letter only"),
                RedactionAlternative(strategy: .contextual, text: "[person]", description: "Descriptive placeholder"),
                RedactionAlternative(strategy: .generic, text: "[REDACTED]", description: "Generic redaction")
            ]

        case .address:
            return [
                RedactionAlternative(strategy: .token, text: "[ADDR_\(tokenId)]", description: "Unique identifier token"),
                RedactionAlternative(strategy: .semantic, text: "123 Main St", description: "Generic placeholder address"),
                RedactionAlternative(strategy: .contextual, text: "[address]", description: "Descriptive placeholder"),
                RedactionAlternative(strategy: .generic, text: "[REDACTED]", description: "Generic redaction")
            ]

        case .custom:
            return [
                RedactionAlternative(strategy: .token, text: "[CUSTOM_\(tokenId)]", description: "Unique identifier token"),
                RedactionAlternative(strategy: .contextual, text: "[custom PII]", description: "Descriptive placeholder"),
                RedactionAlternative(strategy: .generic, text: "[REDACTED]", description: "Generic redaction")
            ]
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
    var ghostToken: String
    let createdAt: Date

    init(label: String, ghostToken: String) {
        self.id = UUID()
        self.label = label
        self.ghostToken = ghostToken
        self.createdAt = Date()
    }
}
