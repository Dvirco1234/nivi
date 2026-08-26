import AppKit
import SwiftUI

/// The rounded corners the window draws for itself, published so SwiftUI can clip its
/// background to exactly the same shape. Without a shared value the background would keep
/// its rounded corners in fullscreen, where the window itself is squared off.
final class PreferencesWindowChrome: ObservableObject {
    static let shared = PreferencesWindowChrome()
    @Published fileprivate(set) var cornerRadius: CGFloat = UITuning.sidebarCorner
}

enum PreferencesWindow {
    private static var window: NSWindow?
    private static var store: ModelStore?
    private static var profileStore: ProfileStore?
    private static var trafficLights: TrafficLightLayout?
    private static var tester: ModelTester?
    private static var fileTranscription: FileTranscriptionService?

    static func configure(store: ModelStore, profileStore: ProfileStore,
                          tester: ModelTester, fileTranscription: FileTranscriptionService) {
        self.store = store
        self.profileStore = profileStore
        self.tester = tester
        self.fileTranscription = fileTranscription
    }

    /// Re-runs the AppKit button layout after a tuning change; SwiftUI redraws itself.
    static func refreshTrafficLights() {
        guard let window else { return }
        trafficLights?.reposition(window)
        applyCornerRadius(to: window)
    }

    /// Rounds the window to the same radius as the sidebar panel. Skipped in fullscreen,
    /// where rounded corners against the screen edge just look like a mistake.
    static func applyCornerRadius(to window: NSWindow) {
        guard let layer = window.contentView?.layer ?? {
            window.contentView?.wantsLayer = true
            return window.contentView?.layer
        }() else { return }
        let fullScreen = window.styleMask.contains(.fullScreen)
        let radius = fullScreen ? 0 : UITuning.sidebarCorner
        layer.cornerRadius = radius
        layer.masksToBounds = true
        PreferencesWindowChrome.shared.cornerRadius = radius
    }

