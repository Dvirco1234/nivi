import Foundation

/// Decides when a main thread that has stopped answering is worth a warning, and when it is
/// bad enough that the app should stop itself.
///
/// This is the judgement behind `MainThreadWatchdog`, kept here so it can be tested without
/// a running app. The watchdog owns the timer and the logging; this owns the rule.
///
/// ## Why the rule is not simply "how long since the last answer"
///
/// That is what it used to be, measured with `Date()`, and it was wrong twice in September
/// 2026. `Date()` is wall-clock time, and a sleeping Mac freezes the process while the wall
/// clock keeps going. On the first tick after waking, a perfectly healthy app looked like it
/// had been stuck for the whole sleep, and it quit itself:
///
///     2026-09-09T15:20:14Z ERROR Main thread has been stuck for 946s. Quitting
///     pmset: 2026-09-09 18:20:15 +0300 DarkWake from Deep Idle
///
/// Those two lines are the same second. The app was not stuck. The Mac had been asleep for
/// about sixteen minutes, which is one of its normal sleep cycles. Nothing in the log ever
/// showed the five-second warning that a real stall would have produced first.
///
/// So there are two guards now, and both have to agree before the app stops itself:
///
/// 1. **A clock that stops when the Mac does.** The caller passes
///    `ProcessInfo.processInfo.systemUptime`, which counts time awake, so sleep adds nothing.
/// 2. **Ticks actually watched.** Quitting needs the watch to have run often enough to have
///    seen the silence for itself. A process that was frozen for other reasons, so that its
///    own timer never fired, comes back with one late tick and one late tick is not evidence.
///
/// Guard 1 alone would cover sleep. Guard 2 covers anything else that stops a background app
/// from running, which is a long list on macOS and not worth enumerating. Neither guard can
/// hide a real stall, because a real stall means the app is running, its timer is firing and
/// the awake clock is moving.
public struct StallWatch {
    /// What the watchdog should do about the reading it just took.
    public enum Verdict: Equatable {
        /// Either all is well, or the stall has already been written to the log once.
        case nothingToReport
        case warn(seconds: Int)
        case quit(seconds: Int)
    }

    private let tickEvery: TimeInterval
    private let warnAfter: TimeInterval
    private let quitAfter: TimeInterval
    /// How many readings the watch has to take before it is allowed to quit the app, so the
    /// silence is something it watched rather than something it inferred from one number.
    private let ticksNeededToQuit: Int

    private var lastAnswer: TimeInterval = 0
    private var ticksWatched = 0
    private var hasWarned = false

    public init(tickEvery: TimeInterval, warnAfter: TimeInterval, quitAfter: TimeInterval) {
        self.tickEvery = tickEvery
        self.warnAfter = warnAfter
        self.quitAfter = quitAfter
        self.ticksNeededToQuit = max(1, Int((quitAfter / tickEvery).rounded()))
    }

    /// The main thread came back. Whatever silence there was is over.
    public mutating func mainThreadAnswered(at now: TimeInterval) {
        lastAnswer = now
        ticksWatched = 0
        hasWarned = false
    }

    /// One reading, taken once every `tickEvery` on the clock that stops during sleep.
    public mutating func tick(at now: TimeInterval) -> Verdict {
        ticksWatched += 1
        let silence = max(0, now - lastAnswer)

        if silence >= quitAfter && ticksWatched >= ticksNeededToQuit {
            return .quit(seconds: Int(silence))
        }
        if silence >= warnAfter && !hasWarned {
            hasWarned = true
            return .warn(seconds: Int(silence))
        }
        return .nothingToReport
    }
}
