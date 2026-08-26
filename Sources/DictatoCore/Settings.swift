import Foundation

public enum InsertionMode: String, Codable, CaseIterable {
    case batch, batchFastFinish, overlayLive, inAppLive

    public var displayName: String {
        switch self {
        case .batch: return "Batch (record, then paste)"
        case .batchFastFinish: return "Batch, fast finish (transcribes while you speak)"
        case .overlayLive: return "Live preview in overlay"
        case .inAppLive: return "Live typing into app"
        }
    }

    /// Whether the transcriber runs during the recording instead of only at the end.
    ///
    /// Plain batch waits for the whole recording, so the wait at the end grows with how
    /// long you spoke. Every other mode transcribes as you go, which leaves only the
    /// unfinished tail for the final pass. They differ in what they show while doing it,
    /// not in whether they do it.
    public var streamsDuringRecording: Bool { self != .batch }
}

/// How the app follows the system theme, or overrides it.
public enum AppAppearance: String, Codable, CaseIterable, Sendable {
    case system, light, dark

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// How dictated text gets into the other app.
public enum TextInputMethod: String, Codable, CaseIterable, Sendable {
    /// Put the text on the clipboard and press Cmd-V. Fast.
    case paste
    /// Send the characters as key presses. Slower, but leaves the clipboard alone.
    case type

    public var displayName: String {
        switch self {
        case .paste: return "Paste (Cmd-V)"
        case .type: return "Type it out"
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
            Key.removeSoundDescriptions: true,
            Key.profilesJSON: "",
            Key.streamingIntervalMs: 500,
            Key.streamingWindowSeconds: 10,
            Key.recordingDisplay: RecordingDisplay.panel.rawValue,
            Key.appearance: AppAppearance.system.rawValue,
            Key.showInDock: true,
            Key.showInStatusBar: true,
            Key.escapeToCancelEnabled: true,
            Key.muteWhileRecording: false,
            Key.trackpadFeedback: false,
            Key.textInputMethod: TextInputMethod.paste.rawValue,
            Key.microphonePriority: "",
            Key.wordReplacementsJSON: "",
            Key.historyEnabled: true,
            Key.historyRetentionDays: 30,
            Key.fileChunkMinutes: 5,
            Key.volumeBeforeMute: -1,
        ])
    }

    private enum Key {
        static let autoPaste = "autoPaste"
        static let showOverlay = "showOverlay"
        static let doubleTapWindowMs = "doubleTapWindowMs"
        static let maxRecordingSeconds = "maxRecordingSeconds"
        static let verboseLogging = "verboseLogging"
        static let modelPathOverride = "modelPathOverride"
        static let playSounds = "playSounds"
        static let copyOnly = "copyOnly"
        static let showInferenceTime = "showInferenceTime"
        static let showAudioDuration = "showAudioDuration"
        static let dictateBinding = "dictateBinding"
        static let cancelBinding = "cancelBinding"
        static let excludeFromClipboardHistory = "excludeFromClipboardHistory"
        static let recognizerCacheCapacity = "recognizerCacheCapacity"
        static let removeSoundDescriptions = "removeSoundDescriptions"
        static let idleUnloadSeconds = "idleUnloadSeconds"
        static let profilesJSON = "profilesJSON"
        static let streamingIntervalMs = "streamingIntervalMs"
        static let streamingWindowSeconds = "streamingWindowSeconds"
        static let recordingDisplay = "recordingDisplay"
        static let appearance = "appearance"
        static let showInDock = "showInDock"
        static let showInStatusBar = "showInStatusBar"
        static let escapeToCancelEnabled = "escapeToCancelEnabled"
        static let muteWhileRecording = "muteWhileRecording"
        static let trackpadFeedback = "trackpadFeedback"
        static let textInputMethod = "textInputMethod"
        static let microphonePriority = "microphonePriority"
        static let wordReplacementsJSON = "wordReplacementsJSON"
        static let historyEnabled = "historyEnabled"
        static let historyRetentionDays = "historyRetentionDays"
        static let fileChunkMinutes = "fileChunkMinutes"
        static let volumeBeforeMute = "volumeBeforeMute"
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

