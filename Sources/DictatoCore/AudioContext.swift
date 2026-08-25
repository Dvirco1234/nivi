import Foundation

/// Smallest encoder context whisper is asked for. Below this the output degrades badly
/// even on very short audio, and the saving is not worth it.
public let minimumAudioContext = 256
/// whisper's full encoder context: 1500 positions for the 30 seconds it was trained on.
/// `whisper_full` rejects anything larger.
public let maximumAudioContext = 1500

/// Encoder context to request for a slice of audio.
///
/// whisper's encoder always runs the full 30 seconds and pads shorter audio, so a short
/// slice is only cheaper if the context shrinks with it. Size it to the audio actually
/// being transcribed: a context smaller than the audio cuts real speech out of the encoder
/// before the model ever sees it, and that speech is then silently missing from the text.
///
/// The slack is what whisper.cpp issue #1855 used (`1500 * seconds / 30 + 128`) when it
/// measured no accuracy loss over 200 clips. It covers a slice that runs slightly longer
/// than expected, which is normal here because the live window overruns whenever a segment
/// is still being spoken.
///
/// Note: this override is ignored by a Core ML encoder, which has a fixed input shape
/// (whisper.cpp issues #1488, #2405). Dictato runs the Metal encoder, so it applies today.
public func audioContext(forSampleCount sampleCount: Int, sampleRate: Int) -> Int {
    guard sampleCount > 0, sampleRate > 0 else { return minimumAudioContext }
    let proportional = maximumAudioContext * sampleCount / (sampleRate * 30) + 128
    return min(maximumAudioContext, max(minimumAudioContext, proportional))
}
