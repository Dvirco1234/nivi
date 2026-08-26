import Foundation
import DictatoCore

/// Transcribes a file the user dropped, without touching dictation.
///
/// It never opens the microphone and never speaks to `DictationController` or the
/// dictation state machine, the same shape `ModelTester` already proved. The one thing it
/// shares is `RecognizerCache`, so using the model the user already dictates with costs no
/// extra memory. That cache is an actor, so a long piece in flight would make a dictation
/// wait, which is why the job checks `isDictationBusy` between pieces and stands aside.
/// Dictation always wins.
@MainActor
final class FileTranscriptionService: ObservableObject {

    enum Phase: Equatable {
        case idle
        case decoding(Double)
        /// Pieces finished, out of how many.
        case transcribing(done: Int, of: Int)
        /// Waiting for a dictation to finish before starting the next piece.
        case waitingForDictation
        case finished
        /// Something stopped the job before it could run. The title says which kind of
        /// problem it was, so the banner does not blame the file for a busy microphone.
        case failed(title: String, message: String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript = ""
    /// True when the user stopped the job, so the text is only part of the file.
    @Published private(set) var stoppedEarly = false
    @Published private(set) var fileName = ""
    @Published private(set) var audioSeconds: Double = 0
    @Published private(set) var workSeconds: Double = 0
    @Published private(set) var modelName = ""
    @Published private(set) var progressLine = ""

    /// Which model and language the next job runs with.
    ///
    /// Kept here rather than in the view because SwiftUI throws view state away more
    /// readily than it looks: after the file chooser closed, a `@State` choice was back at
    /// its default. The service outlives the window, so the choice sticks.
    @Published var modelID = ""
    @Published var language = "auto"

    /// Set by the controller, so a file job can never push in front of a real dictation.
    var isDictationBusy: () -> Bool = { false }

    private let cache: RecognizerCache
    private let modelStore: ModelStore
    private let history: HistoryStore
    private var job: Task<Void, Never>?
    /// Read from the decode loop on a background thread, so it lives in a box of its own
    /// rather than being read across the actor boundary.
    private let cancelFlag = CancelFlag()

    init(cache: RecognizerCache, modelStore: ModelStore, history: HistoryStore = .shared) {
        self.cache = cache
        self.modelStore = modelStore
        self.history = history
    }

    var isRunning: Bool {
        switch phase {
        case .decoding, .transcribing, .waitingForDictation: return true
        case .idle, .finished, .failed: return false
        }
    }

    // MARK: - Running a job

    func start(url: URL, model: ManagedModel, language: String, chunkMinutes: Int) {
        guard !isRunning else { return }
        guard !isDictationBusy() else {
            phase = .failed(title: "Dictation comes first",
                            message: "Finish the recording that is running, then start the file.")
            return
        }
        guard TranscribableFormat.isSupported(fileExtension: url.pathExtension) else {
            let name = url.pathExtension.uppercased()
            phase = .failed(
                title: "Dictato cannot read this file",
                message: TranscribableFormat.isKnownUnsupported(fileExtension: url.pathExtension)
                    ? "\(name) files are not supported. Convert the file to MP3 or WAV and try again."
                    : "\(name) files are not supported.")
            return
        }
        guard modelStore.isInstalled(model.id) else {
            phase = .failed(title: "That model is not on this Mac yet",
                            message: "Download \(model.displayName) in Dictation models first.")
            return
        }

        transcript = ""
        stoppedEarly = false
        workSeconds = 0
        audioSeconds = 0
        progressLine = ""
        fileName = url.lastPathComponent
        modelName = model.displayName
        cancelFlag.reset()
        phase = .decoding(0)

        let modelPath = modelStore.installedURL(for: model)
        job = Task { [weak self] in
            await self?.run(url: url, modelID: model.id, modelPath: modelPath,
                            language: language, chunkMinutes: chunkMinutes)
        }
    }

    /// Stops the work, not just the progress bar. The decode loop and the piece loop both
    /// watch this, and whatever text is finished so far is kept and marked as partial.
    func cancel() {
        guard isRunning else { return }
        cancelFlag.cancel()
        job?.cancel()
    }

    func clearResult() {
        guard !isRunning else { return }
        transcript = ""
        stoppedEarly = false
        fileName = ""
        phase = .idle
    }

    // MARK: - The job itself

    private func run(url: URL, modelID: String, modelPath: URL,
                     language: String, chunkMinutes: Int) async {
        let startedAt = Date()
        do {
            let samples = try await decode(url: url)
            guard !cancelFlag.isCancelled else { return finishStopped(startedAt: startedAt) }

            audioSeconds = Double(samples.count) / Double(AudioFileDecoder.sampleRate)
            let recognizer = try await cache.recognizer(id: modelID, modelPath: modelPath)

            // Cut on the quietest moment near each boundary, so a piece rarely ends
            // mid-word.
            let cuts = AudioChunkPlanner.cutPoints(samples: samples,
                                                   sampleRate: AudioFileDecoder.sampleRate,
                                                   chunkSeconds: chunkMinutes * 60)
            let ranges = chunkRanges(cuts: cuts, sampleCount: samples.count)
            var pieces: [String] = []

            for (index, range) in ranges.enumerated() {
                guard !cancelFlag.isCancelled else { break }
                await waitForDictationToFinish()
                guard !cancelFlag.isCancelled else { break }

                phase = .transcribing(done: index, of: ranges.count)
                progressLine = ChunkedTranscription.progressLine(
                    chunksDone: index, chunkCount: ranges.count,
                    elapsedSeconds: Date().timeIntervalSince(startedAt))

                let piece = try await recognizer.transcribe(samples: Array(samples[range]),
                                                            language: language)
                pieces.append(TranscriptCleaning.clean(
                    piece, removeSoundDescriptions: Settings().removeSoundDescriptions))
                transcript = ChunkedTranscription.join(pieces)
            }

            workSeconds = Date().timeIntervalSince(startedAt)
            if cancelFlag.isCancelled {
                finishStopped(startedAt: startedAt)
                return
            }
            phase = .finished
            progressLine = ""
            saveToHistory(modelID: modelID, language: language)
            Log.info("File transcribed: \(fileName), \(ranges.count) part(s), \(Int(workSeconds))s")
        } catch is CancellationError {
            finishStopped(startedAt: startedAt)
        } catch AudioFileDecodingError.cancelled {
            finishStopped(startedAt: startedAt)
        } catch {
            Log.error("File transcription failed: \(error.localizedDescription)")
            phase = .failed(title: "Dictato cannot read this file",
                            message: error.localizedDescription)
        }
    }

    private func decode(url: URL) async throws -> [Float] {
        let flag = cancelFlag
        return try await Task.detached(priority: .userInitiated) {
            try await AudioFileDecoder.decode(
                url: url,
                onProgress: { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, case .decoding = self.phase else { return }
                        self.phase = .decoding(fraction)
                    }
                },
                isCancelled: { flag.isCancelled })
        }.value
    }

