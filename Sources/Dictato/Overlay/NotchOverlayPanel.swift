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
    private var layoutObservers: Set<AnyCancellable> = []
    /// The screen measurements the hosted view was built with, so the view is only
    /// rebuilt when they actually change rather than on every reposition.
    private var hostedShape: (notchWidth: CGFloat, stripHeight: CGFloat) = (-1, -1)

    init(model: OverlayModel) {
        self.model = model
        super.init(
            contentRect: NSRect(x: 0, y: 0,
                                width: NotchOverlayView.barWidth(notchWidth: 0),
                                height: NSStatusBar.system.thickness),
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

        model.$liveText
            .map(\.isEmpty)
            .removeDuplicates()
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &layoutObservers)
        // The Layout sliders change the bar's width, so it has to be re-laid out while
        // it is on screen or the window keeps the old size and clips the bar.
        UITuning.Store.shared.$overrides
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &layoutObservers)
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
        let notch = Self.notchArea(of: screen)
        let notchWidth = notch?.width ?? 0
        let stripHeight = Self.topStripHeight(of: screen)
        if (notchWidth, stripHeight) != hostedShape {
            contentView = NSHostingView(rootView: NotchOverlayView(
                model: model, notchWidth: notchWidth, stripHeight: stripHeight))
            hostedShape = (notchWidth, stripHeight)
        }

        let width = NotchOverlayView.barWidth(notchWidth: notchWidth)
        let height = NotchOverlayView.barHeight(stripHeight: stripHeight, liveText: model.liveText)
        // Line the bar's empty middle up with the real notch. Centring on the screen
        // would only work while both sides are the same width, and they are not: the
        // icons need less room than the wave, so the wave would slide under the notch.
        let left = notch.map { $0.left - NotchOverlayView.leftWidth }
            ?? (screen.frame.midX - width / 2)
        setFrame(NSRect(x: left,
                        y: screen.frame.maxY - height,
                        width: width,
                        height: height),
                 display: true)
    }

    /// Where the physical notch sits, in screen coordinates, or nil on a display without
    /// one. `safeAreaInsets.top` is non-zero only on notched built-in displays, and the
    /// two auxiliary areas are the strips of menu bar either side of the notch, so the
    /// gap between them is the notch.
    private static func notchArea(of screen: NSScreen) -> (left: CGFloat, width: CGFloat)? {
        guard screen.safeAreaInsets.top > 0,
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea,
              rightArea.minX > leftArea.maxX else { return nil }
        return (leftArea.maxX, rightArea.minX - leftArea.maxX)
    }

    /// How far down from the top edge the notch and the menu bar reach.
    ///
    /// On a notched display the notch ends exactly `safeAreaInsets.top` below the top of
    /// the screen, so matching that puts the bar's bottom edge on the bottom of the
    /// notch with nothing hanging over. Displays without a notch have no such number, so
    /// they get the menu bar's height instead, which is the strip they do have.
    private static func topStripHeight(of screen: NSScreen) -> CGFloat {
        if screen.safeAreaInsets.top > 0 { return screen.safeAreaInsets.top }
        let menuBar = NSApp.mainMenu?.menuBarHeight ?? 0
        return menuBar > 0 ? menuBar : NSStatusBar.system.thickness
    }
}
