import AppKit
import SwiftUI

/// Floating panel above all windows, bottom-center. Never takes keyboard focus.
final class OverlayPanel: NSPanel {
    /// Screen to show on — set to the screen of the app being dictated in.
    var preferredScreen: NSScreen?

    init(model: OverlayModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: OverlayView(model: model))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        guard let screen = preferredScreen ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        setFrameOrigin(NSPoint(
            x: frame.midX - self.frame.width / 2,
            y: frame.minY + 100
        ))
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}
