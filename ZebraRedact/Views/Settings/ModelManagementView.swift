import SwiftUI

struct ModelManagementView: View {
    @StateObject private var modelManager = ModelManager()
    @State private var testResult: String?
    @State private var showUninstallAlert = false
    @State private var modelToUninstall: MLXModelInfo?

    var body: some View {
        Form {
            Section("MLX Detection Models") {
                ForEach(modelManager.models) { model in
                    modelRow(model)
                }
            }

            if let activeID = modelManager.activeModelID,
               let active = modelManager.models.first(where: { $0.id == activeID }) {
                Section("Active Model") {
                    LabeledContent("Model", value: active.displayName)
                    LabeledContent("Accuracy", value: "\(active.accuracy)%")
                }
            }

            Section("Test") {
                Button("Run Test on Sample Text") {
                    testResult = modelManager.testModel(
                        on: "Email john@test.com, call 555-123-4567, card 4111-1111-1111-1111"
                    )
                }

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(ZebraTheme.green)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal)
        .alert("Remove Model?", isPresented: $showUninstallAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let model = modelToUninstall {
                    try? modelManager.uninstallModel(model)
                }
            }
        } message: {
            if let model = modelToUninstall {
                Text("Delete \(model.sizeFormatted)? Detection will fall back to regex.")
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ model: MLXModelInfo) -> some View {
        let state = modelManager.state(for: model)

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.body.bold())
                    if model.isRecommended {
                        Text("Recommended")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(ZebraTheme.purple.opacity(0.15))
                            .foregroundStyle(ZebraTheme.purple)
                            .clipShape(Capsule())
                    }
                }
                Text("\(model.sizeFormatted) · Accuracy: \(model.accuracy)%")
                    .font(.caption)
                    .foregroundStyle(ZebraTheme.secondaryText)
            }

            Spacer()

            switch state {
            case .notInstalled:
                Button("Download") {
                    Task { await modelManager.installModel(model) }
                }
                .buttonStyle(.borderedProminent)
                .tint(ZebraTheme.purple)
                .controlSize(.small)

            case .downloading(let progress):
                VStack(spacing: 2) {
                    ProgressView(value: progress)
                        .frame(width: 80)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(ZebraTheme.secondaryText)
                }

            case .installing:
                ProgressView()
                    .controlSize(.small)

            case .installed:
                HStack(spacing: 6) {
                    if modelManager.activeModelID != model.id {
                        Button("Use") { modelManager.switchToModel(model) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    } else {
                        Text("Active")
                            .font(.caption.bold())
                            .foregroundStyle(ZebraTheme.green)
                    }
                    Button {
                        modelToUninstall = model
                        showUninstallAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(ZebraTheme.red)
                    }
                    .buttonStyle(.borderless)
                }

            case .failed(let msg):
                VStack(alignment: .trailing, spacing: 2) {
                    Text(msg).font(.caption2).foregroundStyle(ZebraTheme.red).lineLimit(1)
                    Button("Retry") { Task { await modelManager.installModel(model) } }
                        .controlSize(.small)
                }
            }
        }
    }
}
