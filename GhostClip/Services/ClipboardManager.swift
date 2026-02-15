import AppKit

/// Manages reading from and writing to the system clipboard (NSPasteboard).
final class ClipboardManager {
    static let shared = ClipboardManager()

    private let pasteboard = NSPasteboard.general

    private init() {}

    // MARK: - Read

    /// Reads the current clipboard text content.
    func readText() -> String? {
        pasteboard.string(forType: .string)
    }

    // MARK: - Write

    /// Writes text to the clipboard, replacing current content.
    func writeText(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Read from Focused App Selection

    /// Simulates ⌘C to capture the current selection from the frontmost app.
    func captureSelection(completion: @escaping (String?) -> Void) {
        // Save current clipboard
        let savedContent = readText()

        // Clear and simulate ⌘C
        pasteboard.clearContents()

        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // C key
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // Wait briefly for the paste to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            let selection = self?.readText()

            // Restore previous clipboard if we got a selection
            if selection == nil, let saved = savedContent {
                self?.writeText(saved)
            }

            completion(selection ?? savedContent)
        }
    }
}
