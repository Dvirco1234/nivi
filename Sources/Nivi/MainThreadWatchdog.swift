import AppKit
import Foundation

/// Notices when the main thread has stopped running, and makes sure the user is never left
/// with an app they cannot close.
///
/// Nivi normally runs with no Dock icon, and macOS leaves apps like that out of the Force
/// Quit window. So a main thread that stops answering is worse than a frozen app: the menu
/// bar icon is still there, it just does nothing, and there is no button anywhere that
/// ends it. That happened once, caused by a CoreAudio call that never came back.
///
/// A background timer pings the main queue once a second and checks how long ago the last
/// ping came back. Two stages:
///
/// 1. After `warnAfter`, write one line to the log. Most stalls are short and this is all
///    that is needed to recognise one later.
/// 2. After `quitAfter`, stop the process. Losing an app that is doing nothing anyway is
///    much better than a menu bar icon the user cannot get rid of, and everything Nivi
///    keeps is already on disk. The one thing a normal quit does — putting the output
///    volume back — is deliberately not attempted here, because it is itself a CoreAudio
///    call and CoreAudio is the usual suspect. `SystemVolume.restoreAfterCrash()` puts the
///    volume back on the next launch instead.
enum MainThreadWatchdog {
    /// Long enough that a slow menu build or a big SwiftUI redraw never trips it.
    static let warnAfter: TimeInterval = 5
    /// Long enough that nothing legitimate reaches it. Transcription, model loading and
    /// audio all run on their own queues, so the main thread is never busy for this long.
    static let quitAfter: TimeInterval = 45

    private static let queue = DispatchQueue(label: "com.dvir.nivi.watchdog")
    private static let lock = NSLock()
    private static var lastAnswerFromMainThread = Date()
    private static var alreadyWarned = false
    private static var timer: DispatchSourceTimer?

    static func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { check() }
        self.timer = timer
        timer.resume()
    }

    private static func check() {
        DispatchQueue.main.async {
            lock.lock()
            lastAnswerFromMainThread = Date()
            alreadyWarned = false
            lock.unlock()
        }

        lock.lock()
        let stalledFor = Date().timeIntervalSince(lastAnswerFromMainThread)
        let shouldWarn = stalledFor >= warnAfter && !alreadyWarned
        if shouldWarn { alreadyWarned = true }
        lock.unlock()

        if stalledFor >= quitAfter {
            Log.error("Main thread has been stuck for \(Int(stalledFor))s. Quitting: the app "
                      + "cannot be used or closed in this state. Start it again from Spotlight.")
            // Let the log write finish. Log.write is async on its own queue, and this
            // process is about to stop existing.
            Thread.sleep(forTimeInterval: 0.5)
            exit(70)
        }
        if shouldWarn {
            Log.error("Main thread has not answered for \(Int(stalledFor))s — the menu bar "
                      + "will not respond until it does.")
        }
    }
}
