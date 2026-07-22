import AppKit
import SwiftUI

/// Floating panel above all windows, bottom-center. Never takes keyboard focus.
final class OverlayPanel: NSPanel {
    init(model: OverlayModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: OverlayView(model: model))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        guard let screen = NSScreen.main else { return }
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
