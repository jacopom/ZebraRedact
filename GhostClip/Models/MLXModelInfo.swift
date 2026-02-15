import Foundation

/// Describes an available MLX model for PII detection.
struct MLXModelInfo: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let displayName: String
    let sizeBytes: Int64
    let accuracy: Int
    let downloadURL: URL
    let isRecommended: Bool

    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

enum ModelInstallState: Equatable {
    case notInstalled
    case downloading(progress: Double)
    case installing
    case installed
    case failed(String)
}

extension MLXModelInfo {
    static let availableModels: [MLXModelInfo] = [
        MLXModelInfo(
            id: "distilbert-pii",
            name: "distilbert-pii",
            displayName: "DistilBERT-PII",
            sizeBytes: 100_000_000,
            accuracy: 98,
            downloadURL: URL(string: "https://huggingface.co/mlx-community/distilbert-base-uncased/resolve/main/model.mlx")!,
            isRecommended: true
        ),
        MLXModelInfo(
            id: "tiny-pii",
            name: "tiny-pii",
            displayName: "TinyPII",
            sizeBytes: 20_000_000,
            accuracy: 85,
            downloadURL: URL(string: "https://huggingface.co/mlx-community/tiny-pii/resolve/main/model.mlx")!,
            isRecommended: false
        ),
    ]
}
