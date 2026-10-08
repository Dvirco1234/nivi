import AVFoundation
import AudioToolbox
import CoreAudio

enum AudioRecorderError: LocalizedError {
    case noInputDevice
    case audioSystemTimedOut(TimeInterval)
    /// Thrown by a start that finally got its answer from CoreAudio long after the caller
    /// stopped waiting. Nobody is listening for it; it only stops the work going further.
    case abandonedWhileStarting

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No audio input device available"
        case .audioSystemTimedOut(let seconds):
            return "The audio system did not answer within \(Int(seconds)) seconds"
        case .abandonedWhileStarting:
            return "The recording was given up on before the audio system answered"
        }
    }
}

/// An `AVAudioEngine` and the serial queue that owns it, together, so that both can be
/// thrown away as a unit.
///
/// They have to be thrown away together because of how a stuck CoreAudio call behaves. The
/// call blocks on a queue, and a blocked Mach call cannot be cancelled, so that queue is
/// occupied until the audio daemon decides to answer. If the queue is the only one the
/// recorder has, everything the user does next lands behind a call that is going nowhere.
/// That is exactly what happened on 14 September 2026: one start blocked for 27 minutes,
/// and the five recordings the user tried in the meantime never ran at all. Each waited its
/// eight seconds behind the stuck one and reported a timeout it had done nothing to earn.
/// The app's own log shows them all completing at once when the daemon finally replied:
///
///     Recording input: ... (audio start took 1658094 ms)
///     Recording input: ... (audio start took 3 ms)
///     Recording input: ... (audio start took 2 ms)
///
/// Replacing the session gives the next recording a queue of its own, so a wedged audio
/// daemon costs one dictation instead of every dictation until it recovers.
private final class MicrophoneSession {
    let queue: DispatchQueue
    var engine: AVAudioEngine?
    /// The microphone the user asked for when this engine was built, or nil if they have
    /// no preference. If the answer changes, the engine has to be rebuilt.
    var wantedDevice: AudioDeviceID?
    /// The system's default input when this engine was built, for the same reason.
    var systemDefault: AudioDeviceID?
    var idleTeardown: DispatchWorkItem?

    /// Read from the session's own queue and written from whichever thread gave up on it,
    /// so it needs a lock of its own rather than the queue it is about to stop trusting.
    private let retirementLock = NSLock()
    private var retired = false

    var isRetired: Bool {
        retirementLock.lock()
        defer { retirementLock.unlock() }
        return retired
    }

    func retire() {
        retirementLock.lock()
        retired = true
        retirementLock.unlock()
    }

    init(number: Int) {
        queue = DispatchQueue(label: "com.dvir.nivi.audio-engine.\(number)", qos: .userInitiated)
    }
}

/// Records microphone input and accumulates 16 kHz mono Float32 samples in memory.
///
/// Everything that talks to AVAudioEngine or CoreAudio runs on the current session's queue,
/// never on the main thread. These calls go through the system audio daemon, so they can
/// block for a long time. Once, on a Mac whose audio daemon had got into a bad state,
/// one of them never came back at all and took the whole app with it. Starting is therefore
/// also given a deadline: see `startTimeout`. When that deadline passes the session is
/// retired and a fresh one takes its place; `MicrophoneSession` explains why.
final class AudioRecorder {
    static let sampleRate = 16_000.0

    /// How long the audio hardware gets to hand back a working input node before the
    /// recording is failed. Normal start-up is tens of milliseconds; the first one after
    /// launch can take a few seconds while CoreAudio wakes up.
    static let startTimeout: TimeInterval = 8

    /// How long an unused engine is kept alive. Keeping it means the next recording starts
    /// without rebuilding CoreAudio's private aggregate device. Dropping it eventually
    /// means an idle Nivi leaves no extra device sitting in everyone else's device list.
    private static let idleTeardownDelay: TimeInterval = 90

    var onLevel: ((Float) -> Void)?

    // MARK: - State
    //
    // Everything inside a session is only ever read or written on that session's own queue,
    // apart from its retirement flag, which has its own lock. `samples` and `isCapturing`
    // are only ever touched under `samplesQueue`, because the audio tap appends from a
    // real-time thread.

    /// Guards the swap in `retire(_:because:)` only. The session's contents are still the
    /// session queue's business.
    private let sessionLock = NSLock()
    private var session = MicrophoneSession(number: 1)
    private var sessionsMade = 1

    private var samples: [Float] = []
    private var isCapturing = false

    private let samplesQueue = DispatchQueue(label: "com.dvir.nivi.audio")

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

