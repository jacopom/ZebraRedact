import Foundation

// MARK: - Ollama API Types

struct OllamaTagsResponse: Decodable {
    let models: [OllamaModelEntry]
}

struct OllamaModelEntry: Decodable {
    let name: String
    let size: Int64?
}

struct OllamaPullProgress: Decodable {
    let status: String
    let completed: Int64?
    let total: Int64?
}

struct OllamaGenerateResponse: Decodable {
    let response: String
}

private struct OllamaEntityEntry: Decodable {
    let text: String
    let type: String
    let confidence: Double
}

private struct OllamaReplacementEntry: Decodable {
    let original: String
    let replacement: String
}

// MARK: - Errors

enum OllamaError: LocalizedError {
    case notRunning
    case noModelSelected
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notRunning:       return "Ollama is not running. Open LLM-Aware Setup from the ⋯ menu."
        case .noModelSelected:  return "No model selected. Open LLM-Aware Setup to download one."
        case .requestFailed(let msg): return "Ollama error: \(msg)"
        }
    }
}

// MARK: - Curated Models

struct CuratedOllamaModel: Identifiable {
    let id: String          // ollama model name, e.g. "llama3.2:3b"
    let displayName: String
    let description: String
    let sizeGB: Double
    let isRecommended: Bool

    static let all: [CuratedOllamaModel] = [
        CuratedOllamaModel(
            id: "llama3.2:3b",
            displayName: "Llama 3.2 3B",
            description: "Fast, great instruction following",
            sizeGB: 2.0,
            isRecommended: true
        ),
        CuratedOllamaModel(
            id: "phi4-mini:3.8b",
            displayName: "Phi 4 Mini 3.8B",
            description: "Microsoft, excellent for structured tasks",
            sizeGB: 2.5,
            isRecommended: false
        ),
        CuratedOllamaModel(
            id: "gemma3:4b",
            displayName: "Gemma 3 4B",
            description: "Google, strong multilingual support",
            sizeGB: 3.3,
            isRecommended: false
        ),
        CuratedOllamaModel(
            id: "mistral:7b",
            displayName: "Mistral 7B",
            description: "Higher quality, needs more RAM",
            sizeGB: 4.1,
            isRecommended: false
        ),
    ]
}

// MARK: - OllamaEngine

enum OllamaEngine {

    private static let baseURL = "http://localhost:11434"

    // MARK: - Active Model (UserDefaults)

    static var activeModel: String? {
        get { UserDefaults.standard.string(forKey: "ollamaActiveModel") }
        set {
            if let value = newValue {
                UserDefaults.standard.set(value, forKey: "ollamaActiveModel")
            } else {
                UserDefaults.standard.removeObject(forKey: "ollamaActiveModel")
            }
        }
    }

    // MARK: - Status

    static func isRunning() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - List installed models

