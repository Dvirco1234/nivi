import AVFoundation
import AudioToolbox
import CoreAudio

enum AudioRecorderError: LocalizedError {
    case noInputDevice
    case audioSystemTimedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No audio input device available"
        case .audioSystemTimedOut(let seconds):
            return "The audio system did not answer within \(Int(seconds)) seconds"
        }
    }
}

/// Records microphone input and accumulates 16 kHz mono Float32 samples in memory.
///
/// Everything that talks to AVAudioEngine or CoreAudio runs on `engineQueue`, never on the
/// main thread. These calls go through the system audio daemon, so they can block for a
/// long time — and once, on a Mac whose audio daemon had got into a bad state, one of them
/// never came back at all and took the whole app with it. Starting is therefore also given
/// a deadline: see `startTimeout`.
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
    // `engine` and the two "what was this engine built for" values are only ever read or
    // written on `engineQueue`. `samples` and `isCapturing` are only ever touched under
    // `samplesQueue`, because the audio tap appends from a real-time thread.

    private var engine: AVAudioEngine?
    /// The microphone the user asked for when this engine was built, or nil if they have
    /// no preference. If the answer changes, the engine has to be rebuilt.
    private var engineWantedDevice: AudioDeviceID?
    /// The system's default input when this engine was built, for the same reason.
    private var engineSystemDefault: AudioDeviceID?
    private var idleTeardown: DispatchWorkItem?

    private var samples: [Float] = []
    private var isCapturing = false

    private let samplesQueue = DispatchQueue(label: "com.dvir.nivi.audio")
    private let engineQueue = DispatchQueue(label: "com.dvir.nivi.audio-engine", qos: .userInitiated)

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

    init() {
        // The route changed: headphones went in, a device was unplugged, the daemon
        // restarted. The engine is now pointed at hardware that may not exist, so throw it
        // away rather than record silence from it.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.engineQueue.async {
                guard !self.capturing else { return }   // never pull the rug out mid-recording
                self.discardEngine(because: "the audio route changed")
            }
        }
    }

    // MARK: - Recording

    /// Opens the microphone. Runs entirely off the main thread and gives up after
    /// `startTimeout`, so a wedged audio daemon fails one recording instead of the app.
    func start() async throws {
        samplesQueue.sync {
            samples.removeAll()
            isCapturing = false
        }
        try await withDeadline(Self.startTimeout,
                               on: engineQueue,
                               ifLate: AudioRecorderError.audioSystemTimedOut(Self.startTimeout)) {
            [weak self] in
            guard let self else { throw AudioRecorderError.noInputDevice }
            try self.startOnEngineQueue()
        }
    }

    /// Ends the recording and hands over everything it captured.
    ///
    /// The recorder lets go of the buffer as it hands it over. Keeping a second copy
    /// until the next recording starts would hold the whole dictation in memory for as
    /// long as the app is idle, which is about 4 MB a minute of speech for no reason.
    ///
    /// Stopping the hardware is left to `engineQueue`, so this returns straight away even
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

    // MARK: - The engine (engineQueue only)

    private func startOnEngineQueue() throws {
        dispatchPrecondition(condition: .onQueue(engineQueue))
        idleTeardown?.cancel()
        idleTeardown = nil

        let started = Date()
        let engine = readyEngine()
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            discardEngine(because: "the input node reported no usable format")
            throw AudioRecorderError.noInputDevice
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            discardEngine(because: "the input format cannot be converted to 16 kHz mono")
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
            discardEngine(because: "the engine would not start")
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
    private func readyEngine() -> AVAudioEngine {
        dispatchPrecondition(condition: .onQueue(engineQueue))
        let wanted = MicrophoneDevices.preferred()
        let systemDefault = MicrophoneDevices.systemDefault()?.audioDeviceID

        if let engine, wanted?.audioDeviceID == engineWantedDevice,
           systemDefault == engineSystemDefault {
            return engine
        }
        discardEngine(because: "the microphone to record from changed")

        let engine = AVAudioEngine()
        self.engine = engine
        engineWantedDevice = wanted?.audioDeviceID
        engineSystemDefault = systemDefault
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
        engineQueue.async { [weak self] in
            guard let self, let engine = self.engine else { return }
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.scheduleIdleTeardown()
        }
    }

    private func scheduleIdleTeardown() {
        dispatchPrecondition(condition: .onQueue(engineQueue))
        idleTeardown?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.discardEngine(because: "nothing has been recorded for a while")
        }
        idleTeardown = work
        engineQueue.asyncAfter(deadline: .now() + Self.idleTeardownDelay, execute: work)
    }

    private func discardEngine(because reason: String) {
        dispatchPrecondition(condition: .onQueue(engineQueue))
        guard let engine else { return }
        Log.debug("Dropping the audio engine: \(reason)")
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        engineWantedDevice = nil
        engineSystemDefault = nil
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
