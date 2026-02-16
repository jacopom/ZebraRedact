import Foundation

/// Protocol for PII detection engines (Regex, NLTagger, MLX)
protocol PIIDetectionEngine {
    /// Detects PII items in the given text
    func detect(in text: String) -> [PIIItem]

    /// Engine identifier (for display purposes)
    var name: String { get }

    /// Whether the engine is available on this system
    var isAvailable: Bool { get }
}