    /// Whether to drop the notes a model writes about sounds, such as `(music)`.
    ///
    /// On by default. Dictato writes down speech, so a note about a sound is never
    /// something the user said. See `TranscriptCleaning` for what counts as one.
    public var removeSoundDescriptions: Bool {
        get { defaults.bool(forKey: Key.removeSoundDescriptions) }
        nonmutating set { defaults.set(newValue, forKey: Key.removeSoundDescriptions) }
    }

    /// Seconds of inactivity before the loaded model is released from memory (0 = never).
    public var idleUnloadSeconds: Int {
        get { defaults.integer(forKey: Key.idleUnloadSeconds) }
        nonmutating set { defaults.set(newValue, forKey: Key.idleUnloadSeconds) }
    }

    public var profilesJSON: String {
        get { defaults.string(forKey: Key.profilesJSON) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: Key.profilesJSON) }
    }

    public var streamingIntervalMs: Int {
        get { defaults.integer(forKey: Key.streamingIntervalMs) }
        nonmutating set { defaults.set(newValue, forKey: Key.streamingIntervalMs) }
    }

    public var recordingDisplay: RecordingDisplay {
        get { RecordingDisplay(rawValue: defaults.string(forKey: Key.recordingDisplay) ?? "") ?? .panel }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.recordingDisplay) }
    }

    public var streamingWindowSeconds: Int {
        get { defaults.integer(forKey: Key.streamingWindowSeconds) }
        nonmutating set { defaults.set(newValue, forKey: Key.streamingWindowSeconds) }
    }

    // MARK: - Settings the Preferences redesign will use
    //
    // These are stored in this release so later work only adds behaviour and never
    // changes what is written to disk. Nothing reads them yet.

    public var appearance: AppAppearance {
        get { AppAppearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.appearance) }
    }

    public var showInDock: Bool {
        get { defaults.bool(forKey: Key.showInDock) }
        nonmutating set { defaults.set(newValue, forKey: Key.showInDock) }
    }

    public var showInStatusBar: Bool {
        get { defaults.bool(forKey: Key.showInStatusBar) }
        nonmutating set { defaults.set(newValue, forKey: Key.showInStatusBar) }
    }

    /// Whether the recorded cancel key is listened for at all.
    public var escapeToCancelEnabled: Bool {
        get { defaults.bool(forKey: Key.escapeToCancelEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.escapeToCancelEnabled) }
    }

    public var muteWhileRecording: Bool {
        get { defaults.bool(forKey: Key.muteWhileRecording) }
        nonmutating set { defaults.set(newValue, forKey: Key.muteWhileRecording) }
    }

    /// The system output volume from before we muted it, so it can be put back even if
    /// the app is killed mid-recording. Below zero means nothing is saved.
    public var volumeBeforeMute: Double {
        get { defaults.double(forKey: Key.volumeBeforeMute) }
        nonmutating set { defaults.set(newValue, forKey: Key.volumeBeforeMute) }
    }

    public var trackpadFeedback: Bool {
        get { defaults.bool(forKey: Key.trackpadFeedback) }
        nonmutating set { defaults.set(newValue, forKey: Key.trackpadFeedback) }
    }

    public var textInputMethod: TextInputMethod {
        get { TextInputMethod(rawValue: defaults.string(forKey: Key.textInputMethod) ?? "") ?? .paste }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.textInputMethod) }
    }

    /// Microphone unique ids, best first, as a JSON array of strings.
    public var microphonePriority: String {
        get { defaults.string(forKey: Key.microphonePriority) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: Key.microphonePriority) }
    }

    /// `WordReplacement` rules as JSON. Read it with `WordReplacing.decode(json:)`.
    public var wordReplacementsJSON: String {
        get { defaults.string(forKey: Key.wordReplacementsJSON) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: Key.wordReplacementsJSON) }
    }

    public var historyEnabled: Bool {
        get { defaults.bool(forKey: Key.historyEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.historyEnabled) }
    }

    /// Days to keep saved transcriptions. Zero keeps them forever.
    public var historyRetentionDays: Int {
        get { max(0, defaults.integer(forKey: Key.historyRetentionDays)) }
        nonmutating set { defaults.set(max(0, newValue), forKey: Key.historyRetentionDays) }
    }

    /// How long each piece of a long file is when it is transcribed in parts.
    public var fileChunkMinutes: Int {
        get { min(15, max(1, defaults.integer(forKey: Key.fileChunkMinutes))) }
        nonmutating set { defaults.set(min(15, max(1, newValue)), forKey: Key.fileChunkMinutes) }
    }
}
