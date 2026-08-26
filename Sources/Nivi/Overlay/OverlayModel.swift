import AppKit

enum OverlayPhase: Equatable {
    case hidden
    case recording(elapsed: TimeInterval)
    case processing
    case success
    case error(String)
}

final class OverlayModel: ObservableObject {
    @Published var phase: OverlayPhase = .hidden
    @Published var levels: [Float] = []
    @Published var targetAppName: String?
    @Published var targetAppIcon: NSImage?
    @Published var languageCode: String = "he"   // running model's language → logo choice
    @Published var liveText: String = ""
    /// Set once when a recording starts, from the user's preference, so turning the
    /// counter off does not make it disappear in the middle of a recording.
    @Published var showsElapsedTime: Bool = true
    var onCancel: (() -> Void)?

    func setTarget(name: String?, icon: NSImage?) {
        targetAppName = name
        targetAppIcon = icon
    }

    static let waveformSlots = 46

    func pushLevel(_ level: Float) {
        levels.append(level)
        if levels.count > Self.waveformSlots {
            levels.removeFirst(levels.count - Self.waveformSlots)
        }
    }

    func reset() {
        levels = []
        liveText = ""
    }
}
