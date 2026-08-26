import Foundation

/// Whether the parts of the app that only make sense to whoever builds it are on.
///
/// Those are the Debug tab (inference timings, verbose logging, the log folder path)
/// and the Layout tab (live sliders that write `ui-tuning.conf`). Someone who
/// downloads Nivi should never meet either of them.
///
/// On in a debug build, which is what `make dev` makes. Off in the release build
/// that goes into the DMG.
///
/// Escape hatch, for running the released build day to day and still wanting the
/// tuning sliders. It is off by default and nothing in the UI mentions it:
///
///     defaults write com.dvir.nivi showDeveloperTabs -bool true
///
/// Read once at launch, so turning it on needs a restart. That is deliberate: the
/// layout numbers are read at startup too, and a flag that could flip mid-session
/// would leave half the window on old values.
enum DeveloperMode {
    static let isOn: Bool = {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: "showDeveloperTabs")
        #endif
    }()
}
