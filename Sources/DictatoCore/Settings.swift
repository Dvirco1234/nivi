import Foundation

public enum InsertionMode: String, Codable, CaseIterable {
    case batch, overlayLive, inAppLive

    public var isImplemented: Bool { self == .batch }   // 2a: only batch

    public var displayName: String {
        switch self {
        case .batch: return "Batch (record, then paste)"
        case .overlayLive: return "Live preview in overlay"
        case .inAppLive: return "Live typing into app"
        }
    }
}

/// UserDefaults-backed settings. Edit via Preferences or `defaults write com.dvir.dictato <key> <value>`.
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
            Key.excludeFromClipboardHistory: true,
            Key.recognizerCacheCapacity: 2,
            Key.idleUnloadSeconds: 300,
        ])
    }

    private enum Key {
        static let autoPaste = "autoPaste"
        static let showOverlay = "showOverlay"
        static let doubleTapWindowMs = "doubleTapWindowMs"
        static let maxRecordingSeconds = "maxRecordingSeconds"
        static let verboseLogging = "verboseLogging"
        static let modelPathOverride = "modelPathOverride"
        static let insertionMode = "insertionMode"
        static let playSounds = "playSounds"
        static let copyOnly = "copyOnly"
        static let showInferenceTime = "showInferenceTime"
        static let showAudioDuration = "showAudioDuration"
        static let dictateBinding = "dictateBinding"
        static let cancelBinding = "cancelBinding"
        static let excludeFromClipboardHistory = "excludeFromClipboardHistory"
        static let recognizerCacheCapacity = "recognizerCacheCapacity"
        static let idleUnloadSeconds = "idleUnloadSeconds"
    }

    public var autoPaste: Bool {
        get { defaults.bool(forKey: Key.autoPaste) }
        nonmutating set { defaults.set(newValue, forKey: Key.autoPaste) }
    }

    public var showOverlay: Bool {
        get { defaults.bool(forKey: Key.showOverlay) }
        nonmutating set { defaults.set(newValue, forKey: Key.showOverlay) }
    }

    public var doubleTapWindowMs: Int {
        get { defaults.integer(forKey: Key.doubleTapWindowMs) }
        nonmutating set { defaults.set(newValue, forKey: Key.doubleTapWindowMs) }
    }

    public var maxRecordingSeconds: Int {
        get { defaults.integer(forKey: Key.maxRecordingSeconds) }
        nonmutating set { defaults.set(newValue, forKey: Key.maxRecordingSeconds) }
    }

    public var verboseLogging: Bool {
        get { defaults.bool(forKey: Key.verboseLogging) }
        nonmutating set { defaults.set(newValue, forKey: Key.verboseLogging) }
    }

    public var modelPathOverride: String? {
        get { defaults.string(forKey: Key.modelPathOverride) }
        nonmutating set { defaults.set(newValue, forKey: Key.modelPathOverride) }
    }

    public var insertionMode: InsertionMode {
        get { InsertionMode(rawValue: defaults.string(forKey: Key.insertionMode) ?? "") ?? .batch }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.insertionMode) }
    }

    public var playSounds: Bool {
        get { defaults.bool(forKey: Key.playSounds) }
        nonmutating set { defaults.set(newValue, forKey: Key.playSounds) }
    }

    public var copyOnly: Bool {
        get { defaults.bool(forKey: Key.copyOnly) }
        nonmutating set { defaults.set(newValue, forKey: Key.copyOnly) }
    }

    public var showInferenceTime: Bool {
        get { defaults.bool(forKey: Key.showInferenceTime) }
        nonmutating set { defaults.set(newValue, forKey: Key.showInferenceTime) }
    }

    public var showAudioDuration: Bool {
        get { defaults.bool(forKey: Key.showAudioDuration) }
        nonmutating set { defaults.set(newValue, forKey: Key.showAudioDuration) }
    }

    public var dictateBinding: HotkeyBinding {
        get { HotkeyBinding.from(json: defaults.string(forKey: Key.dictateBinding) ?? "") ?? .defaultDictate }
        nonmutating set { defaults.set(newValue.encodedJSON(), forKey: Key.dictateBinding) }
    }

    public var cancelBinding: HotkeyBinding {
        get { HotkeyBinding.from(json: defaults.string(forKey: Key.cancelBinding) ?? "") ?? .defaultCancel }
        nonmutating set { defaults.set(newValue.encodedJSON(), forKey: Key.cancelBinding) }
    }

    public var excludeFromClipboardHistory: Bool {
        get { defaults.bool(forKey: Key.excludeFromClipboardHistory) }
        nonmutating set { defaults.set(newValue, forKey: Key.excludeFromClipboardHistory) }
    }

    public var recognizerCacheCapacity: Int {
        get { max(1, defaults.integer(forKey: Key.recognizerCacheCapacity)) }
        nonmutating set { defaults.set(max(1, newValue), forKey: Key.recognizerCacheCapacity) }
    }

    /// Seconds of inactivity before the loaded model is released from memory (0 = never).
    public var idleUnloadSeconds: Int {
        get { defaults.integer(forKey: Key.idleUnloadSeconds) }
        nonmutating set { defaults.set(newValue, forKey: Key.idleUnloadSeconds) }
    }
}
