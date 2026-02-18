import Foundation
import NaturalLanguage

// MARK: - Data Models

struct SemanticContext {
    let entities: [EntityNode]
    let relationships: [EntityRelationship]
    let roles: [UUID: String]
}

struct EntityNode {
    let id: UUID
    let item: PIIItem
    let grammaticalRole: GrammaticalRole
    let contextWords: [String]
    let syntacticPosition: SyntacticPosition
}

enum GrammaticalRole {
    case subject
    case object
    case possessive
    case unknown
}

struct SyntacticPosition {
    let sentenceIndex: Int
    let positionInSentence: Int
    let isBeginning: Bool
    let isEnding: Bool
}

struct EntityRelationship {
    let fromEntity: UUID
    let toEntity: UUID
    let relationshipType: RelationType
    let confidence: Double
}

enum RelationType {
    case contact      // name + email/phone
    case ownership    // person + address/card
    case professional // person + organization
    case temporal     // event + date
}

// MARK: - Semantic Analyzer

final class SemanticAnalyzer {
    private let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType, .lemma])

    func analyze(text: String, items: [PIIItem]) async -> SemanticContext {
        tagger.string = text

        var entities: [EntityNode] = []
        var relationships: [EntityRelationship] = []

        // Step 1: Analyze each PII item's context
        for item in items {
            let grammaticalRole = determineGrammaticalRole(item: item, text: text)
            let contextWords = extractContextWords(around: item.range, in: text)
            let syntacticPosition = analyzeSyntacticPosition(item: item, text: text)

            let node = EntityNode(
                id: item.id,
                item: item,
                grammaticalRole: grammaticalRole,
                contextWords: contextWords,
                syntacticPosition: syntacticPosition
            )
            entities.append(node)
        }

        // Step 2: Detect relationships between entities
        relationships = await detectRelationships(between: entities, in: text)

        // Step 3: Generate semantic role descriptions
        let roles = generateRoleDescriptions(entities: entities, relationships: relationships)

        return SemanticContext(
            entities: entities,
            relationships: relationships,
            roles: roles
        )
    }

    // MARK: - Grammatical Analysis

    private func determineGrammaticalRole(item: PIIItem, text: String) -> GrammaticalRole {
        // Use NLTagger to analyze surrounding tokens
        let beforeRange = text.index(item.range.lowerBound, offsetBy: -20, limitedBy: text.startIndex) ?? text.startIndex
        let afterRange = text.index(item.range.upperBound, offsetBy: 20, limitedBy: text.endIndex) ?? text.endIndex

        var role: GrammaticalRole = .unknown

        tagger.enumerateTags(in: beforeRange..<afterRange, unit: .word, scheme: .lexicalClass) { tag, tokenRange in
            if tokenRange.upperBound == item.range.lowerBound {
                // Word immediately before entity
                if tag == .verb {
                    role = .object // Verb before entity → entity is object
                }
            }
            if tokenRange.lowerBound == item.range.upperBound {
                // Word immediately after entity
                if tag == .verb {
                    role = .subject // Entity before verb → entity is subject
                }
            }
            return true
        }

        return role
    }

    private func extractContextWords(around range: Range<String.Index>, in text: String) -> [String] {
        let beforeStart = text.index(range.lowerBound, offsetBy: -50, limitedBy: text.startIndex) ?? text.startIndex
        let afterEnd = text.index(range.upperBound, offsetBy: 50, limitedBy: text.endIndex) ?? text.endIndex

        let contextText = String(text[beforeStart..<afterEnd])
        return contextText.split(separator: " ").map(String.init)
    }

    private func analyzeSyntacticPosition(item: PIIItem, text: String) -> SyntacticPosition {
        // Count sentences before this position
        let beforeText = String(text[..<item.range.lowerBound])
        let sentenceCount = beforeText.components(separatedBy: ".").count - 1

        // Find position within current sentence
        let currentSentenceStart = beforeText.lastIndex(of: ".") ?? text.startIndex
        let sentenceText = String(text[currentSentenceStart..<item.range.upperBound])
        let words = sentenceText.split(separator: " ")
        let position = words.count

        let isBeginning = position <= 2
        let isEnding = text.distance(from: item.range.upperBound, to: text.endIndex) < 10

        return SyntacticPosition(
            sentenceIndex: sentenceCount,
            positionInSentence: position,
            isBeginning: isBeginning,
            isEnding: isEnding
        )
    }

    // MARK: - Relationship Detection

    private func detectRelationships(between entities: [EntityNode], in text: String) async -> [EntityRelationship] {
        var relationships: [EntityRelationship] = []

        // Heuristic 1: Name within 10 words of email/phone → contact relationship
        for i in 0..<entities.count {
            for j in (i+1)..<entities.count {
                let entity1 = entities[i]
                let entity2 = entities[j]

                // Calculate distance in words
                let distance = calculateWordDistance(
                    from: entity1.item.range,
                    to: entity2.item.range,
                    in: text
                )

                if distance <= 10 {
                    if (entity1.item.type == .name && [.email, .phone].contains(entity2.item.type)) ||
                       (entity2.item.type == .name && [.email, .phone].contains(entity1.item.type)) {
                        relationships.append(EntityRelationship(
                            fromEntity: entity1.id,
                            toEntity: entity2.id,
                            relationshipType: .contact,
                            confidence: 0.8
                        ))
                    }
                }

                // Heuristic 2: Name + Address within 15 words → ownership
                if distance <= 15 {
                    if (entity1.item.type == .name && entity2.item.type == .address) ||
                       (entity2.item.type == .name && entity1.item.type == .address) {
                        relationships.append(EntityRelationship(
                            fromEntity: entity1.id,
                            toEntity: entity2.id,
                            relationshipType: .ownership,
                            confidence: 0.7
                        ))
                    }
                }
            }
        }

        return relationships
    }

    private func calculateWordDistance(from range1: Range<String.Index>, to range2: Range<String.Index>, in text: String) -> Int {
        let start = min(range1.upperBound, range2.upperBound)
        let end = max(range1.lowerBound, range2.lowerBound)

        guard start < end else { return 0 }

        let betweenText = String(text[start..<end])
        return betweenText.split(separator: " ").count
    }

    // MARK: - Role Description Generation

    private func generateRoleDescriptions(entities: [EntityNode], relationships: [EntityRelationship]) -> [UUID: String] {
        var roles: [UUID: String] = [:]

        for entity in entities {
            let description = generateDescription(for: entity, considering: relationships)
            roles[entity.id] = description
        }

        return roles
    }

    private func generateDescription(for entity: EntityNode, considering relationships: [EntityRelationship]) -> String {
        // Context-aware role generation
        let contextHints = entity.contextWords.map { $0.lowercased() }

        switch entity.item.type {
        case .name:
            if contextHints.contains(where: { ["ceo", "director", "manager", "lead", "chief"].contains($0) }) {
                return "project lead"
            }
            if contextHints.contains(where: { ["dr", "doctor", "professor", "phd"].contains($0) }) {
                return "professional"
            }
            if relationships.contains(where: { $0.fromEntity == entity.id && $0.relationshipType == .contact }) {
                return "contact person"
            }
            return "individual"

        case .email:
            if contextHints.contains(where: { ["work", "office", "business", "corporate"].contains($0) }) {
                return "work email"
            }
            return "email address"

        case .phone:
            if contextHints.contains(where: { ["mobile", "cell"].contains($0) }) {
                return "mobile number"
            }
            if contextHints.contains(where: { ["office", "work"].contains($0) }) {
                return "office number"
            }
            return "phone number"

        case .address:
            if contextHints.contains(where: { ["office", "headquarters", "hq"].contains($0) }) {
                return "office location"
            }
            if contextHints.contains(where: { ["home", "residence"].contains($0) }) {
                return "home address"
            }
            return "location"

        case .creditCard:
            return "payment method"

        case .ssn:
            return "tax identifier"

        case .ipAddress:
            return "network address"

        case .apiKey:
            return "access credential"

        case .custom:
            return "sensitive data"
        }
    }
}
