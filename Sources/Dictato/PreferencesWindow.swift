import AppKit
import SwiftUI

enum PreferencesWindow {
    private static var window: NSWindow?
    private static var store: ModelStore?
    private static var profileStore: ProfileStore?

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
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        win.title = "Dictato"
        win.isReleasedWhenClosed = false
        win.center()
        win.contentView = NSHostingView(rootView: SettingsView(store: store, profileStore: profileStore))
        window = win
        win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}
