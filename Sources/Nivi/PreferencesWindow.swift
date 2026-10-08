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
    private static var fullScreenCorners: FullScreenCorners?
    private static var tester: ModelTester?
    private static var fileTranscription: FileTranscriptionService?

    static func configure(store: ModelStore, profileStore: ProfileStore,
                          tester: ModelTester, fileTranscription: FileTranscriptionService) {
        self.store = store
        self.profileStore = profileStore
        self.tester = tester
        self.fileTranscription = fileTranscription
    }

    /// Re-applies the AppKit side of the window after a tuning change; SwiftUI redraws
    /// itself.
    static func refreshWindowChrome() {
        guard let window else { return }
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

    /// How the window frame looks and behaves. Kept apart from `show()` so the screenshot
    /// tool can build a window with exactly the same chrome.
    ///
    /// The close, minimise and zoom buttons are placed by AppKit, not by Nivi. They sit
    /// lower than a plain titlebar would put them because of the empty toolbar below:
    /// a unified toolbar makes the titlebar taller, and AppKit centres the buttons in it,
    /// which lands them inside the sidebar's rounded panel.
    ///
    /// Nivi used to pin the buttons there itself with constraints. They were drawn in the
    /// right place, but AppKit decides where the mouse counts as "over the buttons" from
    /// its own position for them, not from where they are drawn, and it clips clicks to
    /// the 32 pt titlebar they had been pushed out of. Measured: the hover area was
    /// 9 to 23 pt from the top while the buttons were drawn at 21 to 35 pt, and the bottom
    /// 3 pt of each button did not take clicks at all. Hover and clicks only worked along
    /// the top edge. Letting AppKit place the buttons keeps what is drawn and what is
    /// clickable the same thing: 19 to 33 pt for both.
    static func configureChrome(of win: NSWindow) {
        win.title = "Nivi"
        win.titleVisibility = .hidden            // tab is shown in the sidebar, not the titlebar
        win.titlebarAppearsTransparent = true    // traffic lights float over the sidebar
        let toolbar = NSToolbar(identifier: "preferences")
        toolbar.allowsUserCustomization = false
        win.toolbar = toolbar
        win.toolbarStyle = .unified
        win.titlebarSeparatorStyle = .none
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 760, height: 520)
        win.maxSize = NSSize(width: 1600, height: 1200)
        win.collectionBehavior.insert(.fullScreenPrimary)   // native green-button fullscreen
        // The window is rounded to match the sidebar panel, which means drawing its own
        // corners: a clear, non-opaque window plus a masked content layer. Nothing paints
        // the window background any more, so SettingsView has to supply one: see the
        // material behind its root view.
        win.isOpaque = false
        win.backgroundColor = .clear
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
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let store, let profileStore, let tester, let fileTranscription else { return }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        configureChrome(of: win)
        win.center()
        win.contentView = NSHostingView(
            rootView: SettingsView(store: store, profileStore: profileStore,
                                   tester: tester, fileTranscription: fileTranscription))
        applyCornerRadius(to: win)

        let corners = FullScreenCorners()
        win.delegate = corners
        fullScreenCorners = corners   // NSWindow holds its delegate weakly

        window = win
        win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

/// Squares the window's corners in fullscreen and rounds them again afterwards.
private final class FullScreenCorners: NSObject, NSWindowDelegate {
    func windowWillEnterFullScreen(_ notification: Notification) {
        // Squared off directly rather than via applyCornerRadius: the style mask does not
        // report .fullScreen yet at this point.
        if let win = notification.object as? NSWindow {
            win.contentView?.layer?.cornerRadius = 0
            PreferencesWindowChrome.shared.cornerRadius = 0
        }
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        if let win = notification.object as? NSWindow {
            PreferencesWindow.applyCornerRadius(to: win)
        }
    }
}
