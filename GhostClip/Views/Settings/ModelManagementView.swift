import SwiftUI

/// Pro-only view for managing MLX PII detection models.
struct ModelManagementView: View {
    @StateObject private var modelManager = ModelManager()
    @State private var testResult: String?
    @State private var showUninstallAlert = false
    @State private var modelToUninstall: MLXModelInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "cpu.fill")
                    .foregroundStyle(GhostTheme.purple)
                Text("MLX Detector (Pro)")
                    .font(GhostTheme.headlineFont)
            }

            Divider()

            // Model List
            Text("Available Models")
                .font(.subheadline.bold())
                .foregroundStyle(GhostTheme.secondaryText)

            ForEach(modelManager.models) { model in
                modelRow(model)
            }

            Divider()

            // Active Model
            if let activeID = modelManager.activeModelID,
               let active = modelManager.models.first(where: { $0.id == activeID }) {
                HStack {
                    Text("Active Model:")
                        .font(.caption.bold())
                    Text(active.displayName)
                        .font(.caption)
                        .foregroundStyle(GhostTheme.purple)
                }
            }

            // Test Button
            Button("Test on Sample Text") {
                testResult = modelManager.testModel(
                    on: "Contact john@test.com at 555-123-4567, card 4111-1111-1111-1111"
                )
            }
            .buttonStyle(.bordered)

            if let result = testResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(GhostTheme.green)
            }
        }
        .padding()
        .alert("Remove Model?", isPresented: $showUninstallAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let model = modelToUninstall {
                    try? modelManager.uninstallModel(model)
                }
            }
        } message: {
            if let model = modelToUninstall {
                Text("Delete \(model.sizeFormatted)? Fallback to regex.")
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ model: MLXModelInfo) -> some View {
        let state = modelManager.state(for: model)

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(model.displayName)
                        .font(.body.bold())
                    if model.isRecommended {
                        Text("Recommended")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(GhostTheme.purple.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                Text("\(model.sizeFormatted) · Accuracy: \(model.accuracy)%")
                    .font(.caption)
                    .foregroundStyle(GhostTheme.secondaryText)
            }

            Spacer()

            switch state {
            case .notInstalled:
                Button("Install") {
                    Task { await modelManager.installModel(model) }
                }
                .buttonStyle(.borderedProminent)
                .tint(GhostTheme.purple)
                .controlSize(.small)

            case .downloading(let progress):
                VStack {
                    ProgressView(value: progress)
                        .frame(width: 80)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                }

            case .installing:
                ProgressView()
                    .controlSize(.small)

            case .installed:
                HStack(spacing: 8) {
                    if modelManager.activeModelID != model.id {
                        Button("Use") {
                            modelManager.switchToModel(model)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(GhostTheme.green)
                    }

                    Button {
                        modelToUninstall = model
                        showUninstallAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(GhostTheme.red)
                    }
                    .buttonStyle(.borderless)
                }

            case .failed(let msg):
                VStack(alignment: .trailing) {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(GhostTheme.red)
                    Button("Retry") {
                        Task { await modelManager.installModel(model) }
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ModelManagementView()
        .frame(width: 400)
}
