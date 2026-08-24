import CoreGraphics
import Foundation

/// Layout numbers that get adjusted by eye rather than derived from anything.
///
/// Each one is read from UserDefaults at layout time with the shipped value as the
/// fallback, so a number can be tried with `defaults write com.dvir.dictato <key> -int N`
/// and seen by reopening Preferences. Finding the pixel that looks right is guesswork,
/// and a rebuild per attempt makes it slow enough that it doesn't get done properly.
///
/// These are tuning aids, not user settings — nothing in the UI exposes them, and the
/// fallbacks here are what ships. Use `Tools/ui-tune.sh` to list, set and reset them.
enum UITuning {
    // Sidebar
    static var sidebarWidth: CGFloat { value("sidebarWidth", 220) }
    static var sidebarInset: CGFloat { value("sidebarInset", 10) }
    static var sidebarCorner: CGFloat { value("sidebarCorner", 14) }

    // Brand row at the top of the sidebar. The top pad also has to clear the traffic
    // lights, which sit inside the sidebar panel.
    static var brandTop: CGFloat { value("brandTop", 40) }
    static var brandBottom: CGFloat { value("brandBottom", 10) }
    static var brandLeading: CGFloat { value("brandLeading", 16) }

    // Detail panes (Models, Profiles)
    static var contentPadding: CGFloat { value("contentPadding", 20) }
    static var cardSpacing: CGFloat { value("cardSpacing", 12) }
    static var cardPadding: CGFloat { value("cardPadding", 14) }
    static var cardCorner: CGFloat { value("cardCorner", 12) }

    /// Zero and negative are treated as "unset" so a stray `defaults write … 0` can't
    /// collapse the layout into something unrecoverable without a reset.
    private static func value(_ key: String, _ fallback: CGFloat) -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: key)
        return stored > 0 ? CGFloat(stored) : fallback
    }

    /// Every key with its shipped default, for the tuning script and for baking values in.
    static let keys: [(String, CGFloat)] = [
        ("sidebarWidth", 220), ("sidebarInset", 10), ("sidebarCorner", 14),
        ("brandTop", 40), ("brandBottom", 10), ("brandLeading", 16),
        ("contentPadding", 20), ("cardSpacing", 12), ("cardPadding", 14), ("cardCorner", 12),
        ("trafficLightX", 22), ("trafficLightTop", 22), ("trafficLightPitch", 20),
    ]
}