    static func show() {
        UITuning.reload()
        if let window {
            // Rebuild the SwiftUI tree on every open so tweaked UITuning values take
            // effect by closing and reopening, without restarting the app. The view is
            // cheap to build and this only runs when the user opens Preferences.
            if let store, let profileStore, let tester, let fileTranscription {
                window.contentView = NSHostingView(
                    rootView: SettingsView(store: store, profileStore: profileStore,
                                           tester: tester, fileTranscription: fileTranscription))
            }
            applyCornerRadius(to: window)
            window.makeKeyAndOrderFront(nil)
            trafficLights?.reposition(window)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let store, let profileStore, let tester, let fileTranscription else { return }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        win.title = "Nivi"
        win.titleVisibility = .hidden            // tab is shown in the sidebar, not the titlebar
        win.titlebarAppearsTransparent = true    // traffic lights float over the sidebar
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 760, height: 520)
        win.maxSize = NSSize(width: 1600, height: 1200)
        win.collectionBehavior.insert(.fullScreenPrimary)   // native green-button fullscreen
        // The window is rounded to match the sidebar panel, which means drawing its own
        // corners: a clear, non-opaque window plus a masked content layer. Nothing paints
        // the window background any more, so SettingsView has to supply one — see the
        // material behind its root view.
        win.isOpaque = false
        win.backgroundColor = .clear
        win.center()
        win.contentView = NSHostingView(
            rootView: SettingsView(store: store, profileStore: profileStore,
                                   tester: tester, fileTranscription: fileTranscription))
        applyCornerRadius(to: win)

        // Nudge the traffic lights down/right so they sit inside the inset sidebar panel.
        let layout = TrafficLightLayout()
        win.delegate = layout
        trafficLights = layout
        layout.install(in: win)

        window = win
        win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

/// Moves the standard window buttons into the sidebar's inset rounded panel and
/// keeps them there.
///
/// AppKit owns these buttons and puts them back at their default spot every time the
/// titlebar lays itself out, which happens whenever the window content changes —
/// switching a tab in the sidebar is enough. Setting `frame` once therefore does not
/// hold, and setting it again from a frame-change notification does not either: moving
/// one button makes the titlebar lay out again straight away, which undoes the moves we
/// just made to the other two. Measured on a tab switch, that fight ended with the close
/// and miniaturise buttons in place and the zoom button left at the system position.
///
/// So the buttons are placed with constraints instead of frames. The titlebar's own
/// layout pass then computes their position from those constraints rather than
/// overwriting it, and there is nothing left to fight about.
private final class TrafficLightLayout: NSObject, NSWindowDelegate {
    // Panel inset (10) matches SettingsView's sidebar `.padding(10)`, plus an
    // interior margin so the lights sit comfortably inside the rounded corner.
    //
    // Read when the constraints are built or refreshed rather than baked in, so the
    // position can be nudged in the tuning file and seen by reopening the window —
    // finding the pixel that looks right is guesswork that shouldn't need a rebuild
    // each try.
    private var x: CGFloat { UITuning.trafficLightX }
    private var topMargin: CGFloat { UITuning.trafficLightTop }
    private var pitch: CGFloat { UITuning.trafficLightPitch }
    private var inFullScreen = false

    private static let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    /// One entry per button. The constraints are kept so the tuning sliders can move the
    /// buttons by changing a constant, and so they can be torn down for fullscreen.
    private var placements: [(button: NSButton, left: NSLayoutConstraint, top: NSLayoutConstraint)] = []

    /// Pins the buttons to the top-left of the titlebar.
    /// Safe to call again: the previous constraints are removed first. That matters after
    /// leaving fullscreen, where the system hands the window a fresh titlebar view.
    func install(in window: NSWindow) {
        removeConstraints()
        guard !inFullScreen else { return }   // system owns the buttons in fullscreen
        let buttons = Self.buttonTypes.compactMap { window.standardWindowButton($0) }
        guard buttons.count == 3, let titlebar = buttons.first?.superview else { return }
        for (index, button) in buttons.enumerated() {
            button.translatesAutoresizingMaskIntoConstraints = false
            // Left, not leading: the traffic lights stay on the left even when the app is
            // showing Hebrew and the interface flips to right-to-left.
            let left = button.leftAnchor.constraint(
                equalTo: titlebar.leftAnchor, constant: x + CGFloat(index) * pitch)
            let top = button.topAnchor.constraint(equalTo: titlebar.topAnchor, constant: topMargin)
            NSLayoutConstraint.activate([left, top])
            placements.append((button, left, top))
        }
        titlebar.needsLayout = true
    }

    /// Applies the current tuning values. Builds the constraints first if they are missing,
    /// so this doubles as "put them where they belong now".
    func reposition(_ window: NSWindow) {
        guard !inFullScreen else { return }
        guard !placements.isEmpty else { return install(in: window) }
        for (index, placement) in placements.enumerated() {
            placement.left.constant = x + CGFloat(index) * pitch
            placement.top.constant = topMargin
        }
        placements.first?.button.superview?.needsLayout = true
    }

    /// Hands the buttons back to AppKit, which needs their frames under its own control.
    private func removeConstraints() {
        for placement in placements {
            NSLayoutConstraint.deactivate([placement.left, placement.top])
            placement.button.translatesAutoresizingMaskIntoConstraints = true
        }
        placements.removeAll()
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        inFullScreen = true
        removeConstraints()   // the system places the buttons itself in fullscreen
        // Squared off directly rather than via applyCornerRadius: the style mask does not
        // report .fullScreen yet at this point.
        if let win = notification.object as? NSWindow {
            win.contentView?.layer?.cornerRadius = 0
            PreferencesWindowChrome.shared.cornerRadius = 0
        }
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        inFullScreen = false
        if let win = notification.object as? NSWindow {
            install(in: win)
            PreferencesWindow.applyCornerRadius(to: win)
        }
    }
}
