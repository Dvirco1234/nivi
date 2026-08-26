import Foundation

/// Detects taps of the right Command key from a stream of modifier/key events.
/// A "tap" is a press+release with no other key involved during the hold.
public final class ModifierTapDetector {
    public enum Mode {
        case doubleTap
        case singleTap
    }

    public var mode: Mode = .doubleTap
    public var onActivate: (() -> Void)?

    private let doubleTapWindow: TimeInterval
    private let now: () -> TimeInterval
    private var isDown = false
    private var comboUsed = false
    private var pendingTapTime: TimeInterval?

    public init(doubleTapWindow: TimeInterval = 0.4, now: @escaping () -> TimeInterval) {
        self.doubleTapWindow = doubleTapWindow
        self.now = now
    }

    public func modifierChanged(down: Bool) {
        if down {
            isDown = true
            comboUsed = false
            return
        }
        guard isDown else { return }
        isDown = false
        if comboUsed {
            pendingTapTime = nil
            return
        }
        registerTap()
    }

    public func otherKeyDown() {
        if isDown {
            comboUsed = true
        } else {
            pendingTapTime = nil
        }
    }

    private func registerTap() {
        let time = now()
        switch mode {
        case .singleTap:
            pendingTapTime = nil
            onActivate?()
        case .doubleTap:
            if let pending = pendingTapTime, time - pending <= doubleTapWindow {
                pendingTapTime = nil
                onActivate?()
            } else {
                pendingTapTime = time
            }
        }
    }
}
