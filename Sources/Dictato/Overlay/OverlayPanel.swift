import AppKit
import Combine
import SwiftUI

/// Floating panel above all windows, bottom-center. Never takes keyboard focus.
final class OverlayPanel: NSPanel {
    /// Screen to show on — set to the screen of the app being dictated in.
    var preferredScreen: NSScreen?

    private let model: OverlayModel
    private var sizeObservers: Set<AnyCancellable> = []

    init(model: OverlayModel) {
        self.model = model
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
        // The card grows when there is live text to show, and the Layout sliders can
        // change its size while it is on screen. The panel does not resize itself, so
        // without this a bigger card is simply clipped.
        model.$liveText
            .map { OverlayView.cardHeight(liveText: $0) }
            .removeDuplicates()
            .sink { [weak self] _ in self?.resizeToCard() }
            .store(in: &sizeObservers)
        UITuning.Store.shared.$overrides
            .sink { [weak self] _ in self?.resizeToCard() }
            .store(in: &sizeObservers)
    }

    /// Resizes around the bottom edge so the card grows upward instead of jumping, and
    /// keeps the same centre so a width change does not slide the card sideways.
    private func resizeToCard() {
        let width = OverlayView.cardWidth
        let height = OverlayView.cardHeight(liveText: model.liveText)
        guard frame.width != width || frame.height != height else { return }
        setFrame(NSRect(x: frame.midX - width / 2, y: frame.minY, width: width, height: height),
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
