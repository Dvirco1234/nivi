import AVFoundation
import AudioToolbox
import CoreAudio

/// Records microphone input and accumulates 16 kHz mono Float32 samples in memory.
final class AudioRecorder {
    static let sampleRate = 16_000.0

    var onLevel: ((Float) -> Void)?

    // A fresh engine is built per recording so it always binds the CURRENT default
    // input device — reusing one engine goes stale when AirPods/headphones connect
    // or the route changes, which made recording silently fail.
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let samplesQueue = DispatchQueue(label: "com.dvir.dictato.audio")
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

    func start() throws {
        samplesQueue.sync { samples.removeAll() }
        tearDown()   // drop any previous engine

        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        // Pick the microphone before asking the node anything about its format: the format
        // belongs to whichever device the node is bound to, and the binding cannot be
        // changed once the engine is running.
        bindPreferredMicrophone(on: input)
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            self.engine = nil
            throw NSError(domain: "Dictato", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No audio input device available"])
        }
        Log.info("Recording input: \(Int(inputFormat.sampleRate)) Hz, \(inputFormat.channelCount) ch")
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            tearDown()
            throw error
        }
    }

    func stop() -> [Float] {
        tearDown()
        return samplesQueue.sync { samples }
    }

    /// A snapshot of everything recorded so far. Recording continues; the streaming
    /// loop re-transcribes this growing buffer. Taken under `samplesQueue` because
    /// the audio tap appends to `samples` from a real-time thread.
    func currentSamples() -> [Float] {
        samplesQueue.sync { samples }
    }

    func cancel() {
        tearDown()
        samplesQueue.sync { samples.removeAll() }
    }

    /// Points the engine at the first microphone on the user's priority list that is
    /// plugged in.
    ///
    /// Nothing happens when the list is empty or none of its devices are connected, and
    /// the engine keeps the system's default input, exactly as before this setting
    /// existed. A failure here is logged and ignored for the same reason: recording with
    /// the wrong microphone is much better than not recording at all.
    private func bindPreferredMicrophone(on input: AVAudioInputNode) {
        guard let device = MicrophoneDevices.preferred() else { return }
        guard let unit = input.audioUnit else {
            Log.error("No audio unit on the input node, keeping the system microphone")
            return
        }
        var deviceID = device.audioDeviceID
        let status = AudioUnitSetProperty(unit,
                                          kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global,
                                          0,
                                          &deviceID,
                                          UInt32(MemoryLayout<AudioDeviceID>.size))
        if status == noErr {
            Log.info("Recording from \(device.name)")
        } else {
            Log.error("Could not select \(device.name) (status \(status)), keeping the system microphone")
        }
    }

    private func tearDown() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        converter = nil
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
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
        samplesQueue.sync { samples.append(contentsOf: chunk) }

        let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
        // Perceptual boost: sqrt curve + high gain so normal speech swings the bars.
        let level = min(1.0, sqrt(rms) * 3.2)
        DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
    }
}
