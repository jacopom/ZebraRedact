import SwiftUI

/// Pro vault UI for storing real PII values in Keychain, PIN/biometric protected.
struct VaultView: View {
    @StateObject private var vault = VaultManager()
    @State private var newLabel = ""
    @State private var newValue = ""
    @State private var revealedEntryID: UUID?
    @State private var revealedValue: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(GhostTheme.purple)
                Text("Vault (Pro) — PIN Protected")
                    .font(GhostTheme.headlineFont)
            }

            if !vault.isUnlocked {
                // Lock Screen
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(GhostTheme.secondaryText)

                    Text("Unlock Vault")
                        .font(.headline)

                    Button("Authenticate") {
                        Task { await vault.authenticate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(GhostTheme.purple)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                // Entries List
                Text("Your Secrets")
                    .font(.subheadline.bold())
                    .foregroundStyle(GhostTheme.secondaryText)

                if vault.entries.isEmpty {
                    Text("No vault entries yet. Add your first secret below.")
                        .font(.caption)
                        .foregroundStyle(GhostTheme.secondaryText)
                        .italic()
                } else {
                    ForEach(vault.entries) { entry in
                        entryRow(entry)
                    }
                }

                Divider()

                // Add New
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Secret")
                        .font(.subheadline.bold())

                    HStack {
                        TextField("Label (e.g., My Email)", text: $newLabel)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 160)

                        SecureField("Value", text: $newValue)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)

                        Button("Save") {
                            guard !newLabel.isEmpty, !newValue.isEmpty else { return }
                            _ = vault.addEntry(label: newLabel, value: newValue)
                            newLabel = ""
                            newValue = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(GhostTheme.purple)
                        .disabled(newLabel.isEmpty || newValue.isEmpty)
                    }
                }

                // Lock button
                Button {
                    vault.lock()
                } label: {
                    Label("Lock Vault", systemImage: "lock.fill")
                }
                .buttonStyle(.bordered)
            }

            if let error = vault.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(GhostTheme.red)
            }
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Personal Vault")
    }

    @ViewBuilder
    private func entryRow(_ entry: VaultEntry) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(entry.label)
                    .font(.body.bold())
                Text(entry.ghostToken)
                    .font(.caption.monospaced())
                    .foregroundStyle(GhostTheme.purple)
            }

            Spacer()

            if revealedEntryID == entry.id, let value = revealedValue {
                Text(value)
                    .font(.caption.monospaced())
                    .foregroundStyle(GhostTheme.secondaryText)
                    .textSelection(.enabled)
            }

            // Reveal button
            Button {
                if revealedEntryID == entry.id {
                    revealedEntryID = nil
                    revealedValue = nil
                } else {
                    revealedValue = vault.retrieveValue(for: entry)
                    revealedEntryID = entry.id
                }
            } label: {
                Image(systemName: revealedEntryID == entry.id ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help("Toggle value visibility")

            // Delete button
            Button {
                vault.deleteEntry(entry)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(GhostTheme.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .accessibilityLabel("Vault item: \(entry.label)")
    }
}

#Preview {
    VaultView()
        .frame(width: 400, height: 500)
}
