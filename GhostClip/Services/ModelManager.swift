import Foundation
import Combine

/// Manages MLX model downloads, installation, and switching (Pro feature).
@MainActor
final class ModelManager: ObservableObject {
    @Published var models: [MLXModelInfo] = MLXModelInfo.availableModels
    @Published var installStates: [String: ModelInstallState] = [:]
    @Published var activeModelID: String?

    private var downloadTasks: [String: URLSessionDownloadTask] = [:]

    init() {
        activeModelID = UserDefaults.standard.string(forKey: ZebraRedactConstants.StorageKeys.activeModel)
        refreshInstallStates()
    }

    // MARK: - State

    func state(for model: MLXModelInfo) -> ModelInstallState {
        installStates[model.id] ?? .notInstalled
    }

    func isInstalled(_ model: MLXModelInfo) -> Bool {
        let modelPath = ZebraRedactConstants.Paths.mlxModelsDirectory
            .appendingPathComponent(model.name, isDirectory: true)
        return FileManager.default.fileExists(atPath: modelPath.path)
    }

    func refreshInstallStates() {
        for model in models {
            if isInstalled(model) {
                installStates[model.id] = .installed
            } else if case .downloading = installStates[model.id] {
                // keep downloading state
            } else {
                installStates[model.id] = .notInstalled
            }
        }
    }

    // MARK: - Install

    func installModel(_ model: MLXModelInfo) async {
        installStates[model.id] = .downloading(progress: 0)

        let destDir = ZebraRedactConstants.Paths.mlxModelsDirectory
            .appendingPathComponent(model.name, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        } catch {
            installStates[model.id] = .failed("Cannot create directory: \(error.localizedDescription)")
            return
        }

        // Simulated download with URLSession
        let session = URLSession.shared
        do {
            let (tempURL, response) = try await session.download(from: model.downloadURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                installStates[model.id] = .failed("Download failed. Check network.")
                return
            }

            let finalPath = destDir.appendingPathComponent("model.mlx")
            try FileManager.default.moveItem(at: tempURL, to: finalPath)

            installStates[model.id] = .installed
        } catch {
            installStates[model.id] = .failed("Download error: \(error.localizedDescription)")
        }
    }

    // MARK: - Uninstall

    func uninstallModel(_ model: MLXModelInfo) throws {
        let modelPath = ZebraRedactConstants.Paths.mlxModelsDirectory
            .appendingPathComponent(model.name, isDirectory: true)

        try FileManager.default.removeItem(at: modelPath)
        installStates[model.id] = .notInstalled

        if activeModelID == model.id {
            activeModelID = nil
            UserDefaults.standard.removeObject(forKey: ZebraRedactConstants.StorageKeys.activeModel)
        }
    }

    // MARK: - Switch

    func switchToModel(_ model: MLXModelInfo) {
        guard isInstalled(model) else { return }
        activeModelID = model.id
        UserDefaults.standard.set(model.id, forKey: ZebraRedactConstants.StorageKeys.activeModel)
    }

    // MARK: - Test

    func testModel(on sampleText: String) -> String {
        let detector = RegexDetector()
        let items = detector.detect(in: sampleText)
        return "PII found: \(items.count) item(s) — \(items.map(\.type.rawValue).joined(separator: ", "))"
    }
}
