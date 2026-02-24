import Foundation

/// Persists ghost token → original value mappings so LLM responses can be rehydrated.
/// Stores in memory and optionally to disk for session persistence.
final class TokenMappingStore {
    static let shared = TokenMappingStore()

    /// Token → original value, e.g. "[EMAIL_A1B2]" → "john@example.com"
    private(set) var mappings: [String: TokenMapping] = [:]

    private let storageURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("ZebraRedact", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("token_mappings.json")
    }()

    private init() {
        loadFromDisk()
    }

    // MARK: - Store

    func store(token: String, original: String, type: PIIType) {
        let mapping = TokenMapping(token: token, originalValue: original, type: type, createdAt: Date())
        mappings[token] = mapping
        saveToDisk()
    }

    func storeBatch(items: [PIIItem]) {
        for item in items where item.isMasked {
            let mapping = TokenMapping(
                token: item.token,
                originalValue: item.originalText,
                type: item.type,
                createdAt: Date()
            )
            mappings[item.token] = mapping
        }
        saveToDisk()
    }

    // MARK: - Rehydrate

    /// Replaces all [TOKEN] tokens in the text with their original values.
    func rehydrate(_ text: String) -> String {
        var result = text
        for (token, mapping) in mappings {
            result = result.replacingOccurrences(of: token, with: mapping.originalValue)
        }
        return result
    }

    /// Returns the tokens found in the given text along with their mappings.
    func findTokens(in text: String) -> [TokenMapping] {
        mappings.values.filter { text.contains($0.token) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Number of tokens that would be replaced in the text.
    func rehydrationCount(in text: String) -> Int {
        mappings.keys.filter { text.contains($0) }.count
    }

    // MARK: - Clear

    func clearAll() {
        mappings.removeAll()
        saveToDisk()
    }

    func clearOlderThan(_ date: Date) {
        mappings = mappings.filter { $0.value.createdAt > date }
        saveToDisk()
    }

    var count: Int { mappings.count }

    // MARK: - Persistence

    private func saveToDisk() {
        guard let data = try? JSONEncoder().encode(Array(mappings.values)) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: storageURL),
              let entries = try? JSONDecoder().decode([TokenMapping].self, from: data) else { return }
        for entry in entries {
            mappings[entry.token] = entry
        }
    }
}

// MARK: - Data Model

struct TokenMapping: Codable, Identifiable {
    let token: String
    let originalValue: String
    let type: PIIType
    let createdAt: Date

    var id: String { token }
}
