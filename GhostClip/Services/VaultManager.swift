import Foundation
import Security
import LocalAuthentication

/// Manages the Pro vault using Keychain for storing real PII values.
@MainActor
final class VaultManager: ObservableObject {
    @Published var entries: [VaultEntry] = []
    @Published var isUnlocked: Bool = false
    @Published var error: String?

    private let service = GhostClipConstants.Paths.vaultKeychainService

    // MARK: - Authentication

    func authenticate() async -> Bool {
        let context = LAContext()
        var authError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            error = "Biometric authentication not available."
            return false
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock GhostClip Vault"
            )
            isUnlocked = success
            if success { loadEntries() }
            return success
        } catch {
            self.error = "Authentication failed: \(error.localizedDescription)"
            return false
        }
    }

    func lock() {
        isUnlocked = false
        entries = []
    }

    // MARK: - CRUD

    func addEntry(label: String, value: String) -> VaultEntry? {
        let entry = VaultEntry(label: label, ghostToken: "[GHOST_\(UUID().uuidString.prefix(4).uppercased())]")

        let keychainItem: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: entry.id.uuidString,
            kSecAttrLabel as String: entry.label,
            kSecValueData as String: value.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]

        let status = SecItemAdd(keychainItem as CFDictionary, nil)
        guard status == errSecSuccess else {
            error = "Failed to save: \(SecCopyErrorMessageString(status, nil) as String? ?? "Unknown")"
            return nil
        }

        // Persist metadata (label + ghostToken mapping)
        persistEntryMetadata(entry)
        entries.append(entry)
        return entry
    }

    func deleteEntry(_ entry: VaultEntry) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: entry.id.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
        removeEntryMetadata(entry)
        entries.removeAll { $0.id == entry.id }
    }

    func retrieveValue(for entry: VaultEntry) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: entry.id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Rehydration

    func rehydrate(text: String) -> String {
        var result = text
        for entry in entries {
            if let value = retrieveValue(for: entry) {
                result = result.replacingOccurrences(of: entry.ghostToken, with: value)
            }
        }
        return result
    }

    // MARK: - Metadata Persistence

    private var metadataURL: URL {
        GhostClipConstants.Paths.mlxModelsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("vault_meta.json")
    }

    private func loadEntries() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([VaultEntry].self, from: data) else {
            entries = []
            return
        }
        entries = decoded
    }

    private func persistEntryMetadata(_ entry: VaultEntry) {
        var all = (try? JSONDecoder().decode([VaultEntry].self, from: Data(contentsOf: metadataURL))) ?? []
        all.append(entry)
        if let data = try? JSONEncoder().encode(all) {
            try? FileManager.default.createDirectory(at: metadataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: metadataURL)
        }
    }

    private func removeEntryMetadata(_ entry: VaultEntry) {
        var all = (try? JSONDecoder().decode([VaultEntry].self, from: Data(contentsOf: metadataURL))) ?? []
        all.removeAll { $0.id == entry.id }
        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: metadataURL)
        }
    }
}
