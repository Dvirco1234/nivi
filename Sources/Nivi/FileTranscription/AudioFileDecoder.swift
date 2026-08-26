import AVFoundation
import Foundation

/// Why a file could not be turned into samples, in words the tab can show as they are.
enum AudioFileDecodingError: LocalizedError {
    case formatNotSupported
    case noAudioTrack
    case couldNotRead(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .formatNotSupported:
            return "This file format is not supported. Try converting it to MP3 or WAV first."
        case .noAudioTrack:
            return "There is no audio in this file."
        case .couldNotRead(let reason):
            return "Nivi could not read this file. \(reason)"
        case .cancelled:
            return "Stopped."
        }
    }
}

/// Turns an audio or video file into the 16 kHz mono samples the speech models expect.
///
/// Everything goes through `AVAssetReader`, including plain audio files. It opens
/// whatever the system's own decoders handle, and unlike `AVAudioFile` it also opens video
/// containers and pulls the audio track out of them. It resamples on the way, so there is
/// no second resampling path to keep in step with `AudioRecorder`.
enum AudioFileDecoder {
    static let sampleRate = 16_000

    /// Decodes the whole file.
    ///
    /// Memory, stated plainly: 16 kHz mono Float32 is 64 KB a second, so about 230 MB for
    /// an hour. Fine on an Apple Silicon Mac, not free. The read loop already works in
    /// pieces, so decoding straight into chunks later is a change, not a rewrite.
    static func decode(url: URL,
                       onProgress: @escaping @Sendable (Double) -> Void,
                       isCancelled: @escaping @Sendable () -> Bool) async throws -> [Float] {
        let asset = AVURLAsset(url: url)

        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw AudioFileDecodingError.formatNotSupported
        }
        guard !tracks.isEmpty else { throw AudioFileDecodingError.noAudioTrack }

        let duration = (try? await asset.load(.duration).seconds) ?? 0

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw AudioFileDecodingError.couldNotRead(error.localizedDescription)
        }

        // Ask the reader for exactly the format whisper.cpp takes, and let Core Media do
        // the resampling.
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        guard reader.canAdd(output) else { throw AudioFileDecodingError.formatNotSupported }
        reader.add(output)
        guard reader.startReading() else {
            throw AudioFileDecodingError.couldNotRead(
                reader.error?.localizedDescription ?? "The file could not be opened.")
        }

        var samples: [Float] = []
        if duration > 0 {
            samples.reserveCapacity(Int(duration) * sampleRate)
        }

        while let buffer = output.copyNextSampleBuffer() {
            if isCancelled() {
                reader.cancelReading()
                throw AudioFileDecodingError.cancelled
            }
            append(buffer, to: &samples)
            CMSampleBufferInvalidate(buffer)
            if duration > 0 {
                onProgress(min(1, Double(samples.count) / Double(sampleRate) / duration))
            }
        }

        switch reader.status {
        case .completed:
            break
        case .cancelled:
            throw AudioFileDecodingError.cancelled
        default:
            throw AudioFileDecodingError.couldNotRead(
                reader.error?.localizedDescription ?? "The file ended early.")
        }

        guard !samples.isEmpty else { throw AudioFileDecodingError.noAudioTrack }
        onProgress(1)
        return samples
    }

    private static func append(_ buffer: CMSampleBuffer, to samples: inout [Float]) {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { return }
        var lengthAtOffset = 0
        var totalLength = 0
        var pointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset,
                                          totalLengthOut: &totalLength,
                                          dataPointerOut: &pointer) == kCMBlockBufferNoErr,
              let pointer else { return }
        let count = totalLength / MemoryLayout<Float>.size
        pointer.withMemoryRebound(to: Float.self, capacity: count) { floats in
            samples.append(contentsOf: UnsafeBufferPointer(start: floats, count: count))
        }
    }
}
