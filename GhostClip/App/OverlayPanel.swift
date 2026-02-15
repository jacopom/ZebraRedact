import AppKit
import SwiftUI

/// A floating NSPanel that hosts the GhostClip overlay editor.
final class OverlayPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
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
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func showOverlay<Content: View>(@ViewBuilder content: () -> Content) {
        let hostingView = NSHostingView(rootView: content())
        contentView = hostingView

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelWidth: CGFloat = min(1000, screenFrame.width * 0.7)
        let panelHeight: CGFloat = min(720, screenFrame.height * 0.75)
        let panelSize = NSSize(width: panelWidth, height: panelHeight)
        let origin = NSPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.midY - panelSize.height / 2
        )
        setFrame(NSRect(origin: origin, size: panelSize), display: true)
        setContentSize(panelSize)

        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismissOverlay() {
        orderOut(nil)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
