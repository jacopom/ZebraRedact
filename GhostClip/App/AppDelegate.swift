import AppKit
import SwiftUI

/// AppDelegate manages the menu bar status item, global hotkey, and overlay lifecycle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var overlayPanel: OverlayPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBarItem()
        registerHotkey()
    }

    // MARK: - Menu Bar

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "theatermasks.fill", accessibilityDescription: "GhostClip")
            button.image?.size = NSSize(width: 18, height: 18)
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open GhostClip (⌥⌘G)", action: #selector(triggerOverlay), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit GhostClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    // MARK: - Hotkey

    private func registerHotkey() {
        HotkeyManager.shared.register { [weak self] in
            DispatchQueue.main.async {
                self?.triggerOverlay()
            }
        }
    }

    // MARK: - Overlay

    @objc func triggerOverlay() {
        // If panel is visible, dismiss it
        if let panel = overlayPanel, panel.isVisible {
            panel.dismissOverlay()
            overlayPanel = nil
            return
        }

        // Capture text from clipboard or selection
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

        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 450),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = "GhostClip Settings"
        settingsWindow.contentView = NSHostingView(rootView: SettingsView())
        settingsWindow.center()
        settingsWindow.makeKeyAndOrderFront(nil)
    }
}
