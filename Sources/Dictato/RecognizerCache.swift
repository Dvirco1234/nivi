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

    func setCapacity(_ n: Int) {
        capacity = max(1, n)
        evictIfNeeded()
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
        evictIfNeeded()
        return recognizer
    }

    func evictAll() {
        for (_, r) in loaded { r.unload() }
        loaded.removeAll()
        order.removeAll()
    }

    private func touch(_ id: String) {
        order.removeAll { $0 == id }
        order.append(id)
    }

    private func evictIfNeeded() {
        while order.count > capacity {
            let victim = order.removeFirst()
            loaded[victim]?.unload()
            loaded[victim] = nil
            Log.info("Recognizer evicted from cache: \(victim)")
        }
    }
}
