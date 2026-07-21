import Foundation

/// UserDefaults-backed settings. No UI in v1 — edit via `defaults write com.dvir.dictato <key> <value>`.
public struct Settings {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.autoPaste: true,
            Key.showOverlay: true,
            Key.doubleTapWindowMs: 400,
            Key.maxRecordingSeconds: 600,
            Key.verboseLogging: false,
        ])
    }

    private enum Key {
        static let autoPaste = "autoPaste"
        static let showOverlay = "showOverlay"
        static let doubleTapWindowMs = "doubleTapWindowMs"
        static let maxRecordingSeconds = "maxRecordingSeconds"
        static let verboseLogging = "verboseLogging"
        static let modelPathOverride = "modelPathOverride"
    }

    public var autoPaste: Bool {
        get { defaults.bool(forKey: Key.autoPaste) }
        set { defaults.set(newValue, forKey: Key.autoPaste) }
    }

    public var showOverlay: Bool {
        get { defaults.bool(forKey: Key.showOverlay) }
        set { defaults.set(newValue, forKey: Key.showOverlay) }
    }

    public var doubleTapWindowMs: Int {
        get { defaults.integer(forKey: Key.doubleTapWindowMs) }
        set { defaults.set(newValue, forKey: Key.doubleTapWindowMs) }
    }

    public var maxRecordingSeconds: Int {
        get { defaults.integer(forKey: Key.maxRecordingSeconds) }
        set { defaults.set(newValue, forKey: Key.maxRecordingSeconds) }
    }

    public var verboseLogging: Bool {
        get { defaults.bool(forKey: Key.verboseLogging) }
        set { defaults.set(newValue, forKey: Key.verboseLogging) }
    }

    public var modelPathOverride: String? {
        get { defaults.string(forKey: Key.modelPathOverride) }
        set { defaults.set(newValue, forKey: Key.modelPathOverride) }
    }
}
