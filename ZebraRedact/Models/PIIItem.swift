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

    /// Soft pastel palette — legible highlights without visual noise.
    var highlightColor: Color {
        switch self {
        case .email:      return Color(red: 0.60, green: 0.78, blue: 0.98)  // Cornflower blue
        case .phone:      return Color(red: 0.65, green: 0.88, blue: 0.98)  // Sky blue
        case .creditCard: return Color(red: 0.98, green: 0.67, blue: 0.72)  // Rose
        case .ssn:        return Color(red: 0.99, green: 0.87, blue: 0.55)  // Amber
        case .ipAddress:  return Color(red: 0.80, green: 0.72, blue: 0.99)  // Lavender
        case .apiKey:     return Color(red: 0.99, green: 0.95, blue: 0.58)  // Lemon
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

    // MARK: - Fake data pools (varied, international)

    private enum FakeData {
        static let names = [
            "Emma Wilson", "James Chen", "Fatima Al-Hassan", "Lucas Moreau",
            "Sofia Andersen", "Kwame Asante", "Priya Sharma", "Tobias Müller",
            "Yuki Tanaka", "Amara Okafor", "Diego Fernández", "Astrid Lindqvist",
            "Mohammed Al-Rashid", "Valentina Rossi", "Arjun Nair", "Chloe Dubois"
        ]
        static let emails = [
            "a.wilson@techcorp.io", "j.chen@startup.co", "f.hassan@globalnet.org",
            "l.moreau@example.fr", "sofia.a@university.edu", "k.asante@company.com",
            "p.sharma@consulting.in", "t.mueller@firma.de", "y.tanaka@corp.jp",
            "amara.o@nonprofit.org", "d.fernandez@empresa.es", "a.lindqvist@ab.se"
        ]
        static let phones = [
            "(415) 555-0192", "+44 20 7946 0958", "+49 30 1234 5678",
            "(212) 555-0134", "+33 1 23 45 67 89", "+81 3-1234-5678",
            "(312) 555-0167", "+61 2 9876 5432", "+34 91 123 4567",
            "(617) 555-0183", "+1 604 555-0147", "+55 11 9876-5432"
        ]
        static let addresses = [
            "742 Evergreen Terrace, Springfield", "15 Rue de la Paix, Paris",
            "Unter den Linden 77, Berlin", "350 Fifth Avenue, New York",
            "1 Harbour Rd, Hong Kong", "Via Veneto 183, Rome",
            "Avenida Paulista 900, São Paulo", "10 Downing Street, London",
            "Shibuya Crossing 1-2-3, Tokyo", "Calle Gran Vía 28, Madrid"
        ]
        static let ipAddresses = [
            "10.0.0.1", "172.16.0.1", "192.168.0.100", "10.10.1.50",
            "172.31.255.1", "192.168.100.14", "10.0.1.200", "172.20.10.1"
        ]

        static func pick<T>(_ pool: [T], seed: String) -> T {
            // Deterministic-ish pick so the same input always gets the same fake value
            let hash = abs(seed.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
            return pool[hash % pool.count]
        }

        /// Like pick, but guarantees the result differs from the original (case-insensitive).
        static func pickExcluding(_ pool: [String], seed: String, original: String) -> String {
            let filtered = pool.filter { $0.caseInsensitiveCompare(original) != .orderedSame }
            let actualPool = filtered.isEmpty ? pool : filtered
            let hash = abs(seed.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
            return actualPool[hash % actualPool.count]
        }
    }

    /// Generate default alternatives for this PII type
    static func generateAlternatives(for type: PIIType, original: String) -> [RedactionAlternative] {
        let tokenId = UUID().uuidString.prefix(4).uppercased()

        switch type {
        case .email:
            let fakeEmail = FakeData.pickExcluding(FakeData.emails, seed: original, original: original)
            return [
                RedactionAlternative(strategy: .token, text: "[EMAIL_\(tokenId)]", description: "Unique identifier token"),
                RedactionAlternative(strategy: .semantic, text: fakeEmail, description: "Realistic fake email"),
                RedactionAlternative(strategy: .partial, text: "\(original.prefix(1))***@***", description: "Show first character only"),
                RedactionAlternative(strategy: .contextual, text: "[email address]", description: "Descriptive placeholder"),
                RedactionAlternative(strategy: .generic, text: "[REDACTED]", description: "Generic redaction")
            ]

        case .phone:
            let fakePhone = FakeData.pickExcluding(FakeData.phones, seed: original, original: original)
            return [
                RedactionAlternative(strategy: .token, text: "[PHONE_\(tokenId)]", description: "Unique identifier token"),
                RedactionAlternative(strategy: .semantic, text: fakePhone, description: "Realistic fake number"),
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
            let fakeIP = FakeData.pickExcluding(FakeData.ipAddresses, seed: original, original: original)
            return [
                RedactionAlternative(strategy: .token, text: "[IP_\(tokenId)]", description: "Unique identifier token"),
                RedactionAlternative(strategy: .semantic, text: fakeIP, description: "Fake private IP address"),
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
            let fakeName = FakeData.pickExcluding(FakeData.names, seed: original, original: original)
            return [
                RedactionAlternative(strategy: .token, text: "[NAME_\(tokenId)]", description: "Unique identifier token"),
                RedactionAlternative(strategy: .semantic, text: fakeName, description: "Varied fake name"),
                RedactionAlternative(strategy: .partial, text: "\(original.prefix(1))***", description: "Show first letter only"),
                RedactionAlternative(strategy: .contextual, text: "[person]", description: "Descriptive placeholder"),
                RedactionAlternative(strategy: .generic, text: "[REDACTED]", description: "Generic redaction")
            ]

        case .address:
            let fakeAddr = FakeData.pickExcluding(FakeData.addresses, seed: original, original: original)
            return [
                RedactionAlternative(strategy: .token, text: "[ADDR_\(tokenId)]", description: "Unique identifier token"),
                RedactionAlternative(strategy: .semantic, text: fakeAddr, description: "Varied fake address"),
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
