import Foundation
import NiviCore

/// LRU cache of loaded recognizers keyed by model id. Loads on miss, evicts the
/// least-recently-used past capacity. Serialized via an actor.
actor RecognizerCache {
    private var capacity: Int
    private var order = RecentlyUsedOrder()
    private var loaded: [String: SpeechRecognizer] = [:]
    /// Loads still running, one per model id. An actor lets a second caller in while the
    /// first waits for its load, and both used to load the same model. Recording start and
    /// stop often ask for a cold model at the same moment, so a second caller now waits on
    /// the first caller's load instead of starting its own.
    private var loading: [String: Task<SpeechRecognizer, Error>] = [:]

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func setCapacity(_ n: Int) async {
        capacity = max(1, n)
        await unload(order.trim(to: capacity))
    }

    func recognizer(id: String, modelPath: URL) async throws -> SpeechRecognizer {
        if let existing = loaded[id] {
            order.touch(id)
            return existing
        }
        if let inFlight = loading[id] {
            return try await inFlight.value
        }
        let load = Task { () throws -> SpeechRecognizer in
            let recognizer = WhisperCppRecognizer(modelPath: modelPath)
            try await recognizer.load()
            return recognizer
        }
        loading[id] = load
        let recognizer: SpeechRecognizer
        do {
            recognizer = try await load.value
        } catch {
            loading[id] = nil
            throw error
        }
        loading[id] = nil
        loaded[id] = recognizer
        Log.info("Recognizer loaded into cache: \(id)")
        await unload(order.insert(id, capacity: capacity))
        return recognizer
    }

    func evictAll() async {
        // Drop them from the cache before awaiting the frees, so a concurrent
        // `recognizer(id:)` loads a fresh one instead of handing out a dying context.
        let victims = Array(loaded.values)
        loaded.removeAll()
        order.removeAll()
        for recognizer in victims { await recognizer.unload() }
    }

    private func unload(_ ids: [String]) async {
        // Every id leaves `loaded` before the first await, for the same reason as in
        // `evictAll`: nobody may be handed a model that is being freed.
        let victims = ids.compactMap { id in loaded.removeValue(forKey: id).map { (id, $0) } }
        for (id, recognizer) in victims {
            await recognizer.unload()
            Log.info("Recognizer evicted from cache: \(id)")
        }
    }
}
