import Foundation

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

    func pushLevel(_ level: Float) {
        levels.append(level)
        if levels.count > 30 {
            levels.removeFirst(levels.count - 30)
        }
    }

    func reset() {
        levels = []
    }
}
