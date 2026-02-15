import AppKit
import SwiftUI

/// A floating NSPanel that hosts the GhostClip overlay editor.
/// Behaves like a popover: floats above all windows, dismisses on outside click.
final class OverlayPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        backgroundColor = .windowBackgroundColor
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow

        // Auto-dismiss when clicking outside
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
    }

    /// Shows the overlay centered on the screen with the given SwiftUI view.
    func showOverlay<Content: View>(@ViewBuilder content: () -> Content) {
        let hostingView = NSHostingView(rootView: content())
        contentView = hostingView

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelSize = NSSize(width: 900, height: 700)
        let origin = NSPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.midY - panelSize.height / 2
        )
        setFrame(NSRect(origin: origin, size: panelSize), display: true)

        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismissOverlay() {
        orderOut(nil)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
