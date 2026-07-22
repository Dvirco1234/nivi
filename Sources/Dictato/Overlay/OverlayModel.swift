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
    }
}
