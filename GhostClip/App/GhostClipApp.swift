import SwiftUI

@main
struct GhostClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window (⌘,)
        Settings {
            SettingsView()
        }
    }
}
