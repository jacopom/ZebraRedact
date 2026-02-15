import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlayPanel: OverlayPanel?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBarItem()
        registerHotkey()
        showOnboardingIfNeeded()
    }

    // MARK: - Menu Bar

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "theatermasks.fill", accessibilityDescription: "GhostClip")
            button.image?.size = NSSize(width: 16, height: 16)
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Ghost Clipboard   ⌥⌘G", action: #selector(triggerOverlay), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit GhostClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        let complete = UserDefaults.standard.bool(forKey: GhostClipConstants.StorageKeys.onboardingComplete)
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

    // MARK: - Overlay

    @objc func triggerOverlay() {
        if let panel = overlayPanel, panel.isVisible {
            panel.dismissOverlay()
            overlayPanel = nil
            return
        }

        ClipboardManager.shared.captureSelection { [weak self] text in
            let inputText = text ?? ""
            self?.showOverlayEditor(with: inputText)
        }
    }

    private func showOverlayEditor(with text: String) {
        let panel = OverlayPanel(contentRect: .zero)
        self.overlayPanel = panel

        panel.showOverlay {
            OverlayEditorView(initialText: text) { [weak self] ghostedText in
                ClipboardManager.shared.writeText(ghostedText)
                self?.overlayPanel?.dismissOverlay()
                self?.overlayPanel = nil
            }
        }
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
