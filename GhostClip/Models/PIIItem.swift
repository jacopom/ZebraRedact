import Foundation

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
}

struct PIIItem: Identifiable, Equatable {
    let id: UUID
    let type: PIIType
    let range: Range<String.Index>
    let originalText: String
    let ghostToken: String
    var confidence: Double
    var isMasked: Bool

    init(
        type: PIIType,
        range: Range<String.Index>,
        originalText: String,
        confidence: Double = 1.0,
        isMasked: Bool = true
    ) {
        self.id = UUID()
        self.type = type
        self.range = range
        self.originalText = originalText
        self.ghostToken = "[GHOST_\(UUID().uuidString.prefix(4).uppercased())]"
        self.confidence = confidence
        self.isMasked = isMasked
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
