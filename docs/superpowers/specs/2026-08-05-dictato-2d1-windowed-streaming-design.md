# Dictato 2d.1 — Windowed Streaming (design)

Date: 2026-08-05
Status: Approved
Builds on: `2026-07-26-dictato-2d-streaming-design.md` (live streaming, shipped)

## Problem

Live preview is laggy, and the lag grows as you speak. Two causes:

1. **Every pass re-transcribes the whole recording.** Pass duration grows with the
   recording, so by 30 s each pass is slow and the preview falls further behind. In-app-live
   is worse still: `StablePrefixTracker` needs two *consecutive* identical passes before
   committing a word, so commit latency is roughly twice the pass duration.
2. **The final pass re-transcribes everything too.** With `maxRecordingSeconds` at 600, a
   long dictation means whisper chews through minutes of audio while the user waits.

The current mitigation — freezing the preview past `maxStreamingSeconds` — hides the
symptom rather than fixing it.

## The constraint that shapes the design

Whisper's encoder always runs over a fixed 30-second context (`n_audio_ctx` = 1500 frames);
`whisper_full` pads shorter audio to fill it. **So shortening the transcribed window does
not, by itself, make a pass faster** — 5 s costs the same encoder time as 25 s.

The lever that does work is `whisper_full_params.audio_ctx` (`whisper.h:504`), which
overrides that context size. whisper.cpp's own `stream` example exposes it as `-ac`.
Scaling `audio_ctx` down in proportion to the window is what converts a shorter window into
a genuinely cheaper pass.

Windowing and `audio_ctx` scaling only work together. Either alone is close to pointless:
window-only keeps the fixed encoder cost, `audio_ctx`-only shrinks the context whisper can
attend to while still feeding it the whole growing buffer.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Older text freezes mid-dictation | **Accepted** | Speed matters more than mid-dictation revisions. In-app-live has already typed that text and cannot retract it, so freezing changes little there in practice. |
| Final pass scope | **Unfrozen tail only**, stitched onto frozen text | Makes stopping near-instant regardless of dictation length. Costs whole-buffer correction on long dictations — a real quality tradeoff, accepted deliberately. |
| Window length | **10 s default**, configurable | Keeps a couple of sentences of context for punctuation and self-correction. Much shorter degrades whisper on padded audio while saving little once `audio_ctx` is already scaled. |
| Freeze boundary | **Whole segments, by timestamp** | The only way to know which words belong to audio that scrolled out. Guessing produces duplicated or dropped words at the seam. |
| Batch mode | **Untouched** | No streaming, so it keeps today's whole-buffer pass and its full-context quality. |

## Architecture

```
DictatoCore
├── TranscriptSegment        NEW  { text, startMs, endMs } — pure value type
├── StreamWindow             NEW  pure freeze/stitch logic (frozenText + windowStart)
└── Settings                 +streamingWindowSeconds (10)

Dictato
├── SpeechRecognizer         +transcribeSegments(samples:language:audioCtx:)
├── WhisperCppRecognizer     implements it: no_timestamps = false, audio_ctx, segment reads
├── StreamingTranscriber     drives StreamWindow; transcribes only the live window
└── DictationController      final pass covers the unfrozen tail, stitched onto frozen text
```

### TranscriptSegment (DictatoCore)

```swift
public struct TranscriptSegment: Equatable {
    public let text: String
    public let startMs: Int
    public let endMs: Int
}
```

Times are relative to the start of the samples passed to that call, not to the recording.
The caller converts to absolute positions using the window offset it supplied.

### StreamWindow (DictatoCore, pure and testable)

Holds `frozenText: String` and `windowStartSample: Int`. After each pass:

```swift
public mutating func advance(segments: [TranscriptSegment],
                             windowSampleCount: Int,
                             maxWindowSamples: Int,
                             sampleRate: Int) -> String   // returns full live text
```

Rules:
- If `windowSampleCount <= maxWindowSamples`, nothing freezes.
- Otherwise freeze the leading segments whose `endMs` falls before the point where the
  window would have to start to fit `maxWindowSamples`, append their text to `frozenText`,
  and advance `windowStartSample` by that segment's `endMs`.
- Never freeze the final segment, even if it alone exceeds the window — it is still being
  spoken and its text will keep changing. A single over-long segment simply means the
  window temporarily exceeds its nominal length; correctness beats the size target.
- The live text returned is `frozenText` joined with the current window's text.

This is where seam bugs would live, so it is a pure value type with no recognizer or audio
dependency and is covered by the swiftc core-test harness.

### Recognizer

```swift
func transcribeSegments(samples: [Float], language: String, audioCtx: Int) async throws -> [TranscriptSegment]
```

`WhisperCppRecognizer` sets `params.no_timestamps = false` and `params.audio_ctx = audioCtx`
(0 meaning "model default"), then reads `whisper_full_n_segments`,
`whisper_full_get_segment_t0/t1` (centiseconds → ms) and `whisper_full_get_segment_text`.
The existing string-returning `transcribe(samples:language:)` stays for batch and is left
on the default full context.

### audio_ctx scaling

`audioCtx = max(floor(1500 × windowSeconds / 30), 256)`, so 10 s → 500.

The floor matters: `audio_ctx` below roughly a sixth of the full context degrades accuracy
sharply, and this is a documented-as-lossy optimization, not a free win. The final pass
deliberately uses the full context (`audioCtx = 0`) so the text the user keeps is not
subject to this tradeoff.

### StreamingTranscriber

Per pass: take `recorder.currentSamples()`, slice from `window.windowStartSample`,
`transcribeSegments` with the scaled `audioCtx`, feed the window's text through the
existing `StablePrefixTracker`, then `window.advance(...)`. Emits the same
`StreamingUpdate`, where `fullText` is frozen + live and `stableText` is frozen + the
tracker's committed prefix — so the committed prefix stays monotonic across a freeze, which
the append-only invariant requires.

`maxStreamingSeconds` and its freeze behavior are removed: passes are now bounded by
construction, so there is nothing to freeze against. Its Preferences control is replaced by
the window-length control.

### DictationController

On stop for a live-mode profile: transcribe only from `window.windowStartSample` at full
context, stitch onto `frozenText`, then insert per mode. In-app-live still routes through
`appendOnlyTail` against `typedText`, so the append-only guarantee is unchanged. If
streaming never started (cold-model fallback), the final pass covers the whole buffer as it
does today.

## Error handling

- A failed pass leaves `frozenText` and `windowStartSample` untouched and retries next
  interval; freezing only ever advances on a successful pass.
- Empty segment list is treated as a failed pass — no freeze, no update.
- If the window somehow grows past two nominal windows (pathological single segment), log
  once and keep going rather than force-freezing mid-segment.

## Testing

- Core: `StreamWindow` — nothing to freeze; freeze one segment; freeze several at once; a
  single segment longer than the window (must not freeze); empty segments; stitching
  produces no doubled or missing spaces; `windowStartSample` advances monotonically.
- Core: `TranscriptSegment` round-trip and ms conversion.
- Manual: preview keeps up during a 60 s dictation and does not degrade as it runs; stopping
  after a long dictation returns text near-instantly; no duplicated or dropped words at
  freeze boundaries; in-app-live never rewrites typed text; batch unchanged; Hebrew and
  English profiles both correct.

## Out of scope

VAD auto-stop, a second smaller model for preview passes, re-correcting frozen text,
punctuation post-processing.
