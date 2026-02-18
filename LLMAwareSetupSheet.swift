import SwiftUI

// MARK: - OllamaModelManager

@MainActor
final class OllamaModelManager: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var installedModels: [String] = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadStatus: [String: String] = [:]
    @Published var isChecking: Bool = false
    @Published var activeModelId: String? = OllamaEngine.activeModel

    func checkStatus() async {
        isChecking = true
        isRunning = await OllamaEngine.isRunning()
        if isRunning {
            installedModels = (try? await OllamaEngine.listModels()) ?? []
        } else {
            installedModels = []
        }
        isChecking = false
    }

    func downloadModel(_ model: CuratedOllamaModel) async {
        downloadProgress[model.id] = 0
        downloadStatus[model.id] = "Starting…"

        do {
            for try await update in OllamaEngine.pullModel(name: model.id) {
                downloadProgress[model.id] = update.progress
                downloadStatus[model.id] = update.status
            }
            installedModels = (try? await OllamaEngine.listModels()) ?? []
            if activeModelId == nil {
                selectModel(model.id)
            }
        } catch {
            downloadStatus[model.id] = "Error: \(error.localizedDescription)"
        }

        downloadProgress.removeValue(forKey: model.id)
    }

    func selectModel(_ id: String) {
        OllamaEngine.activeModel = id
        activeModelId = id
    }

    func isInstalled(_ model: CuratedOllamaModel) -> Bool {
        installedModels.contains(where: { $0.hasPrefix(model.id) || $0 == model.id })
    }

    func isDownloading(_ model: CuratedOllamaModel) -> Bool {
        downloadProgress[model.id] != nil
    }
}

// MARK: - LLMAwareSetupSheet

struct LLMAwareSetupSheet: View {
    @StateObject private var manager = OllamaModelManager()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LLM-Aware Setup")
                        .font(.headline)
                    Text("Use a local model for context-aware redaction")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Ollama status row
                    ollamaStatusRow

                    if manager.isRunning {
                        // Section header
                        Text("Available Models")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .padding(.top, 4)

                        VStack(spacing: 8) {
                            ForEach(CuratedOllamaModel.all) { model in
                                ModelRow(model: model, manager: manager)
                            }
                        }
                    } else {
                        // Prompt to install
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Ollama is not running")
                                    .font(.callout.weight(.medium))
                                Text("Install and start Ollama, then click Refresh.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Link("ollama.com", destination: URL(string: "https://ollama.com")!)
                                .font(.callout)
                        }
                        .padding(16)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(10)
                    }

                    Spacer(minLength: 0)

                    Text("Models are downloaded from ollama.com and run entirely on your device. No data leaves your Mac.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(24)
            }
        }
        .frame(width: 480, height: 540)
        .task { await manager.checkStatus() }
    }

    private var ollamaStatusRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(manager.isRunning ? Color.green : Color(.systemRed))
                .frame(width: 8, height: 8)

            Text(manager.isRunning ? "Ollama is running" : "Ollama is not running")
                .font(.callout)

            Spacer()

            Button(action: { Task { await manager.checkStatus() } }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                    Text("Refresh")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(manager.isChecking)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - ModelRow

struct ModelRow: View {
    let model: CuratedOllamaModel
    @ObservedObject var manager: OllamaModelManager

    private var isInstalled: Bool { manager.isInstalled(model) }
    private var isDownloading: Bool { manager.isDownloading(model) }
    private var isActive: Bool { manager.activeModelId == model.id }
    private var progress: Double { manager.downloadProgress[model.id] ?? 0 }
    private var statusMsg: String? { manager.downloadStatus[model.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.callout.weight(.semibold))
                        if model.isRecommended {
                            Text("Recommended")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple)
                                .cornerRadius(4)
                        }
                    }
                    Text(model.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f GB", model.sizeGB))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Action
                if isDownloading {
                    VStack(alignment: .trailing, spacing: 4) {
                        ProgressView(value: progress)
                            .frame(width: 80)
                        Text("\(Int(progress * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else if isInstalled {
                    if isActive {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Active")
                                .font(.callout)
                                .foregroundColor(.green)
                        }
                    } else {
                        Button("Use") {
                            manager.selectModel(model.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else {
                    Button(action: { Task { await manager.downloadModel(model) } }) {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if isDownloading, let msg = statusMsg {
                Text(msg)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive
                      ? Color.purple.opacity(0.08)
                      : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}
