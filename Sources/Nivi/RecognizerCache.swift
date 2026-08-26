import Foundation

/// LRU cache of loaded recognizers keyed by model id. Loads on miss, evicts the
/// least-recently-used past capacity. Serialized via an actor.
actor RecognizerCache {
    private var capacity: Int
    private var order: [String] = []                    // most-recent last
    private var loaded: [String: SpeechRecognizer] = [:]

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func setCapacity(_ n: Int) async {
        capacity = max(1, n)
        await evictIfNeeded()
    }

    func recognizer(id: String, modelPath: URL) async throws -> SpeechRecognizer {
        if let existing = loaded[id] {
            touch(id)
            return existing
        }
        let recognizer = WhisperCppRecognizer(modelPath: modelPath)
        try await recognizer.load()
        loaded[id] = recognizer
        order.append(id)
        Log.info("Recognizer loaded into cache: \(id)")
        await evictIfNeeded()
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

    private func touch(_ id: String) {
        order.removeAll { $0 == id }
        order.append(id)
    }

    private func evictIfNeeded() async {
        while order.count > capacity {
            let victim = order.removeFirst()
            let recognizer = loaded.removeValue(forKey: victim)
            await recognizer?.unload()
            Log.info("Recognizer evicted from cache: \(victim)")
        }
    }
}