    /// Waits, in quarter seconds, while a dictation is running.
    private func waitForDictationToFinish() async {
        guard isDictationBusy() else { return }
        phase = .waitingForDictation
        progressLine = "Waiting for your dictation to finish."
        while isDictationBusy(), !cancelFlag.isCancelled {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private func finishStopped(startedAt: Date) {
        workSeconds = Date().timeIntervalSince(startedAt)
        stoppedEarly = true
        progressLine = ""
        phase = transcript.isEmpty ? .idle : .finished
        if !transcript.isEmpty {
            // Half a file is still worth keeping, and it is marked as partial on screen.
            Log.info("File transcription stopped early: \(fileName)")
        }
    }

    private func saveToHistory(modelID: String, language: String) {
        history.record(text: transcript,
                       durationSeconds: audioSeconds,
                       source: .file,
                       modelID: modelID,
                       language: language,
                       sourceName: fileName)
    }

    /// Turns cut positions into the ranges to transcribe.
    private func chunkRanges(cuts: [Int], sampleCount: Int) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = 0
        for cut in cuts where cut > start && cut < sampleCount {
            ranges.append(start..<cut)
            start = cut
        }
        ranges.append(start..<sampleCount)
        return ranges
    }
}

/// A cancel flag two threads can share. `Task.isCancelled` is not enough here, because the
/// decode loop runs on a detached task and the piece loop needs the same answer.
private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return flag
    }

    func cancel() {
        lock.lock(); flag = true; lock.unlock()
    }

    func reset() {
        lock.lock(); flag = false; lock.unlock()
    }
}
