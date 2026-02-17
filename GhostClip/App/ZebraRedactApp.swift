import SwiftUI

@main
struct ZebraRedactApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Main window
        WindowGroup {
            MainWindow()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About ZebraRedact") {
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
