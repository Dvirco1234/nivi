import Foundation

/// Smallest encoder context whisper is asked for. Below this the output degrades badly
/// even on very short audio, and the saving is not worth it.
public let minimumAudioContext = 256
/// whisper's full encoder context: 1500 positions for the 30 seconds it was trained on.
/// `whisper_full` rejects anything larger.
public let maximumAudioContext = 1500

/// Pass this as the audio context to mean "use the model's own full context". It is
/// whisper's own way of saying it: `whisper_full_params.audio_ctx = 0`.
public let wholeAudioContext = 0

/// The encoder context must be a multiple of this, or whisper's Metal backend kills the
/// whole process.
///
/// Metal's matrix kernels require the row stride of the tensor, in bytes, to be aligned.
/// ggml checks it and calls `ggml_abort` when it is not:
///
///     ggml/src/ggml-metal.m:1925: GGML_ASSERT(nb01 % 8 == 0) failed
///
/// For an F16 model that stride is `audio_ctx * 2` bytes, so `audio_ctx` has to divide by
/// 4. For an F32 one the check is `nb01 % 16` over 4-byte elements, which is the same
/// rule. Verified on ivrit-large-v3-turbo: every multiple of 4 from 256 to 1500 runs, and
/// 257, 258, 259, 371, 629 and 631 all abort.
///
/// Do not "simplify" this away. An abort inside a C library is not an error Nivi can
/// catch: it takes the app down and the user loses the dictation they were in the middle
/// of.
public let audioContextAlignment = 4

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
/// The result is rounded **up** to `audioContextAlignment`, so it never gives the model
/// less context than the audio needs. See that constant for why the rounding is not
/// optional.
///
/// Note: this override is ignored by a Core ML encoder, which has a fixed input shape
/// (whisper.cpp issues #1488, #2405). Nivi runs the Metal encoder, so it applies today.
public func audioContext(forSampleCount sampleCount: Int, sampleRate: Int) -> Int {
    guard sampleCount > 0, sampleRate > 0 else { return minimumAudioContext }
    let proportional = maximumAudioContext * sampleCount / (sampleRate * 30) + 128
    let aligned = ((proportional + audioContextAlignment - 1) / audioContextAlignment)
        * audioContextAlignment
    return min(maximumAudioContext, max(minimumAudioContext, aligned))
}

/// Whether whisper can be handed this audio context without aborting.
///
/// The last line of defence. `audioContext(forSampleCount:sampleRate:)` already returns a
/// usable value, but anything that reaches whisper by another route is checked here first,
/// because getting this wrong crashes the process rather than returning an error.
public func isUsableAudioContext(_ value: Int) -> Bool {
    value >= minimumAudioContext
        && value <= maximumAudioContext
        && value % audioContextAlignment == 0
}
