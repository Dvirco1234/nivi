import AppKit
import Combine
import SwiftUI

/// Hosts `NotchOverlayView` flush against the top of the screen.
///
/// Sitting over the menu bar needs a window level above it, and the frame is pinned to
/// `screen.frame` rather than `visibleFrame` because the latter already excludes the menu
/// bar — which is exactly the strip this is meant to occupy.
final class NotchOverlayPanel: NSPanel {
    var preferredScreen: NSScreen?

    private let model: OverlayModel
    private var heightObserver: AnyCancellable?

    init(model: OverlayModel) {
        self.model = model
        super.init(
            contentRect: NSRect(x: 0, y: 0,
                                width: NotchOverlayView.barWidth(notchWidth: 0),
                                height: NotchOverlayView.barHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Above the menu bar, so the bar can meet the top edge and sit beside the notch.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true    // never steal clicks from the menu bar
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        heightObserver = model.$liveText
            .map { NotchOverlayView.barHeight(liveText: $0) }
            .removeDuplicates()
            .sink { [weak self] _ in self?.reposition() }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        reposition()
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }

    private func reposition() {
        guard let screen = preferredScreen ?? NSScreen.main else { return }
        let notchWidth = Self.notchWidth(of: screen)
        contentView = NSHostingView(rootView: NotchOverlayView(model: model, notchWidth: notchWidth))

        let width = NotchOverlayView.barWidth(notchWidth: notchWidth)
        let height = NotchOverlayView.barHeight(liveText: model.liveText)
        let frame = screen.frame
        setFrame(NSRect(x: frame.midX - width / 2,
                        y: frame.maxY - height,
                        width: width,
                        height: height),
                 display: true)
    }

    /// Width of the physical notch, or 0 on displays without one. `safeAreaInsets.top`
    /// is non-zero only on notched built-in displays, and the auxiliary areas give the
    /// horizontal extent the notch actually occupies.
    private static func notchWidth(of screen: NSScreen) -> CGFloat {
        guard screen.safeAreaInsets.top > 0 else { return 0 }
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        guard left > 0, right > 0 else { return 0 }
        return max(0, screen.frame.width - left - right)
    }
}
