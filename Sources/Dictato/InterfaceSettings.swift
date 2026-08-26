import AppKit
import DictatoCore

/// Where Dictato shows itself: the theme, the Dock icon and the menu bar icon.
///
/// One place owns all three, because they are applied from two directions. Preferences
/// changes them while the app runs, and the app has to apply the same settings at launch.
/// Anything that changes them calls `announceChange()`, and the parts that draw something
/// listen for it.
enum InterfaceSettings {

    /// Posted after a change so the Dock icon, the theme and the menu bar icon catch up.
    static let changed = Notification.Name("dictatoInterfaceChanged")

    static func announceChange() {
        NotificationCenter.default.post(name: changed, object: nil)
    }

    /// Applies everything `NSApp` owns. The menu bar icon is `MenuBarController`'s, since
    /// it is the object that holds it.
    static func applyToApp() {
        applyAppearance()
        applyDockIcon()
    }

    static func applyAppearance() {
        // A nil appearance is not "no theme", it is "follow the system", which is exactly
        // what the System option means.
        switch Settings().appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    static func applyDockIcon() {
        NSApp.setActivationPolicy(Settings().showInDock ? .regular : .accessory)
    }

    /// Dictato must always be reachable from either the Dock or the menu bar. The
    /// Preferences toggles will not let the last one be turned off, but the settings are
    /// also plain `defaults` keys anyone can write, so check at launch too. The menu bar
    /// is the one turned back on: it is there whatever window is in front.
    static func makeSureTheAppIsReachable() {
        let settings = Settings()
        guard !settings.showInDock, !settings.showInStatusBar else { return }
        settings.showInStatusBar = true
        Log.info("Dock icon and menu bar icon were both off — turned the menu bar icon back on")
    }
}
