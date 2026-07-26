import AppKit
import SwiftUI

enum PreferencesWindow {
    private static var window: NSWindow?
    private static var store: ModelStore?
    private static var profileStore: ProfileStore?
    private static var trafficLights: TrafficLightLayout?

    static func configure(store: ModelStore, profileStore: ProfileStore) {
        self.store = store
        self.profileStore = profileStore
    }

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        guard let store, let profileStore else { return }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        win.title = "Dictato"
        win.titleVisibility = .hidden            // tab is shown in the sidebar, not the titlebar
        win.titlebarAppearsTransparent = true    // traffic lights float over the sidebar
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 760, height: 520)
        win.maxSize = NSSize(width: 1600, height: 1200)
        win.collectionBehavior.insert(.fullScreenPrimary)   // native green-button fullscreen
        win.center()
        win.contentView = NSHostingView(rootView: SettingsView(store: store, profileStore: profileStore))

        // Nudge the traffic lights down/right so they sit inside the inset sidebar panel.
        let layout = TrafficLightLayout()
        win.delegate = layout
        trafficLights = layout
        layout.reposition(win)

        window = win
        win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

/// Moves the standard window buttons into the sidebar's inset rounded panel and
/// keeps them there across resizes and fullscreen transitions.
private final class TrafficLightLayout: NSObject, NSWindowDelegate {
    // Panel inset (10) matches SettingsView's sidebar `.padding(10)`, plus an
    // interior margin so the lights sit comfortably inside the rounded corner.
    private let x: CGFloat = 22
    private let topMargin: CGFloat = 22
    private let pitch: CGFloat = 20
    private var inFullScreen = false

    func reposition(_ window: NSWindow) {
        guard !inFullScreen else { return }   // system owns the buttons in fullscreen
        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let buttons = types.compactMap { window.standardWindowButton($0) }
        guard buttons.count == 3, let frame = buttons.first?.superview else { return }
        DispatchQueue.main.async {
            for (i, button) in buttons.enumerated() {
                var f = button.frame
                f.origin.x = self.x + CGFloat(i) * self.pitch
                f.origin.y = frame.bounds.height - self.topMargin - f.height
                button.frame = f
            }
        }
    }

    func windowDidResize(_ notification: Notification) {
        if let win = notification.object as? NSWindow { reposition(win) }
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        if let win = notification.object as? NSWindow { reposition(win) }
    }
    func windowWillEnterFullScreen(_ notification: Notification) { inFullScreen = true }
    func windowDidExitFullScreen(_ notification: Notification) {
        inFullScreen = false
        if let win = notification.object as? NSWindow { reposition(win) }
    }
}