    init() {
        // The route changed: headphones went in, a device was unplugged, the daemon
        // restarted. The engine is now pointed at hardware that may not exist, so throw it
        // away rather than record silence from it.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            let session = self.currentSession()
            session.queue.async {
                guard !self.capturing else { return }   // never pull the rug out mid-recording
                self.discardEngine(in: session, because: "the audio route changed")
            }
        }
    }

    private func currentSession() -> MicrophoneSession {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return session
    }

    // MARK: - Recording

    /// Opens the microphone. Runs entirely off the main thread and gives up after
    /// `startTimeout`, so a wedged audio daemon fails one recording instead of the app.
    ///
    /// Giving up also retires the session, because the call it gave up on still owns that
    /// session's queue and may hold it for many minutes. Without this the next recording
    /// would queue behind it and fail too, and so would every one after that.
    func start() async throws {
        samplesQueue.sync {
            samples.removeAll()
            isCapturing = false
        }
        let session = currentSession()
        do {
            try await withDeadline(Self.startTimeout,
                                   on: session.queue,
                                   ifLate: AudioRecorderError.audioSystemTimedOut(Self.startTimeout)) {
                [weak self] in
                guard let self else { throw AudioRecorderError.noInputDevice }
                try self.startOnSessionQueue(session)
            }
        } catch let error as AudioRecorderError {
            if case .audioSystemTimedOut(let seconds) = error {
                retire(session, because: "it did not answer within \(Int(seconds)) seconds")
            }
            throw error
        }
    }

    /// Gives up on a session for good and puts a fresh one in its place.
    ///
    /// The stuck call is left to finish on the old queue whenever the audio daemon lets it.
    /// The teardown queued here runs behind it and closes whatever it opened. It cannot run
    /// any sooner, and that is the whole reason the session had to be replaced rather than
    /// repaired.
    private func retire(_ stuck: MicrophoneSession, because reason: String) {
        sessionLock.lock()
        guard session === stuck else {       // something already replaced it
            sessionLock.unlock()
            return
        }
        stuck.retire()
        sessionsMade += 1
        session = MicrophoneSession(number: sessionsMade)
        sessionLock.unlock()

        Log.error("Audio engine abandoned: \(reason). The next recording builds a new one.")

        stuck.queue.async {
            guard let engine = stuck.engine else { return }
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            stuck.engine = nil
        }
    }

    /// Ends the recording and hands over everything it captured.
    ///
    /// The recorder lets go of the buffer as it hands it over. Keeping a second copy
    /// until the next recording starts would hold the whole dictation in memory for as
    /// long as the app is idle, which is about 4 MB a minute of speech for no reason.
    ///
    /// Stopping the hardware is left to the session queue, so this returns straight away even
    /// when CoreAudio is being slow.
    func stop() -> [Float] {
        let recorded = samplesQueue.sync { () -> [Float] in
            isCapturing = false
            let recorded = samples
            samples = []
            return recorded
        }
        stopHardwareInTheBackground()
        return recorded
    }

    /// A snapshot of everything recorded so far. Recording continues; the streaming
    /// loop re-transcribes this growing buffer. Taken under `samplesQueue` because
    /// the audio tap appends to `samples` from a real-time thread.
    func currentSamples() -> [Float] {
        samplesQueue.sync { samples }
    }

    func cancel() {
        samplesQueue.sync {
            isCapturing = false
            samples.removeAll()
        }
        stopHardwareInTheBackground()
    }

    // MARK: - The engine (the session's own queue only)

    private func startOnSessionQueue(_ session: MicrophoneSession) throws {
        dispatchPrecondition(condition: .onQueue(session.queue))
        session.idleTeardown?.cancel()
        session.idleTeardown = nil

        let started = Date()
        // Any of the next few calls can block for as long as the audio daemon wants. That
        // is why `start()` puts a deadline on this whole function.
        let engine = readyEngine(in: session)
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)

        // Asked again here because the calls above may have taken minutes, and the caller
        // gave up after eight seconds and told the user the recording failed. Opening the
        // microphone now would record with nobody listening and nothing left to stop it.
        guard !session.isRetired else { throw AudioRecorderError.abandonedWhileStarting }

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            discardEngine(in: session, because: "the input node reported no usable format")
            throw AudioRecorderError.noInputDevice
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            discardEngine(in: session, because: "the input format cannot be converted to 16 kHz mono")
            throw AudioRecorderError.noInputDevice
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer, with: converter)
        }
        samplesQueue.sync { isCapturing = true }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            samplesQueue.sync { isCapturing = false }
            discardEngine(in: session, because: "the engine would not start")
            throw error
        }
        Log.info("Recording input: \(Int(inputFormat.sampleRate)) Hz, \(inputFormat.channelCount) ch"
                 + " (audio start took \(Int(Date().timeIntervalSince(started) * 1000)) ms)")
    }

    /// The engine to record with, reusing the last one when it is still pointed at the
    /// right microphone.
    ///
    /// Building an engine is not free. The first time anything asks an `AVAudioEngine` for
    /// its input node on macOS, CoreAudio builds a private aggregate device behind the
    /// scenes, and tears it down again when the engine goes away. The app used to do that
    /// once per recording — hundreds of times a day — which is a lot of churn to put
    /// through the audio daemon for no gain. Reuse is safe as long as the engine is thrown
    /// away whenever the answer to "which microphone" changes, which is what the two
    /// stored device ids and the route-change notification are for.
    private func readyEngine(in session: MicrophoneSession) -> AVAudioEngine {
        dispatchPrecondition(condition: .onQueue(session.queue))
        let wanted = MicrophoneDevices.preferred()
        let systemDefault = MicrophoneDevices.systemDefault()?.audioDeviceID

        if let engine = session.engine, wanted?.audioDeviceID == session.wantedDevice,
           systemDefault == session.systemDefault {
            return engine
        }
        discardEngine(in: session, because: "the microphone to record from changed")

        let engine = AVAudioEngine()
        session.engine = engine
        session.wantedDevice = wanted?.audioDeviceID
        session.systemDefault = systemDefault
        // Pick the microphone before asking the node anything about its format: the format
        // belongs to whichever device the node is bound to, and the binding cannot be
        // changed once the engine is running.
        if let wanted { bindMicrophone(wanted, on: engine.inputNode) }
        return engine
    }

    /// Points a freshly built engine at one specific microphone.
    ///
    /// This is best effort on purpose. It only runs when the user actually filled in a
    /// microphone priority list, only on an engine that has not started yet, and a failure
    /// is logged and ignored: recording with the wrong microphone is much better than not
    /// recording at all. `setDeviceID` is the supported macOS spelling of
    /// `kAudioOutputUnitProperty_CurrentDevice`; the app used to set that property by hand
    /// on every single recording, and CoreAudio answered
    /// `kAudioHardwareIllegalOperationError` often enough to fill the log.
    private func bindMicrophone(_ device: MicrophoneDevice, on input: AVAudioInputNode) {
        let unit = input.auAudioUnit
        guard unit.deviceID != AUAudioObjectID(device.audioDeviceID) else { return }
        do {
            try unit.setDeviceID(AUAudioObjectID(device.audioDeviceID))
            Log.info("Recording from \(device.name)")
        } catch {
            Log.error("Could not select \(device.name) (\(error.localizedDescription)),"
                      + " keeping the system microphone")
        }
    }

    private func stopHardwareInTheBackground() {
        let session = currentSession()
        session.queue.async { [weak self] in
            guard let self, let engine = session.engine else { return }
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.scheduleIdleTeardown(in: session)
        }
    }

    private func scheduleIdleTeardown(in session: MicrophoneSession) {
        dispatchPrecondition(condition: .onQueue(session.queue))
        session.idleTeardown?.cancel()
        // `session` is held weakly on purpose. The session owns this work item, so holding
        // it back would be a cycle, and a retired session would keep its engine alive for
        // the life of the app. A session nobody else wants can go; its engine goes with it.
        let work = DispatchWorkItem { [weak self, weak session] in
            guard let session else { return }
            self?.discardEngine(in: session, because: "nothing has been recorded for a while")
        }
        session.idleTeardown = work
        session.queue.asyncAfter(deadline: .now() + Self.idleTeardownDelay, execute: work)
    }

    private func discardEngine(in session: MicrophoneSession, because reason: String) {
        dispatchPrecondition(condition: .onQueue(session.queue))
        guard let engine = session.engine else { return }
        Log.debug("Dropping the audio engine: \(reason)")
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        session.engine = nil
        session.wantedDevice = nil
        session.systemDefault = nil
    }

    private var capturing: Bool { samplesQueue.sync { isCapturing } }

    // MARK: - The audio tap

    private func process(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) {
        // The engine can deliver a buffer or two after stop() returned. Those belong to a
        // recording that has already been handed over, so drop them.
        guard capturing else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = out.floatChannelData, out.frameLength > 0 else { return }

        let chunk = Array(UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength)))
        samplesQueue.sync {
            guard isCapturing else { return }
            samples.append(contentsOf: chunk)
        }

        let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
        // Perceptual boost: sqrt curve + high gain so normal speech swings the bars.
        let level = min(1.0, sqrt(rms) * 3.2)
        DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
    }
}
