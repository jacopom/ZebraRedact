#if canImport(FoundationModels)
import FoundationModels
import Foundation

// MARK: - Foundation Model Engine

@available(macOS 26.0, *)
final class FoundationModelEngine {

    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    private lazy var session = LanguageModelSession()

    // MARK: - Augment Detection

    /// Find additional PII entities missed by NLTagger + regex
    func augmentDetection(text: String, existingItems: [PIIItem]) async throws -> [PIIItem] {
        guard !text.isEmpty, Self.isAvailable else { return [] }
        let truncated = text.count > 3000 ? String(text.prefix(3000)) : text
        let alreadyMarked = existingItems.map { $0.originalText }.joined(separator: ", ")

        let prompt = """
        Find additional sensitive information in the following text that should not be shared with an external AI. \
        Focus on: full names, organizations, locations, project names, and internal identifiers. \
        Skip items already marked: \(alreadyMarked.isEmpty ? "none" : alreadyMarked). \
        Return each entity's exact text as it appears in the source, its type, and a confidence score (0.0–1.0).

        Text:
        \(truncated)
        """

        let result = try await session.respond(to: prompt, generating: DetectedEntityList.self)

        var newItems: [PIIItem] = []
        for entity in result.content.entities where entity.confidence > 0.6 {
            guard !entity.text.isEmpty,
                  let range = text.range(of: entity.text, options: .literal) else { continue }

            // Skip if overlaps with an existing item
            let overlaps = existingItems.contains { item in
                range.lowerBound < item.range.upperBound && item.range.lowerBound < range.upperBound
            }
            guard !overlaps else { continue }

            let piiType = PIIType(fromEntityType: entity.type)
            let alternatives = PIIItem.generateAlternatives(for: piiType, original: entity.text)
            guard let firstAlt = alternatives.first else { continue }

            newItems.append(PIIItem(
                type: piiType,
                range: range,
                originalText: entity.text,
                alternatives: alternatives,
                selectedAlternativeId: firstAlt.id,
                confidence: entity.confidence
            ))
        }
        return newItems
    }

    // MARK: - Context-Aware Replacements

    /// Generate semantic replacements that preserve document context
    func generateContextAwareReplacements(text: String, items: [PIIItem]) async throws -> [UUID: String] {
        guard !items.isEmpty, Self.isAvailable else { return [:] }
        let truncated = text.count > 3000 ? String(text.prefix(3000)) : text
        let itemList = items.map { "- \($0.originalText) (\($0.type.rawValue))" }.joined(separator: "\n")

        let prompt = """
        For each sensitive item listed below, generate a realistic replacement that preserves its grammatical \
        role and document context. Use the same category but a different value \
        (e.g. female name → different female name, tech company → different tech company). \
        Return the original text and its replacement.

        Source text:
        \(truncated)

        Items to replace:
        \(itemList)
        """

        let result = try await session.respond(to: prompt, generating: ReplacementList.self)

        var replacements: [UUID: String] = [:]
        for rep in result.content.replacements {
            if let item = items.first(where: { $0.originalText == rep.original }) {
                replacements[item.id] = rep.replacement
            }
        }
        return replacements
    }
}

// MARK: - Generable Output Types

@available(macOS 26.0, *)
@Generable
struct DetectedEntityList {
    @Guide(description: "PII entities found in the text (names, orgs, locations, identifiers). Each entity must appear verbatim in the source text.")
    var entities: [FoundationDetectedEntity]
}

@available(macOS 26.0, *)
@Generable
struct FoundationDetectedEntity {
    @Guide(description: "Exact text as it appears in the source")
    var text: String
    @Guide(description: "Entity type: name, organization, location, email, phone, or other")
    var type: String
    @Guide(description: "Confidence score between 0.0 and 1.0")
    var confidence: Double
}

@available(macOS 26.0, *)
@Generable
struct ReplacementList {
    @Guide(description: "Realistic semantic replacements that preserve grammatical role and document context.")
    var replacements: [FoundationReplacement]
}

@available(macOS 26.0, *)
@Generable
struct FoundationReplacement {
    @Guide(description: "The original sensitive text to replace")
    var original: String
    @Guide(description: "A realistic replacement of the same type and grammatical role")
    var replacement: String
}

#endif

// MARK: - PIIType Entity Type Mapping

extension PIIType {
    init(fromEntityType type: String) {
        switch type.lowercased() {
        case "name", "person", "personalname", "human": self = .name
        case "organization", "org", "company", "brand": self = .custom
        case "location", "address", "place", "city", "country": self = .address
        case "email": self = .email
        case "phone", "phonenumber", "telephone": self = .phone
        default: self = .custom
        }
    }
}
