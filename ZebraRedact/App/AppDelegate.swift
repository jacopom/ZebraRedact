import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBarItem()
        registerHotkey()
        showOnboardingIfNeeded()
    }

    // Keep the app alive as a menu bar app after the last window is closed.
    // Without this, closing the SwiftUI WindowGroup window puts the app into a
    // zombie state (SwiftUI teardown + NSStatusItem run loop conflict → beach ball).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Menu Bar

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            if let img = NSImage(named: "ZebraMenuBar") {
                img.size = NSSize(width: 18, height: 18)
                img.isTemplate = true   // lets macOS invert for dark/light menu bar
                button.image = img
            }
        }

        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open ZebraRedact   ⌥⌘G", action: #selector(triggerOverlay), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: Selector(("showSettingsWindow:")), keyEquivalent: ",")
        settingsItem.target = nil
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit ZebraRedact", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Hotkey

    private func registerHotkey() {
        HotkeyManager.shared.register { [weak self] in
            DispatchQueue.main.async {
                self?.triggerOverlay()
            }
        }
    }

    // MARK: - Onboarding

    private func showOnboardingIfNeeded() {
        let complete = UserDefaults.standard.bool(forKey: ZebraRedactConstants.StorageKeys.onboardingComplete)
        guard !complete else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showOnboarding()
        }
    }

    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 460),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: OnboardingView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.onboardingWindow = window
    }

    // MARK: - Main Window

    @objc func triggerOverlay() {
        // The SwiftUI WindowGroup owns the main window. Find it by title and
        // bring it to the front (makeKeyAndOrderFront also un-hides a closed window).
        if let window = NSApp.windows.first(where: { $0.title == "ZebraRedact" }) {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

}

