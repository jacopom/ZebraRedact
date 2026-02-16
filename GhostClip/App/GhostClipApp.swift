import SwiftUI

@main
struct GhostClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Main window
        WindowGroup {
            MainWindow()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About GhostClip") {
                    NSApp.orderFrontStandardAboutPanel()
                }
            }
        }

        // Settings window (⌘,)
        Settings {
            SettingsView()
        }
    }
}
