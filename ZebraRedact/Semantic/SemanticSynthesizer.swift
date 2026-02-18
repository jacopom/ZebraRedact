import Foundation

/// Phase 3: rule-based semantic replacement engine.
/// All methods are pure (deterministic) so unit tests can assert exact outputs.
/// The LLM can override any of these via `proposeReplacement` if available.
enum SemanticSynthesizer {

    // MARK: - Entry Point

    /// Returns the preferred natural-language replacement, or nil to keep the placeholder.
    /// `spanIndex` is the 0-based count of same-category spans seen before this one.
    static func synthesize(original: String, category: RedactionCategory, spanIndex: Int) -> String? {
        switch category {
        case .metric:
            return metricReplacement(original)
        case .date:
            return dateReplacement(original, spanIndex: spanIndex)
        case .email:
            return "someone@example.com"
        case .phone:
            return "+1 (555) 000-0000"
        case .ipAddress:
            return "10.0.0.1"
        case .apiKey:
            return apiKeyReplacement(original)
        // Placeholders preferred — natural language is misleading for these
        case .person, .project, .organization, .customerGroup, .location, .ssn, .creditCard, .custom:
            return nil
        }
    }

    // MARK: - Metric

    /// "7%" → "single-digit growth"  |  "3" → "several"  |  "$1.2M" → "millions in revenue"
    static func metricReplacement(_ original: String) -> String {
        let trimmed = original.trimmingCharacters(in: .whitespaces)

        // Percentage values
        if trimmed.hasSuffix("%") {
            let numStr = String(trimmed.dropLast())
            if let value = Double(numStr) {
                if value < 10  { return "single-digit growth" }
                if value < 20  { return "low double-digit growth" }
                if value < 50  { return "double-digit growth" }
                return "strong growth"
            }
        }

        // Small bare integers → qualitative quantity
        if let n = Int(trimmed), (1...9).contains(n) {
            return quantityWord(n)
        }

        // Dollar amounts
        if trimmed.hasPrefix("$") {
            let body = trimmed.dropFirst().replacingOccurrences(of: ",", with: "")
            let suffix = body.last.map { String($0).lowercased() } ?? ""
            if suffix == "b" { return "a billion-dollar figure" }
            if suffix == "m" {
                if let n = Double(String(body.dropLast())), n < 10 { return "low eight figures in revenue" }
                return "millions in revenue"
            }
            if suffix == "k" { return "thousands in revenue" }
            return "a key financial figure"
        }

        return "a key metric"
    }

    // MARK: - Date

    /// spanIndex == 0 → "a recent quarter/month/period"
    /// spanIndex >= 1 → "the previous period"
    static func dateReplacement(_ original: String, spanIndex: Int) -> String {
        if spanIndex == 0 {
            let lower = original.lowercased()
            if lower.hasPrefix("q")  { return "a recent quarter" }
            if lower.hasPrefix("h")  { return "a recent half-year period" }
            // Standalone month name
            if !lower.contains(" ") { return "a recent month" }
            return "a recent period"
        }
        return "the previous period"
    }

    // MARK: - API Key

    private static func apiKeyReplacement(_ original: String) -> String {
        if original.hasPrefix("sk-")      { return "sk-XXXXXXXXXXXXXXXXXXXX" }
        if original.hasPrefix("pk_")      { return "pk_XXXXXXXXXXXXXXXXXXXX" }
        if original.hasPrefix("AKIA")     { return "AKIAXXXXXXXXXXXXXXXX" }
        if original.hasPrefix("ghp_")     { return "ghp_XXXXXXXXXXXXXXXXXXXX" }
        return "XXXXXXXXXXXXXXXXXXXXXX"
    }

    // MARK: - Quantity Words

    /// Small integer → English quantifier: 3 → "several"
    static func quantityWord(_ n: Int) -> String {
        switch n {
        case 1:     return "one"
        case 2:     return "a couple of"
        case 3, 4:  return "several"
        case 5...9: return "a number of"
        default:    return "many"
        }
    }
}
