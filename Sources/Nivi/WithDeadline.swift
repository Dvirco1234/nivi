import Foundation

/// Runs blocking work on a background queue and gives up on it after `seconds`.
///
/// This exists for CoreAudio. Its calls go through the system audio daemon, and when that
/// daemon is unhealthy they can block with no upper bound at all — one of them once hung
/// Nivi forever. Giving up is the whole point: the stuck call is left to finish on its own
/// queue whenever it feels like it, the caller gets `ifLate` back instead, and the app
/// stays usable.
///
/// The work is not cancelled, because a blocked Mach call cannot be cancelled. A late
/// result is simply thrown away, so `work` must be safe to leave running.
func withDeadline<T>(_ seconds: TimeInterval,
                     on queue: DispatchQueue,
                     ifLate lateError: Error,
                     _ work: @escaping () throws -> T) async throws -> T {
    let firstAnswer = FirstAnswer<T>()
    return try await withCheckedThrowingContinuation { continuation in
        firstAnswer.waitingCaller = continuation
        queue.async {
            do { firstAnswer.deliver(.success(try work())) }
            catch { firstAnswer.deliver(.failure(error)) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            firstAnswer.deliver(.failure(lateError))
        }
    }
}

/// Lets exactly one of two racing answers reach the caller. Resuming a continuation twice
/// is a crash, so the winner is picked under a lock.
private final class FirstAnswer<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var answered = false
    /// Assigned before either racer can run, so it is never read before it is set.
    var waitingCaller: CheckedContinuation<T, Error>?

    func deliver(_ result: Result<T, Error>) {
        lock.lock()
        let won = !answered
        answered = true
        let caller = waitingCaller
        if won { waitingCaller = nil }
        lock.unlock()
        guard won, let caller else { return }
        caller.resume(with: result)
    }
}
