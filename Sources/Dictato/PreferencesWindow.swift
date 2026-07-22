import AppKit
import SwiftUI

enum PreferencesWindow {
    private static var window: NSWindow?
    private static var store: ModelStore?

    static func configure(store: ModelStore) { self.store = store }

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        guard let store else { return }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        win.title = "Dictato"
        win.isReleasedWhenClosed = false
        win.center()
        win.contentView = NSHostingView(rootView: SettingsView(store: store))
        window = win
        win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}