    static func listModels() async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return response.models.map { $0.name }
    }

    // MARK: - Pull (download) a model

    static func pullModel(name: String) -> AsyncThrowingStream<(progress: Double, status: String), Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let url = URL(string: "\(baseURL)/api/pull") else {
                    continuation.finish(throwing: OllamaError.requestFailed("Invalid URL"))
                    return
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                do {
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "name": name, "stream": true
                    ])
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        continuation.finish(throwing: OllamaError.requestFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"))
                        return
                    }
                    for try await line in bytes.lines {
                        guard !line.isEmpty,
                              let data = line.data(using: .utf8),
                              let prog = try? JSONDecoder().decode(OllamaPullProgress.self, from: data)
                        else { continue }

                        let pct: Double
                        if prog.status == "success" {
                            pct = 1.0
                        } else if let c = prog.completed, let t = prog.total, t > 0 {
                            pct = Double(c) / Double(t)
                        } else {
                            pct = 0
                        }
                        continuation.yield((progress: pct, status: prog.status))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Generate (non-streaming)

    static func generate(model: String, prompt: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw OllamaError.requestFailed("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "prompt": prompt,
            "stream": false
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        return response.response
    }

    // MARK: - JSON extraction helper

    static func extractJSONArray(from text: String) -> String? {
        // Models sometimes wrap the JSON with markdown or preamble — extract first [...] block
        var depth = 0
        var start: String.Index? = nil
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            if ch == "[" {
                if depth == 0 { start = index }
                depth += 1
            } else if ch == "]" {
                depth -= 1
                if depth == 0, let s = start {
                    return String(text[s...index])
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    // MARK: - Augment PII Detection

    static func augmentDetection(text: String, existingItems: [PIIItem]) async throws -> [PIIItem] {
        guard let model = activeModel else { throw OllamaError.noModelSelected }
        let truncated = text.count > 3000 ? String(text.prefix(3000)) : text
        let alreadyMarked = existingItems.map { "\($0.originalText)" }.joined(separator: ", ")

        let prompt = """
        You are a privacy scanner. Find sensitive information in the text that should not be shared externally.
        Look for: person names, company/organization names, locations, internal identifiers.
        Skip items already found: \(alreadyMarked.isEmpty ? "none" : alreadyMarked)

        Text:
        \(truncated)

        Respond with ONLY a valid JSON array, nothing else:
        [{"text": "exact substring as it appears", "type": "name|organization|location|other", "confidence": 0.9}]
        If nothing found, respond with: []
        """

        let raw = try await generate(model: model, prompt: prompt)
        guard let jsonStr = extractJSONArray(from: raw),
              let data = jsonStr.data(using: .utf8),
              let entries = try? JSONDecoder().decode([OllamaEntityEntry].self, from: data)
        else { return [] }

        var newItems: [PIIItem] = []
        for entry in entries where entry.confidence > 0.6 && !entry.text.isEmpty {
            guard let range = text.range(of: entry.text, options: .literal) else { continue }
            let overlaps = existingItems.contains {
                range.lowerBound < $0.range.upperBound && $0.range.lowerBound < range.upperBound
            }
            guard !overlaps else { continue }

            let piiType = PIIType(fromEntityType: entry.type)
            let alternatives = PIIItem.generateAlternatives(for: piiType, original: entry.text)
            guard let firstAlt = alternatives.first else { continue }
            newItems.append(PIIItem(
                type: piiType,
                range: range,
                originalText: entry.text,
                alternatives: alternatives,
                selectedAlternativeId: firstAlt.id,
                confidence: entry.confidence
            ))
        }
        return newItems
    }

    // MARK: - Context-Aware Replacements

    static func generateContextAwareReplacements(text: String, items: [PIIItem]) async throws -> [UUID: String] {
        guard let model = activeModel else { throw OllamaError.noModelSelected }
        guard !items.isEmpty else { return [:] }

        let truncated = text.count > 3000 ? String(text.prefix(3000)) : text
        // Use original text (not UUID) so small models can reliably match items
        let itemLines = items.map { "- \"\($0.originalText)\" (\($0.type.rawValue))" }.joined(separator: "\n")

        let prompt = """
        You are a privacy redaction tool. Replace each sensitive item with a realistic fictional \
        alternative of the same type that preserves grammatical structure and cultural context.
        Rules: preserve language and category (Italian beer company → different Italian/Dutch beer \
        company, female name → different female name of same nationality). \
        Output ONLY a valid JSON array, nothing else.

        Text: \(truncated)

        Items to replace:
        \(itemLines)

        Output format (ONLY the JSON array, no markdown, no explanation):
        [{"original": "<exact original text>", "replacement": "<realistic fake value>"}]
        If you cannot replace an item, omit it from the array.
        """

        let raw = try await generate(model: model, prompt: prompt)
        guard let jsonStr = extractJSONArray(from: raw),
              let data = jsonStr.data(using: .utf8),
              let entries = try? JSONDecoder().decode([OllamaReplacementEntry].self, from: data)
        else { return [:] }

        // Match by original text → look up UUID
        var replacements: [UUID: String] = [:]
        for entry in entries where !entry.replacement.isEmpty {
            if let item = items.first(where: { $0.originalText == entry.original }) {
                replacements[item.id] = entry.replacement
            }
        }
        return replacements
    }
}
