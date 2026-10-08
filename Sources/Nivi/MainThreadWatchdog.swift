import AppKit
import Foundation
import NiviCore

/// Notices when the main thread has stopped running, and makes sure the user is never left
/// with an app they cannot close.
///
/// Nivi normally runs with no Dock icon, and macOS leaves apps like that out of the Force
/// Quit window. So a main thread that stops answering is worse than a frozen app: the menu
/// bar icon is still there, it just does nothing, and there is no button anywhere that
/// ends it. That happened once, caused by a CoreAudio call that never came back.
///
/// A background timer pings the main queue once a second and asks `StallWatch` what to make
/// of the answer, or the lack of one. Two stages:
///
/// 1. After `warnAfter`, write one line to the log. Most stalls are short and this is all
///    that is needed to recognise one later.
/// 2. After `quitAfter`, stop the process. Losing an app that is doing nothing anyway is
///    much better than a menu bar icon the user cannot get rid of, and everything Nivi
///    keeps is already on disk. The one thing a normal quit does — putting the output
///    volume back — is deliberately not attempted here, because it is itself a CoreAudio
///    call and CoreAudio is the usual suspect. `SystemVolume.restoreAfterCrash()` puts the
///    volume back on the next launch instead.
///
/// The clock is `ProcessInfo.processInfo.systemUptime`, which counts time the Mac has been
/// awake and stops while it sleeps. Using the wall clock here made the app quit itself every
/// time the lid was closed for longer than `quitAfter`. `StallWatch` carries the full story
/// and the rule that now prevents it.
enum MainThreadWatchdog {
    /// Long enough that a slow menu build or a big SwiftUI redraw never trips it.
    static let warnAfter: TimeInterval = 5
    /// Long enough that nothing legitimate reaches it. Transcription, model loading and
    /// audio all run on their own queues, so the main thread is never busy for this long.
    static let quitAfter: TimeInterval = 45
    private static let tickEvery: TimeInterval = 1

    private static let queue = DispatchQueue(label: "com.dvir.nivi.watchdog")
    private static let lock = NSLock()
    private static var watch = StallWatch(
        tickEvery: tickEvery, warnAfter: warnAfter, quitAfter: quitAfter)
    private static var timer: DispatchSourceTimer?

    /// Time the Mac has been awake. Deliberately not `Date()`: see the note on the type.
    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    static func start() {
        lock.lock()
        watch.mainThreadAnswered(at: now)
        lock.unlock()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + tickEvery, repeating: tickEvery)
        timer.setEventHandler { check() }
        self.timer = timer
        timer.resume()
    }

    private static func check() {
        DispatchQueue.main.async {
            lock.lock()
            watch.mainThreadAnswered(at: now)
            lock.unlock()
        }

        lock.lock()
        let verdict = watch.tick(at: now)
        lock.unlock()

        switch verdict {
        case .nothingToReport:
            break
        case .warn(let seconds):
            Log.error("Main thread has not answered for \(seconds)s — the menu bar "
                      + "will not respond until it does.")
        case .quit(let seconds):
            Log.error("Main thread has been stuck for \(seconds)s. Quitting: the app "
                      + "cannot be used or closed in this state. Start it again from Spotlight.")
            // Let the log write finish. Log.write is async on its own queue, and this
            // process is about to stop existing.
            Thread.sleep(forTimeInterval: 0.5)
            exit(70)
        }
    }
}
