import SwiftUI

@main
struct GhostClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage(GhostClipConstants.StorageKeys.onboardingComplete) private var onboardingComplete = false

    var body: some Scene {
        // Hidden main window — app lives in menu bar
        MenuBarExtra {
            MenuBarView(onTrigger: { appDelegate.triggerOverlay() })
        } label: {
            Image(systemName: "theatermasks.fill")
        }
        .menuBarExtraStyle(.menu)

        // Settings window (⌘,)
        Settings {
            SettingsView()
        }

        // Onboarding window
        Window("Welcome to GhostClip", id: "onboarding") {
            OnboardingView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    let onTrigger: () -> Void

    var body: some View {
        Button("Open GhostClip ⌥⌘G") {
            onTrigger()
        }
        .keyboardShortcut("g", modifiers: [.option, .command])

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit GhostClip") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
