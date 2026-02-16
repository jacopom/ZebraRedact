import Foundation

/// Semantic replacement engine: replaces PII with contextually similar fake data
/// instead of opaque tokens, so LLMs can work with abstracted but realistic text.
final class SemanticReplacer {

    // MARK: - Replacement Pools

    private static let firstNames = [
        "Alice", "Bob", "Carol", "David", "Emma", "Frank", "Grace", "Henry",
        "Iris", "Jack", "Kate", "Liam", "Mia", "Noah", "Olivia", "Peter",
        "Quinn", "Rachel", "Sam", "Taylor"
    ]

    private static let lastNames = [
        "Anderson", "Brown", "Chen", "Davis", "Evans", "Foster", "Garcia", "Harris",
        "Ivanov", "Johnson", "Kim", "Lee", "Martinez", "Nguyen", "O'Brien", "Patel",
        "Quinn", "Rodriguez", "Smith", "Taylor"
    ]

    private static let domains = [
        "example.com", "sample.org", "demo.net", "test.io", "placeholder.co",
        "mock.dev", "fake.com", "dummy.org"
    ]

    private static let streets = [
        "Maple Street", "Oak Avenue", "Pine Road", "Elm Drive", "Cedar Lane",
        "Birch Boulevard", "Willow Way", "Ash Court", "Spruce Circle"
    ]

    // MARK: - Semantic Replacement

    func replace(items: [PIIItem], in text: String) -> (String, [SemanticMapping]) {
        var result = text
        var mappings: [SemanticMapping] = []

        // Process in reverse order to preserve indices
        for item in items.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) where item.isMasked {
            let replacement = generateReplacement(for: item, original: item.originalText)
            result.replaceSubrange(item.range, with: replacement)

            let mapping = SemanticMapping(
                original: item.originalText,
                replacement: replacement,
                type: item.type,
                createdAt: Date()
            )
            mappings.append(mapping)
        }

        return (result, mappings)
    }

    private func generateReplacement(for item: PIIItem, original: String) -> String {
        switch item.type {
        case .email:
            return generateEmail()

        case .phone:
            return generatePhone()

        case .creditCard:
            return generateCreditCard()

        case .ssn:
            return generateSSN()

        case .ipAddress:
            return generateIP()

        case .apiKey:
            return generateAPIKey(original: original)

        case .name:
            return generateName()

        case .address:
            return generateAddress()

        case .custom:
            return generateGeneric()
        }
    }

    // MARK: - Generators

    private func generateEmail() -> String {
        let first = Self.firstNames.randomElement()!.lowercased()
        let last = Self.lastNames.randomElement()!.lowercased()
        let domain = Self.domains.randomElement()!
        return "\(first).\(last)@\(domain)"
    }

    private func generatePhone() -> String {
        let area = Int.random(in: 200...999)
        let prefix = Int.random(in: 200...999)
        let line = Int.random(in: 1000...9999)
        return "+1 (\(area)) \(prefix)-\(line)"
    }

    private func generateCreditCard() -> String {
        // Luhn-invalid but realistic-looking number
        let parts = (0..<4).map { _ in Int.random(in: 1000...9999) }
        return parts.map { String($0) }.joined(separator: "-")
    }

    private func generateSSN() -> String {
        let area = Int.random(in: 100...999)
        let group = Int.random(in: 10...99)
        let serial = Int.random(in: 1000...9999)
        return "\(area)-\(group)-\(serial)"
    }

    private func generateIP() -> String {
        let octets = (0..<4).map { _ in Int.random(in: 10...250) }
        return octets.map { String($0) }.joined(separator: ".")
    }

    private func generateAPIKey(original: String) -> String {
        // Preserve prefix pattern (sk-, pk_, etc.)
        if original.hasPrefix("sk-") {
            return "sk-" + randomAlphanumeric(length: 20)
        } else if original.hasPrefix("pk_") {
            return "pk_" + randomAlphanumeric(length: 20)
        } else if original.hasPrefix("AKIA") {
            return "AKIA" + randomAlphanumeric(length: 16).uppercased()
        } else if original.hasPrefix("ghp_") {
            return "ghp_" + randomAlphanumeric(length: 36)
        } else {
            return "fake_key_" + randomAlphanumeric(length: 16)
        }
    }

    private func generateName() -> String {
        let first = Self.firstNames.randomElement()!
        let last = Self.lastNames.randomElement()!
        return "\(first) \(last)"
    }

    private func generateAddress() -> String {
        let number = Int.random(in: 100...9999)
        let street = Self.streets.randomElement()!
        return "\(number) \(street)"
    }

    private func generateGeneric() -> String {
        return "[REDACTED]"
    }

    private func randomAlphanumeric(length: Int) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in chars.randomElement()! })
    }
}

// MARK: - Semantic Mapping

struct SemanticMapping: Codable, Identifiable {
    let original: String
    let replacement: String
    let type: PIIType
    let createdAt: Date

    var id: String { original }
}
