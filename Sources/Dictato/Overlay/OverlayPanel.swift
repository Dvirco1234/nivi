import AppKit
import Combine
import SwiftUI

/// Floating panel above all windows, bottom-center. Never takes keyboard focus.
final class OverlayPanel: NSPanel {
    /// Screen to show on — set to the screen of the app being dictated in.
    var preferredScreen: NSScreen?

    private var heightObserver: AnyCancellable?

    init(model: OverlayModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0,
                                width: OverlayView.cardWidth,
                                height: OverlayView.collapsedHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = false   // needed for hover + click-to-cancel
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: OverlayView(model: model))
        // The card grows when there is live text to show. The panel does not resize
        // itself, so without this the taller card is clipped.
        heightObserver = model.$liveText
            .map { OverlayView.cardHeight(liveText: $0) }
            .removeDuplicates()
            .sink { [weak self] height in self?.setCardHeight(height) }
    }

    /// Resizes around the bottom edge so the card grows upward instead of jumping.
    private func setCardHeight(_ height: CGFloat) {
        guard frame.height != height else { return }
        setFrame(NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: height),
                 display: true)
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
