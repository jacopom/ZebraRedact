import Foundation

enum ZebraRedactConstants {
    static let appName = "ZebraRedact"
    static let bundleIdentifier = "com.zebraredact.app"

    // MARK: - Storage Keys
    enum StorageKeys {
        static let hasSeenOnboarding = "hasSeenOnboarding"
        static let onboardingComplete = "onboardingComplete"
        static let activeModel = "activeModel"
        static let isPro = "isPro"
        static let useMLXDetection = "useMLXDetection"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let showInDock = "showInDock"
        static let detectionEngine = "detectionEngine"  // "regex" or "nltagger" or "mlx"
    }

    // MARK: - Hotkeys
    enum Hotkeys {
        static let hotkey = "⌥⌘G"
        static let applyShortcut = "⌘⏎"
        static let cancelShortcut = "⎋"
    }

    // MARK: - Overlay
    enum Overlay {
        static let minWidth: CGFloat = 900
        static let minHeight: CGFloat = 700
        static let maxWidth: CGFloat = 1200
        static let maxHeight: CGFloat = 900
    }

    // MARK: - Model Storage
    enum Paths {
        static var mlxModelsDirectory: URL {
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ZebraRedact/MLX", isDirectory: true)
        }

        static var vaultKeychainService: String { "com.zebraredact.vault" }
    }

    // MARK: - IAP
    enum IAP {
        static let proProductID = "com.zebraredact.pro"
    }
}
