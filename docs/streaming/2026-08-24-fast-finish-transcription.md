# Fast finish: transcribe while recording, paste all at once

Date: 2026-08-24
Status: research and design proposal. No code changed.

## What this document answers

Spokenly got a lot faster at the moment you stop recording. The guess was that
they transcribe the audio in small pieces while you speak, so at the end there
is almost nothing left to do. This document checks that guess, measures what it
would cost Nivi, and proposes what to build.

## Verdict, in short

**The guess is right in shape.** Transcribing while you speak really does turn the wait at the
end from "grows with how long you talked" into "about a second, always". That is why it feels
like 10x on a long sentence and barely different on a short one.

**Three things the guess misses.**

1. The piece size does not set the leftover on its own. What matters is whether each pass
   *moves past* the audio or *re-does* it. Nivi's current live loop re-does it, so the
   leftover is a whole window (10s by default), not the 500ms interval.
2. It is not free. Re-transcribing a rolling window costs roughly 6 to 7 times the total
   compute of one batch pass. A forward-only version costs about the same as batch.
3. The accuracy loss is not concentrated at the end. It is spread across the whole text,
   and it is probably worse in Hebrew than in English, because Hebrew is written without vowel
   marks and leans harder on surrounding words.

**But the guess about the competitor is probably wrong.** Spokenly publishes a real, detailed
changelog, and it contains no entry describing chunked local transcription. Every "realtime" or
"streaming" entry names a cloud engine or Apple's system engine. What it does contain is
"Added NVIDIA Parakeet Unified, a new fully on-device transcription model" in June 2026, then
one month later "Customize Parakeet Unified latency for speed and energy use". Measured
benchmarks put Parakeet on the Neural Engine at roughly **140 to 155 times real time** against
whisper's roughly 15 to 20. **An engine switch explains "10x or more, slightly less accurate"
completely, with no chunking involved.** Superwhisper's changelog tells the same story.

This is stated as the better-supported reading of the public evidence, not as proof. There is
no statement from Spokenly either way.

**The main finding on Nivi's side: it already built the fast finish.**
`dvir/2d1-windowed-streaming` contains a final pass that re-transcribes only the un-frozen
tail. Its own design document says it "makes stopping near-instant regardless of dictation
length", and the same document says batch mode was left "untouched" on purpose, to protect
batch accuracy. Turning it on for batch is about ten lines across two files.

**Recommendation.**

- Do two free fixes now: warm the model at recording start, and size `audio_ctx` to the audio
  actually being transcribed (today's formula can cut real speech out of the encoder).
- Add a fourth insertion mode, `batchFastFinish`, reusing machinery that already exists and is
  already in daily use by overlay-live. Half a day. Ship it as a choice, not a default.
  Expect roughly a 1-second finish regardless of length, against about 6 seconds today for a
  60-second dictation and 18 for a 3-minute one.
- **In parallel, measure Parakeet on real Hebrew.** This is the fork in the road. If Parakeet
  is good enough in Hebrew, its speed advantage removes the latency problem outright and the
  deeper chunking work (forward-only, VAD, prompt carryover) should never be built. Its
  published accuracy numbers are English only; the multilingual average is much worse, and
  Hebrew was not broken out.

**Measure `r` first.** Every latency number in this document rests on an assumed 0.1 seconds of
compute per second of audio. Nivi already logs the real figure. Read it before building
anything.

---

## Part A: what Nivi already has

### Branch state, because it got confusing

Checked with `git branch --merged main` and `git log main..<branch>`.

- `main` head is `1662010 docs: 2d streaming spec (reconciled with profiles) + implementation plan`.
  **`main` has the 2d design documents and nothing else.** No streaming code at all.
- `dvir/2d-streaming`: **not merged into main.** 22 commits ahead of main. This is the
  whole first streaming feature: `StablePrefixTracker`, `appendOnlyTail`, `StreamingTranscriber`,
  live insertion modes in Preferences, Unicode typing, plus a long tail of correctness fixes.
- `dvir/2d1-windowed-streaming`: **not merged into main either.** 43 commits ahead of main,
  and it **contains every commit of `dvir/2d-streaming`**. It is a strict superset. It adds
  `StreamWindow`, `transcribeSegments` with the `audio_ctx` override, the bounded final pass,
  the Notch recording display, model catalog work and the layout tuning work.
- `main` has nothing that is missing from `dvir/2d1-windowed-streaming` (`git log dvir/2d1-windowed-streaming..main` is empty).

So: everything real lives on `dvir/2d1-windowed-streaming`, which is the branch currently
checked out. `dvir/2d-streaming` can be deleted once 2d.1 lands. Merging 2d.1 into main
brings both features in one go.

Both branches also exist on `origin` at the same commits.

### The three insertion modes

Defined in `Sources/NiviCore/Settings.swift` lines 3-13:

```swift
public enum InsertionMode: String, Codable, CaseIterable {
    case batch, overlayLive, inAppLive
```

Each profile carries one mode (`Sources/NiviCore/DictationProfile.swift`, field `mode`).
So the mode is already a per-profile choice, not a global setting. That matters for Part D.

### The streaming machinery, file by file

**`Sources/NiviCore/StreamWindow.swift`** (68 lines).
Keeps a moving window over the recording. Text for audio that has scrolled out of the
window is "frozen": committed and never re-transcribed. It only freezes on whole segment
boundaries, using the `startMs`/`endMs` that whisper gives per segment, because that is
the only place where you can cut without dropping or repeating words. It never freezes the
last segment, since that one is still being spoken. It exposes `frozenText` and
`windowStartSample`.

**`Sources/NiviCore/StablePrefixTracker.swift`** (44 lines).
Turns a series of live guesses into a word prefix that only ever grows. A word is
"committed" once it survived `stabilityPasses` passes unchanged (default 2). Used by
in-app-live, where typed words cannot be taken back.

**`Sources/NiviCore/AppendOnlyTail.swift`** (51 lines).
`appendOnlyTail(alreadyTyped:fullText:)` works out what to add so the document grows toward
the final text without deleting anything. Matches on words with case and punctuation
ignored, because whisper re-punctuates earlier words as more context arrives.

**`Sources/Nivi/StreamingTranscriber.swift`** (140 lines).
The loop. Every `intervalMs` after the previous pass *finishes*, it takes the audio from
`window.windowStartSample` to now, transcribes it with `transcribeSegments`, folds the
result into the `StreamWindow`, and calls `onUpdate` with `fullText` and `stableText`.
It carries the `audioCtx` calculation:

```swift
private var audioCtx: Int {
    max(256, 1500 * windowSeconds / 30)
}
```

**`Sources/Nivi/WhisperCppRecognizer.swift`**.
Two entry points: `transcribe(samples:language:)` (no timestamps, model default audio
context, used by the final pass) and `transcribeSegments(samples:language:audioCtx:)`
(timestamps on, `params.audio_ctx` overridden, used by the live loop). Both run on one
serial `DispatchQueue`, so passes never overlap and a `whisper_free` can never race an
in-flight `whisper_full`.

**`Sources/Nivi/DictationController.swift`** (495 lines). The important part.

Line 208, in `startRecording()`:

```swift
if profile?.mode != .batch, let profile {
    startStreaming(for: profile, generation: generation)
}
```

That single line is the only thing stopping batch mode from streaming.

Lines 293-340, in `stopAndTranscribe()`:

```swift
let streamedTailStart = streamer?.windowStartSample ?? 0
let frozenText = streamer?.frozenText ?? ""
...
if streamedTailStart > 0, samples.count > streamedTailStart {
    let tail = Array(samples[streamedTailStart...])
    let tailText = try await recognizer.transcribe(samples: tail, language: profile.language)
    ...
    text = frozenText + " " + tailText
} else {
    text = try await recognizer.transcribe(samples: samples, language: profile.language)
}
```

**This is already the fast finish.** The bounded final pass exists, is written, is tested in
use by overlay-live, and re-transcribes only the audio the window never froze. It is simply
never reached in batch mode, because batch mode never starts a streamer, so
`streamedTailStart` is `0` and the code falls into the slow whole-buffer branch.

Lines 270-281, `handleStreamingUpdate`, already has a `case .batch: break`. The switch is
already shaped for a mode that streams but shows nothing.

### The `copyOnly` note

The task brief flagged that `copyOnly` is never consulted in `inserter.insert(...)`.
That is true **on `main`**: there, the method signature is
`func insert(_ text: String, autoPaste: Bool, excludeFromHistory: Bool) -> Bool`, with no
`copyOnly` parameter at all.

It is **already fixed on `dvir/2d1-windowed-streaming`** by commit `334c777 fix: clipboard
history ordering, honour copy-only, steady waveform`. On that branch
`TextInserter.insert(_:autoPaste:copyOnly:excludeFromHistory:)` computes
`let willPaste = autoPaste && !copyOnly && PermissionManager.accessibilityGranted`, and
`DictationController` passes `copyOnly: settings.copyOnly` at line 351.

Nothing here needs fixing, and nothing in this design touches it. The only connection is
that fast-finish batch mode uses the exact same `inserter.insert(...)` call as today, so
whatever `copyOnly` does today it keeps doing.

### Existing plan documents

- `docs/superpowers/specs/2026-07-26-nivi-2d-streaming-design.md` and
  `docs/superpowers/plans/2026-07-26-nivi-2d-streaming.md`: the first streaming design.
- `docs/superpowers/specs/2026-08-05-nivi-2d1-windowed-streaming-design.md` and
  `docs/superpowers/plans/2026-08-05-nivi-2d1-windowed-streaming.md`: the sliding
  window design. The bounded final pass is already specified there.
- `docs/parakeet/2026-08-24-parakeet-integration-options.md`: a different engine option,
  relevant to Part C.

The 2d.1 design document is worth quoting, because it already made this exact decision and
then deliberately stopped one step short:

> Final pass scope: **Unfrozen tail only**, stitched onto frozen text. Makes stopping
> near-instant regardless of dictation length. Costs whole-buffer correction on long
> dictations — a real quality tradeoff, accepted deliberately.

> Batch mode: **Untouched.** No streaming, so it keeps today's whole-buffer pass and its
> full-context quality.

So the "instant finish" is not a new idea for Nivi. It was designed, built, and then
scoped out of batch mode on purpose, to protect batch mode's accuracy. What the user is now
asking for is to make that trade available in batch mode as a choice.

---

## Part B: is the hypothesis right

The hypothesis was: *"maybe they take samples every few seconds, two seconds for example,
and build the sentence piece by piece, so when I finish the whole recording it does not need
to transcribe everything, only the last part."*

**The structure of that is right. Three details are wrong or missing.** Details below.

### How batch mode scales today

whisper does not process a long clip in one shot. Inside `whisper_full`, the audio is cut
into 30-second pieces and each piece is run through the encoder and then the decoder. So for
an N-second recording:

```
finish time  ~=  ceil(N / 30) * (encoder cost + decoder cost per piece)
             ~=  r * N        (r = seconds of compute per second of audio)
```

It is close to a straight line in N, with a small step every 30 seconds. `r` is the
"real-time factor". Nivi already logs the real number: `Log.info("Inference completed in
...s")` in `DictationController.swift` line 341. Reading that line against the recording
length in the line above it gives the true `r` on this machine and model.

Concretely, at a plausible `r = 0.1` for a turbo-class model on Apple Silicon with Metal:

| recording | finish wait today |
|---|---|
| 10s | ~1s |
| 30s | ~3s |
| 60s | ~6s |
| 180s | ~18s |

This matches the complaint exactly. Short dictation feels fine. A long sentence feels slow,
and it gets worse the longer you talk. The wait is proportional to how much you said.

### What is left to do at stop, if you transcribe while recording

If audio is transcribed as it arrives, then at the moment of stop the only untranscribed
audio is whatever arrived since the last piece was handled. That is bounded by the piece
size, not by the recording length. So:

```
finish time  ~=  r * (leftover audio)   where leftover <= one chunk
```

**Confirmed: the finish becomes roughly constant instead of proportional to N.** This is the
real reason the competitor feels "10x or more" faster on long recordings, and only slightly
faster on short ones. The speedup is not a constant multiplier. It is the difference between
a line and a flat line, so it grows with how long you talk. That also explains why the
user described it as dramatic: he speaks long sentences.

### Correction 1: what bounds the leftover is the chunk, not the sample interval

The hypothesis said "samples every two seconds". Sampling every two seconds does not by
itself mean only two seconds are left at the end. It depends on whether each pass
**re-transcribes** recent audio or **moves past** it.

Nivi's current live loop **re-transcribes** the whole trailing window on every pass. So
at stop, the leftover is the whole window (`streamingWindowSeconds`, default 10), not the
half-second interval. That is exactly what `stopAndTranscribe` does today: it re-transcribes
`samples[windowStartSample...]`, which is up to one window long.

For a fast finish you want the other shape: **forward-only**. Transcribe each piece of audio
exactly once, commit it, never look back. Then the leftover at stop is only the audio since
the last commit, which is between zero and one chunk. With an 8-second chunk and `r = 0.1`,
that is 0 to 0.8 seconds, about 0.4 seconds on average.

Useful discovery: `StreamWindow` already supports forward-only behaviour with no code
change to its logic. If `maxWindowSamples` is set very small, the freeze loop at lines 41-44
freezes every segment except the last one on every pass. That is forward-only. The tuning
lives at the call site, not inside `StreamWindow`.

### Correction 2: re-transcribing is expensive, forward-only is not

This is the part the hypothesis leaves out entirely, and it decides the design.

**Today's live loop (re-transcribe the window every pass).** With window `W = 10s`,
`intervalMs = 500`, and `r = 0.1`, each pass costs about `0.1 * 10 = 1s` and the next starts
0.5s later. So a pass runs roughly every 1.5 seconds, and the machine is doing inference
about 65% of the time you are speaking. Every second of audio gets transcribed roughly
`W / 1.5 ~= 6-7` times before it freezes. Over a 60-second recording that is around
40 seconds of inference instead of 6. **Roughly 6 to 7 times the total compute.** On a
laptop on battery that is real: sustained GPU and 8 CPU threads, fans, and heat.

**Forward-only chunking.** Each second of audio is transcribed exactly once. Total compute
is about the same as batch mode does today, maybe 1.2 to 1.5x because you pay some fixed
per-call overhead more often and lose some of the 30-second batching. But it is spread out
across the recording, while the user is still talking and not waiting.

So the honest summary is: **forward-only chunking makes the finish constant and costs almost
nothing extra in battery. Re-transcribing chunking makes the finish constant but costs
several times the battery.** Nivi's existing loop is the second kind, because it was built
to drive a live preview that can correct itself. Batch fast-finish does not need correction,
because nothing is shown, so it should use the first kind.

### Correction 3: the accuracy loss is not at the end, it is everywhere

The accuracy drop the user noticed is real and expected. Here is exactly where it comes from,
in rough order of how much it hurts:

1. **Less right-hand context.** whisper is trained on 30-second windows and uses everything it
   heard, including what comes *after* a word, to decide what that word was. A chunk that ends
   at second 8 has nothing after second 8. The last few words of every chunk are decided with
   no future context. This is the biggest single cause.

2. **A reduced `audio_ctx`, but only if it is set too low.** Nivi scales
   `audio_ctx = max(256, 1500 * windowSeconds / 30)` so a short window is actually cheaper.
   The comment in `StreamingTranscriber.swift` line 44 calls this "a lossy optimization, not a
   free one". Part C found evidence that this is more pessimistic than it needs to be: sizing
   the context to the audio you actually have appears close to free, and the real damage comes
   from sizing it *below* the audio you have, which cuts real speech out of the encoder.
   Nivi's current formula can do exactly that, and Part C proposes a one-line fix.

3. **Words split across a chunk edge.** If a chunk boundary lands in the middle of a word, both
   sides get a fragment. Nivi already avoids the worst of this by freezing on whisper's own
   segment boundaries, which whisper places at natural pauses. That is a genuine advantage over
   a naive fixed-timer cut. Voice activity detection would tighten it further (Part C).

4. **No whole-utterance pass at the end.** In batch mode today, whisper sees the entire
   recording and punctuates and capitalizes it as one piece. Chunked, each piece is punctuated
   on its own. You get sentences that end early, capital letters in odd places, and
   inconsistent comma use. Prompt carryover (Part D, option 3) fixes most of this.

5. **The decoder cannot go back.** Once text is frozen it is final. In batch mode whisper can
   effectively revise a word when later audio contradicts it. Chunked, it cannot.

**For Hebrew this matters more than for English.** Hebrew is written without vowel marks, so
a great deal of word identity is decided from surrounding words rather than from the letters
themselves. whisper's Hebrew training data is also thinner than its English data, so the model
leans harder on context to compensate. Cutting the context is exactly the wrong thing to do to
a Hebrew model. Expect the accuracy cost of chunking to be noticeably larger in Hebrew than
the same change would cost in English.

This is not a reason to abandon the idea. It is a reason to (a) keep chunks generous, around
8 to 15 seconds rather than 2 to 3, (b) cut on silence, and (c) make it a choice the user can
turn off per profile rather than a new default that silently degrades his main language.

### Where does that leave the hypothesis

| claim | verdict |
|---|---|
| They transcribe in pieces during recording | Very likely right, and it is the standard technique |
| The finish becomes near-instant because only the last part is left | Right. Constant instead of proportional to length |
| "Two seconds" is the piece size | Probably too small. Nothing forces the piece to equal the leftover, and a 2s piece would hurt accuracy badly |
| Accuracy drops slightly | Right, and this document names the five specific causes |
| It is basically what "Live typing into app" already does, minus the typing | Right in spirit. In practice batch fast-finish should use a cheaper forward-only variant, not the same re-transcribing loop |

One thing the hypothesis does not consider: **the competitor may have changed engine, not
algorithm.** A switch from whisper to something like NVIDIA Parakeet would also produce
"much faster, slightly less accurate" with no change in model that the user would notice from
the settings screen.

Part C went looking, and this turns out to be the better-supported explanation. Spokenly's
changelog contains no entry describing chunked local transcription. It does contain "Added
NVIDIA Parakeet Unified, a new fully on-device transcription model" in June 2026, followed one
month later by "Customize Parakeet Unified latency for speed and energy use". Measured
benchmarks put Parakeet on the Neural Engine at roughly 150x real time against whisper's
roughly 15 to 20x. That alone explains "10x or more", with no chunking involved.

---

## Part C: what is available in the wild

All of this was checked on 2026-08-24. whisper.cpp `master`, latest tag v1.9.3 (2026-08-20).

### whisper.cpp's own streaming example

`examples/stream/stream.cpp`. Defaults: `step_ms = 3000`, `length_ms = 10000`,
`keep_ms = 200`, `no_context = true`.

It has two modes.

- **Timer mode** (`--step > 0`). Every 3 seconds it re-transcribes a growing window up to
  10 seconds, then slides. It keeps the last `keep_ms` of audio across the boundary, and the
  code comment says exactly why: `// keep part of the audio for next iteration to try to
  mitigate word boundary issues`. So the official example confirms the boundary problem is
  real and that overlap is the standard patch for it.
- **Silence mode** (`--step 0`). Uses a simple energy-based detector (a `-vth` threshold), not
  Silero, and transcribes the last `length_ms` whenever silence is detected. It forces
  `no_context` on in this mode: `params.no_context |= use_vad;`.

Context carryover is off by default. `--keep-context` / `-kc` turns it on, and it then feeds
the token ids of the last full segment into the next call as `prompt_tokens`.

One behaviour worth copying: if the audio arrives faster than inference can keep up, the
example prints `WARNING: cannot process audio fast enough, dropping audio ...` and clears the
buffer. Nivi does not need to drop audio (it stores the whole recording), but it does need
the equivalent warning. `StreamingTranscriber.swift` lines 109-114 already has one for the
related "window never advances" case.

### Voice activity detection is built into whisper.cpp and is callable from Swift

- Added by PR #3065, merged 2025-05-12, first shipped in **v1.7.6** (2025-06-25). The current
  model is `ggml-silero-v6.2.0.bin`, about 864 KB, fetched by
  `./models/download-vad-model.sh`.
- The API is plain C in `whisper.h`, so Swift can call it the same way Nivi already calls
  `whisper_full`. On `whisper_full_params` it is three fields: `bool vad`,
  `const char * vad_model_path`, and `whisper_vad_params vad_params`. The parameters are
  `threshold` (0.5), `min_speech_duration_ms` (250), `min_silence_duration_ms` (100),
  `max_speech_duration_s`, `speech_pad_ms` (30) and `samples_overlap` (0.1).
- There is also a standalone set (`whisper_vad_init_from_file_with_params`,
  `whisper_vad_detect_speech`, `whisper_vad_detect_speech_no_reset`, `whisper_vad_reset_state`,
  `whisper_vad_segments_from_samples`, and getters for segment start and end in seconds). The
  `_no_reset` variant is specifically for streaming: it keeps the detector's internal state
  across calls.
- **Important gotcha for Nivi: `params.vad` is only handled inside `whisper_full()` and
  `whisper_full_parallel()`. `whisper_full_with_state()` ignores it entirely.** Open issue
  ggml-org/whisper.cpp#3402, with an unmerged fix in PR #3423. Nivi calls `whisper_full`,
  so this does not bite today, but it rules out the state-based parallel path in option 5b if
  VAD is also wanted.
- Segment timestamps are mapped back to the original timeline when VAD is on (PR #3173), so
  `whisper_full_get_segment_t0/t1` stay usable. Token-level timestamps are still wrong in some
  cases (open issue #3754, proposed fix #3764 closed without merging). Nivi only uses
  segment-level timestamps, so this is fine.
- Other open VAD bugs to be aware of: crashes or stale results when no speech is detected
  (issues #3595, #3918).

Cost estimate for adopting it: one small model file to add to `ModelStore` and the download
flow, three fields set on `whisper_full_params`, and a `withCString` for the path so the C
string outlives the call. That is a smaller job than writing a good detector by hand.

### The `audio_ctx` finding that corrects Part B

`whisper.h` files `audio_ctx` under `// [EXPERIMENTAL] speed-up techniques` with the warning
`// note: these can significantly reduce the quality of the output`. There is **no documented
safe minimum** and no lower bound check in the code. Values above 1500 are rejected.

But the one substantive measurement in the repo is more encouraging than that warning suggests.
Issue ggml-org/whisper.cpp#1855: a user ran 200 Common Voice clips averaging 5.7 seconds, with
`audio_ctx = (clip_seconds / 30) * 1500 + 128`. Total time went from 204 s to 60 s, about 3.4x
faster, and word error rate went from **20.06 to 19.2**, that is very slightly *better*, not
worse. This is a user report, not a maintainer benchmark, and no maintainer endorsed a minimum
value. Still, it is the best evidence available.

**So Part B's cause 2 is overstated and should be read as follows.** Scaling `audio_ctx` down
to match the audio you actually have appears close to free. The damage comes from setting it
*below* the audio you actually have, which truncates real speech.

That points at a concrete weakness in Nivi's current formula:

```swift
private var audioCtx: Int { max(256, 1500 * windowSeconds / 30) }
```

Two things about it.

1. **No slack.** The community formula adds `+ 128`. Nivi's has none, so the encoder context
   ends exactly at the nominal window length with nothing to spare.
2. **It is derived from the configured window, not the actual slice.** The comment at
   `StreamingTranscriber.swift` lines 46-49 already admits this: when `StreamWindow` lets the
   window run long on an overflowing final segment, "audio past the nominal length is not
   encoded at all". That is exactly the truncation case that issue #1855 says is the harmful
   one. It is self-correcting for the text (the final tail pass covers it at full context), but
   in a fast-finish batch mode there is no full-context pass to save it.

**Recommendation: change the formula to size the context to the slice actually being
transcribed, with slack.** Something like
`min(1500, max(256, 1500 * actualSliceSeconds / 30 + 128))`. This is a small, self-contained
improvement that helps overlay-live too, and it should be done before or alongside option 1.

One more constraint to record: `audio_ctx` overrides **do not work with the Core ML encoder**
(issues #1488, #2405), because Core ML has a fixed input shape. Nivi uses Metal
(`params.use_gpu = true` in `WhisperCppRecognizer.load()`), so this is fine today, but any
future move to a Core ML encoder would silently break every streaming path.

### Prompt carryover: the API exists, and so does the failure mode

`whisper_full_params` has all of it:

```c
bool no_context;              // default true
int  n_max_text_ctx;
const char * initial_prompt;  // whisper.cpp tokenizes this for you
bool carry_initial_prompt;    // pin the initial prompt to every 30s window
const whisper_token * prompt_tokens;
int  prompt_n_tokens;
```

A maximum of about 224 tokens is used (`whisper_n_text_ctx()/2`). `carry_initial_prompt` was
added in PR #3395, merged 2025-08-28. The PR itself states the trade-off in its own words:
it "may slightly reduce the model's ability to adapt dynamically to newly generated context
(can increase risk of repetitions if the prompt is long)".

The failure mode Part D warns about is documented, not hypothetical:

- Issue #1017, "Segments Repeating in a Loop when Using 'prompt_tokens'", open since 2023. The
  reporter says the looping "began happening after I started using `prompt_tokens` from a
  previous segment".
- Issue #3744, "Proposal: reduce repetition hallucinations in long-form decoding", opened
  2026-04-05, describes the loop precisely: a bad phrase gets fed back as history, gets
  repeated, and the output collapses.
- Issue #1724 covers hallucination on silence, which is the other half of the same problem.

Mitigations named across those threads: keep temperature fallback on, cap the prompt length,
and drop the carried context when a segment looks degenerate. Build all three into option 3.

### Parallel decoding: available, and the repo itself warns against it

`whisper_full_parallel(ctx, params, samples, n, n_processors)` exists. It creates extra
`whisper_state` objects against one context, so model weights are shared read-only while each
state gets its own scratch and its own key-value caches. The header comment is the honest
summary:

```
// It seems this approach can offer some speedup in some cases.
// However, the transcription accuracy can be worse at the beginning and end of each chunk.
```

On top of that: the chunk split is naive equal slices with no regard for silence; per-token
timestamps are wrong with more than one processor (issue #3726, fix PR #3766 closed unmerged);
prompt context does not cross the joins, so punctuation continuity is lost exactly at the
boundaries; and each extra state duplicates the cross key-value cache, which is sized by
`n_audio_ctx` and is not cheap for a large model on a Mac.

**This confirms option 5b's low ranking.** It buys a smaller slope, not a flat line, and it
brings back every boundary problem that chunking has, without chunking's benefit.

There is **no** newer incremental-decode or ring-buffer API in whisper.cpp. The only
streaming-specific additions are the VAD `_no_reset` / `reset_state` pair.

### WhisperKit: independent confirmation that Nivi's design is the right one

WhisperKit is now a module inside `argmaxinc/argmax-oss-swift` (the old `argmaxinc/WhisperKit`
repo was renamed; old raw links 404).

"Eager mode" is not part of the library. It lives in the demo app,
`Examples/WhisperAX/WhisperAX/Views/ContentView.swift`. What it does:

- Keeps `confirmedText` and `hypothesisText` separate. Only confirmed text is treated as final.
- Confirms by **local agreement**: it takes the longest common prefix of the previous
  hypothesis and the current one, and promotes it. The setting is
  `tokenConfirmationsNeeded`, default 2, adjustable 1 to 10.
- Carries context forward explicitly, with two things at once:
  `streamOptions.clipTimestamps = [lastAgreedSeconds]` moves the audio cursor past what is
  already agreed, and `streamOptions.prefixTokens = lastAgreedTokens` feeds the agreed tokens
  back into the decoder.
- Sets `chunkingStrategy = .none` in eager mode, and requires word timestamps.
- On stop it does `confirmedText += hypothesisText`. The tail hypothesis is simply promoted.

**This is the same design Nivi already has**, arrived at independently.
`StablePrefixTracker` with `stabilityPasses = 2` is local agreement with
`tokenConfirmationsNeeded = 2`. `StreamWindow.windowStartSample` is `clipTimestamps`. The one
thing WhisperKit has that Nivi does not is `prefixTokens`, which is exactly option 3.

WhisperKit's chunking options are only `.none` and `.vad` (`ChunkingStrategy` in
`Sources/WhisperKit/Core/Models.swift`). There is no fixed-timer chunking strategy at all. The
demo app additionally gates streaming on a simple energy detector before running inference:
`silenceThreshold = 0.3` measured against `audioProcessor.relativeEnergy`, with the baseline
set by the quietest 100 ms in the previous 2 seconds. If the tail is silent it sleeps 100 ms
instead of transcribing. **That is a cheap win Nivi could copy in an afternoon, with no VAD
model at all:** skip a streaming pass when the recent audio is silent.

**Latency numbers, from the paper** "WhisperKit: On-device Real-time ASR with Billion-Scale
Transformers" (Orhon et al., ICML 2025 workshop, arXiv 2507.10860), measured on a MacBook Pro
M3 Max using the Neural Engine:

- Headline: 0.46 s latency at 2.2% word error rate.
- Per-word latency on the **hypothesis** stream: about 0.45 s.
- Per-word latency on the **confirmed** stream: about **1.7 s**, and this is the same for
  WhisperKit, Fireworks and Deepgram.

That last number is the one that matters here. **Waiting for confirmation costs roughly 1.2
extra seconds** over showing the raw guess. Nivi's `StablePrefixTracker` pays the same
price, which is why it is used for in-app-live typing and should not be used for
`batchFastFinish` (which needs no confirmation, since nothing is shown before the paste).

No per-device or per-model latency table from Argmax was found. Their true low-latency
WebSocket streaming is now behind a paid Pro SDK.

### What Spokenly actually changed: the evidence points away from chunking

Spokenly publishes a real, detailed changelog at `https://spokenly.app/releases/macos`.
Relevant entries, quoted:

| Version / date | Entry |
|---|---|
| 2.28.0, 2026-08-16 | "New local model: Cohere Transcribe Q4 with top accuracy for 14 languages" |
| 2.28.0, 2026-08-16 | "Quiet microphone audio is boosted automatically for local models" |
| 2.27.x, 2026-08-01 | "Scribe v2 realtime keeping the last words when you stop right after speaking" |
| 2.26.0, 2026-07-24 | "See live transcription as you speak with ElevenLabs Scribe" |
| 2.25.0, 2026-07-15 | "**Customize Parakeet Unified latency for speed and energy use**" |
| 2.23.x, late 2026-06 | "**Added NVIDIA Parakeet Unified, a new fully on-device transcription model**" |
| 2.22.0, 2026-06-04 | "New on-device Nemotron 3.5 model for multilingual dictation" |
| 2.21.2, 2026-05-21 | "Local models now produce more reliable punctuation at end of dictation" |
| 2.20.0, 2026-05-09 | "New: Deepgram Flux model for low-latency streaming transcription" |
| 2.18.11, 2026-03-31 | "Real-time transcription with Apple Speech Analyzer" |

Their engines, from their own homepage: local Whisper and Parakeet, plus bring-your-own keys
for OpenAI, Deepgram, Groq, Anthropic and Google. The changelog adds Apple Speech Analyzer,
ElevenLabs Scribe, Deepgram Flux, Microsoft MAI-Transcribe, Nemotron 3.5 and Cohere Transcribe.
It is a multi-engine app.

**Honest conclusion, stated plainly: there is no public evidence that Spokenly does chunked
local transcription during recording.** Every "realtime", "live" or "streaming" entry in their
changelog names a cloud engine or Apple's system engine, never local Whisper or local Parakeet.

**What the evidence does show is engine work.** They added NVIDIA Parakeet as a fully on-device
model in June 2026, and one month later added a control to "customize Parakeet Unified latency
for speed and energy use". That is a speed dial for a local engine, shipped exactly in the
period being described.

Two caveats on this section. First, the observation was that the model was not changed. If that
is right, an engine switch is a weaker explanation, though an app can change the runtime under
a name the user sees without saying so. Second, the same page returned slightly different
version numbers and dates on two fetches for the Parakeet Unified entry (2.23.0 / Jun 18 versus
2.23.3 / Jun 28). The text is stable, the numbering is not, so do not quote a version number
from this table without re-checking it.

**Do not treat "Spokenly does chunking" as established.** It is a reasonable guess about a
plausible technique. It is not a documented fact.

### Other apps

**Superwhisper** (`superwhisper.com/changelog`) is the closest public example of the pattern:

- v2.9.0, 2026-01-23: "Introducing Parakeet Realtime transcription offline"
- v2.10.0, 2026-02-23: "New realtime streaming UI with live transcription display"
- v2.16.2, 2026-07-06: "Faster pasting — time to paste latency reduced by 300ms"
- v2.2.0, 2025-07-24: "Parakeet is now 2x faster for long recordings"

So Superwhisper does offline realtime with Parakeet, and separately worked on paste latency.
Again the speed story is largely an engine story.

**MacWhisper**: supports Whisper and Parakeet locally and has real-time dictation, but no
primary-source changelog entry was found describing streaming with a held-back paste.

**VoiceInk, Wispr Flow, Aqua Voice**: nothing usable. The claims found were on competitors'
comparison pages or the vendors' own marketing, not technical documentation. No evidence found
either way.

### Parakeet numbers, because they change the ranking

Measured, from FluidAudio's benchmark document
(`github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md`), on an M4 Pro
with 48 GB running macOS Tahoe 26.0, using Parakeet compiled to Core ML on the Neural Engine:

- `parakeet-tdt-0.6b-v3` on LibriSpeech test-clean: word error rate 2.5%, and
  **139.6x to 155.6x real time** (19452.5 seconds of audio processed in 125.0 seconds).
- FLEURS multilingual average: word error rate 14.7%, around 210x real time across 24 languages.
- Cold start is not free: the first Core ML compile took 3361 ms for the encoder, dropping to
  162 ms once warm.

For comparison, whisper large-v3-turbo through WhisperKit on an M4 was reported at about 18x
real time by a third-party blog. That is a secondary source, so treat it as rough. whisper.cpp
has no official real-time-factor table at all; the best end-to-end Apple Silicon figure found
in its issue tracker is about 11 to 12x real time for `medium.en` on a base M4.

**So Parakeet on the Neural Engine is plausibly close to an order of magnitude faster than
whisper on the same machine.** In the language of Part B, it lowers `r` from roughly 0.06 to
roughly 0.007. At that speed a 60-second dictation finishes in well under half a second with no
chunking at all, no accuracy trade, and less battery than either option 1a or 1b.

That is a bigger lever than anything else in this document. It is also a much bigger piece of
work, and it needs its own Hebrew evaluation, since the FLEURS multilingual word error rate of
14.7% is a long way from the 2.5% English number. There is already a document on it at
`docs/parakeet/2026-08-24-parakeet-integration-options.md`.

---

## Part D: options for Nivi, ranked

Reference numbers used below: `r = 0.1` (seconds of compute per second of audio), which is a
plausible figure for a turbo-class whisper model on Apple Silicon with Metal. Measure the real
value first from the two log lines in `DictationController.swift` (line 309 prints the recording
length, line 341 prints the inference time) before committing to any of these numbers.

### Ranked summary

| # | Option | Finish latency | Accuracy cost | Battery | Effort | Rank |
|---|---|---|---|---|---|---|
| 5a | Warm the model at recording start | Removes a ~1s cold-load spike | None | None | 1 hour | **Free, do it now** |
| 5d | Size `audio_ctx` to the real slice, with slack | Unchanged | Recovers a real loss | None | 2 hours | **Free, do it now** |
| 1a | Fast-finish batch reusing the current window loop | ~1s, constant | Medium | 6-7x | Half a day | **Main recommendation** |
| 5e | Skip a streaming pass when the tail is silent | Slightly better | None | Meaningful saving | Half a day | Cheap, do with 1a |
| 1b | Fast-finish batch, forward-only chunking | ~0.4s average, constant | Medium | ~1.3x | 1-2 days | Do second |
| 3 | Prompt carryover between chunks | Unchanged | Recovers punctuation and style | None | 1 day | Do with 1b |
| 4 | Per-profile quality dial | n/a | n/a | n/a | Included in 1a | Comes free with 1a |
| 2 | Voice activity detection for chunk boundaries | Better still | Recovers boundary errors | Small saving | 2-3 days | Later, if 1b is not clean enough |
| 5c | Switch engine to Parakeet | ~0.4s for a 60s clip, no chunking | Unknown for Hebrew, must be measured | Lower | Large | **Biggest lever, separate project** |
| 5b | Parallel overlapping chunks at stop only | Smaller slope, still grows with N | Same boundary problems, plus broken timestamps | High peak | 3+ days | Not worth it |

---

### Option 1a: fast-finish batch, reusing the loop that already exists

**The idea.** Run the existing `StreamingTranscriber` during a batch recording, but show
nothing and type nothing. At stop, `stopAndTranscribe` already knows how to stitch
`frozenText` with a re-transcribed tail. Paste the result as one piece, exactly as batch
mode does today.

**Why this is first.** Almost all of it is already written and already in daily use by
overlay-live. The bounded final pass at `DictationController.swift` lines 322-337 is the fast
finish. It is only unreachable from batch mode.

**What changes.**

1. `Sources/NiviCore/Settings.swift`, `InsertionMode`: add a case.
   ```swift
   case batch, batchFastFinish, overlayLive, inAppLive
   ```
   with a `displayName` such as `"Batch, fast finish (listens while you speak)"`.
   The enum is `String`-backed and `Codable`, so profiles saved today still decode.
   `ProfilesSection.swift` line 133 builds its picker from `InsertionMode.allCases`, so the
   new option appears in Preferences with no UI work at all.

2. Add one computed property next to the enum, so no call site has to list modes by hand:
   ```swift
   public var streamsDuringRecording: Bool { self != .batch }
   ```

3. `DictationController.swift` line 208: replace
   `if profile?.mode != .batch, let profile {` with a check on
   `profile.mode.streamsDuringRecording`.

4. `DictationController.swift` `handleStreamingUpdate` (lines 270-281): add
   `case .batchFastFinish: break`. The text is deliberately held back. The overlay keeps
   showing the ordinary recording card with the level meter, so nothing looks different to
   the user until the paste lands.

5. `DictationController.swift` line 348: change `case .batch, .overlayLive:` to
   `case .batch, .batchFastFinish, .overlayLive:`. Same `inserter.insert(...)` call, same
   `autoPaste`, `copyOnly` and `excludeFromHistory` handling. Nothing about clipboard
   behaviour changes.

That is the whole change. Roughly 10 lines across two files.

**Expected finish latency.** The leftover is the un-frozen window, up to
`streamingWindowSeconds` (default 10) plus any overflow from a long final segment. At
`r = 0.1` that is around 1 second, and it does not grow with recording length. Compared with
today, a 60-second Hebrew dictation goes from about 6 seconds of waiting to about 1.
A 180-second one goes from about 18 seconds to about 1.

**Expected accuracy cost.** Medium, and larger in Hebrew than in English. See the five causes
in Part B. Note one mitigating detail: the frozen text here comes from passes that saw a
10-second window, and each word was seen several times with growing right-hand context before
it froze, because the loop re-transcribes. So 1a's frozen text is actually *better* than a
naive one-shot chunker's. That is the upside of the extra battery it burns.

**Risk.** Low. The stitching path is already exercised every day by overlay-live. The main new
risk is the "window is not advancing" failure that `StreamingTranscriber.swift` lines 109-114
already detects and logs: if whisper keeps returning a single segment, nothing freezes,
`windowStartSample` stays 0, and `stopAndTranscribe` falls back to the whole-buffer pass. That
is a correct fallback. It means the feature silently does nothing rather than breaking, which
is the right failure. Watch the log for that message during testing.

**Effort.** Half a day including manual testing on a long Hebrew dictation.

---

### Option 1b: forward-only chunking, so it does not cost battery

**The idea.** Stop re-transcribing the same audio over and over. Handle each piece of audio
once, commit it, move on. This is the shape a fast finish actually wants, because there is no
live preview to correct.

**Why it matters.** Option 1a runs inference about 65% of the time you speak and transcribes
each second of audio 6 or 7 times (Part B). On a laptop that is fans, heat and battery for no
visible benefit, since nothing is displayed. Forward-only brings total compute back down to
roughly what batch mode costs today, just spread across the recording instead of piled up at
the end.

**What changes.**

1. `StreamingTranscriber` gains a way to say "freeze everything you can, every pass". The
   freeze logic in `StreamWindow` already does this when `maxWindowSamples` is near zero: the
   loop at lines 41-44 freezes every segment except the last. So no change to `StreamWindow`
   itself. Add an init parameter, for example `freezeWindowSeconds: Int`, used only for
   `maxWindowSamples`, while the existing `windowSeconds` keeps driving `audioCtx`.
   For forward-only, pass `freezeWindowSeconds: 0`.

2. Change the pacing. Today the loop sleeps `intervalMs` (500ms) between passes. Forward-only
   should wait until there is a useful amount of new audio, around 6 to 10 seconds, before
   running a pass. Under a few seconds whisper has too little to work with, the padding
   dominates, and per-call overhead eats the saving. Add a "minimum new audio before a pass"
   check in `runPass()`: if `samples.count - windowStartSample` is below the threshold,
   return without transcribing.

3. `audioCtx` should be sized to the chunk, not to the old window:
   `max(256, 1500 * chunkSeconds / 30)`. With `chunkSeconds = 8` that is 400. Keep the 256
   floor. Do not go below it.

**Expected finish latency.** Leftover at stop is 0 to one chunk. With an 8-second chunk and
`r = 0.1`, that is 0 to 0.8 seconds, about 0.4 on average. Still constant in N.

**Expected accuracy cost.** Slightly worse than 1a, because each word is now decided once
rather than firming up over several passes. Still cut on whisper's own segment boundaries,
so the cut points are still at natural pauses. Combine with option 3 to get the punctuation
back.

**Risk.** Medium. Two things to watch. First, the single-segment stall: with a small chunk and
a low `audio_ctx`, whisper is more likely to return one long segment, which freezes nothing.
The existing detector at `StreamingTranscriber.swift` lines 109-114 covers this; keep it and
make sure the threshold still makes sense with the new sizes. Second, a chunk that is all
silence returns no segments, and `StreamWindow.advance` correctly refuses to freeze on an
empty pass. That means a long pause makes the leftover grow past one chunk. Acceptable, and
option 2 addresses it properly.

**Effort.** 1 to 2 days, mostly tuning `chunkSeconds` and `audioCtx` against real Hebrew
recordings and comparing the output against a full batch pass on the same audio.

**Suggested way to measure it.** Record 5 to 10 real Hebrew dictations to disk once, then run
each of them through batch, 1a and 1b offline and diff the text. Do not judge this by feel.
The whole question is a trade of accuracy against latency, and you cannot trade what you
have not measured.

---

### Option 5a: warm the model when recording starts, not when it stops

**The idea.** `idleUnloadSeconds` defaults to 300, so after five minutes of not dictating the
model is dropped from memory (`DictationController.swift` lines 396-407). The next dictation
pays the load. In batch mode that load lands inside `stopAndTranscribe`, on top of the
transcription, so the first dictation after a break feels much slower than the rest.

**What changes.** In `startRecording()`, kick off
`recognizerCache.recognizer(id:modelPath:)` for the active profile's model in a detached task,
alongside `cancelIdleUnload()`. The result is discarded; the point is only that the load
overlaps the speaking instead of the waiting. `RecognizerCache` already returns the same
instance to the later call, so there is no double load. `startStreaming` already does exactly
this call, so for streaming modes it is already covered. This is only about plain batch.

**Latency.** Removes roughly one second from the first dictation after an idle gap. Does
nothing for the rest.

**Risk.** Very low. **Effort.** About an hour. Do it whether or not you do anything else here.

---

### Option 5d: size `audio_ctx` to the audio you actually have

**The idea.** The current formula is:

```swift
private var audioCtx: Int { max(256, 1500 * windowSeconds / 30) }
```

Two problems, both explained with evidence in Part C.

1. It has no slack. The only measured guidance in the whisper.cpp issue tracker (#1855) uses
   `(clip_seconds / 30) * 1500 + 128` and reports **no** accuracy loss doing so, on 200 clips.
   Nivi's formula ends the encoder context exactly at the nominal window with nothing spare.
2. It is derived from the *configured* window, not the slice actually being transcribed. The
   comment at `StreamingTranscriber.swift` lines 46-49 already admits that when the window runs
   long, "audio past the nominal length is not encoded at all". Real speech is cut out of the
   encoder before it is ever seen. In overlay-live and in-app-live this is covered by the final
   full-context tail pass. In a fast-finish batch mode there is no such pass, so the loss is
   permanent.

**What changes.** Compute the context from the slice that `runPass()` is about to send, not
from `windowSeconds`, and add the slack:

```swift
// Roughly: min(1500, max(256, 1500 * sliceSeconds / 30 + 128))
```

This is a handful of lines inside `StreamingTranscriber.runPass()`.

**Latency.** Unchanged, or a touch slower on overflowing windows, because the context is now
sometimes larger. That is the correct trade: it was only faster because it was dropping audio.

**Accuracy.** Recovers a real loss that exists today. Helps overlay-live and in-app-live too,
not just the new mode.

**Risk.** Low. Clamp at 1500, or `whisper_full` rejects the call with
`audio_ctx is larger than the maximum allowed`. Keep the 256 floor.

**One constraint to record while you are here.** `audio_ctx` overrides do not work with the
Core ML encoder (whisper.cpp issues #1488, #2405), because Core ML has a fixed input shape.
Nivi uses Metal, so this is fine today. If a Core ML encoder is ever added, every streaming
path silently loses its speed-up. Worth a comment in the code.

**Effort.** About two hours.

---

### Option 5e: do not run a pass when nobody is speaking

**The idea.** Before running a streaming pass, check whether the recent audio is loud enough to
be speech. If it is silence, sleep and try again. No transcription, no GPU, no battery.

This is copied directly from WhisperKit's demo app, which uses a threshold of `0.3` against a
relative energy measure whose baseline is "the quietest 100 ms in the previous 2 seconds", and
sleeps 100 ms when the tail is quiet. It needs no VAD model and no new dependency.

**Why it is worth doing even though option 2 exists.** It is a fraction of the work, it uses
audio Nivi already has, and it removes the largest single waste in option 1a: re-running a
10-second window over and over while the user pauses to think. It also reduces whisper's
tendency to hallucinate text out of silence (whisper.cpp issue #1724).

**What changes.** `AudioRecorder` already computes a level, since `recorder.onLevel` drives the
overlay meter (`DictationController.swift` line 56). Expose a rolling recent-energy value, and
have `StreamingTranscriber.runPass()` return early when it is below threshold.

**Risk.** Low, and it fails safe: a threshold set too high just means fewer passes, and the
final tail pass still covers everything. Watch for a quiet speaker being treated as silence;
the relative baseline that WhisperKit uses is specifically designed to handle that.

**Effort.** Half a day. Do it in the same change as option 1a.

---

### Option 3: carry the prompt across chunks

**The idea.** whisper accepts text that comes *before* the audio it is about to transcribe,
and uses it to set style, spelling and punctuation. Feeding the tail of the already-frozen
text into the next chunk makes the pieces read as one document instead of five separate ones.

**What changes.** `SpeechRecognizer.transcribeSegments` gains a prompt parameter, and
`WhisperCppRecognizer` sets `params.initial_prompt` on `whisper_full_params` before calling
`whisper_full`. whisper.cpp tokenizes the string for you, so `prompt_tokens` is not needed. It
uses at most about 224 tokens (`whisper_n_text_ctx() / 2`).
`StreamingTranscriber.runPass()` passes the last 100 to 200 characters of
`window.frozenText`. Keep it short: a long prompt costs decoder time and raises the chance of
the model repeating the prompt back.

Do **not** use `carry_initial_prompt`. Its own pull request (whisper.cpp #3395) says it "may
slightly reduce the model's ability to adapt dynamically to newly generated context (can
increase risk of repetitions if the prompt is long)". Nivi wants the opposite: a prompt that
moves forward with the text.

WhisperKit does exactly this, which is good independent evidence the idea works. Its eager mode
sets `streamOptions.prefixTokens = lastAgreedTokens` on every iteration.

**What it fixes.** Cause 4 in Part B, the missing whole-utterance punctuation pass. It also
helps with consistent spelling of names and terms across chunk boundaries, which in Hebrew is
a real problem because the same name can be spelled several ways.

**What it does not fix.** Causes 1, 2 and 3. A prompt is left-hand context. It cannot give a
word the future context it is missing.

**Risk.** Medium, and the failure is documented rather than theoretical. whisper.cpp issue
#1017, "Segments Repeating in a Loop when Using 'prompt_tokens'", has been open since 2023, and
the reporter states the looping "began happening after I started using `prompt_tokens` from a
previous segment". Issue #3744 (opened 2026-04-05) describes the feedback loop precisely: a bad
phrase is fed back as history, gets repeated, and the output collapses. Issue #1724 covers the
related hallucination-on-silence problem.

Build all three of the mitigations named in those threads: keep temperature fallback enabled,
cap the prompt length hard, and drop the carried prompt for a pass whose output starts with a
long verbatim copy of it. Test on a recording with long pauses, which is where loops start.
Option 5e (skip silent passes) also reduces this risk directly.

**Effort.** About a day, most of it on the guard and the testing.

---

### Option 2: cut chunks on silence, not on a clock

**The idea.** Instead of cutting after N seconds whatever is happening, wait for the speaker
to pause and cut there. A pause is a place where cutting costs nothing, because there is no
word straddling the cut and the missing right-hand context is silence anyway. Detecting
whether a piece of audio is speech or silence is called voice activity detection, usually
shortened to VAD.

**Where Nivi stands.** It already gets most of this benefit without any VAD, because
`StreamWindow` freezes on whisper's own segment boundaries and whisper puts those at natural
pauses. That is why this is ranked below options 1 and 3: the cheap 80% is already done.

**What VAD adds on top.** Two real things. First, it lets you decide *when to run a pass*
rather than only *where to cut the result*: run a chunk as soon as the speaker pauses, so the
leftover at stop is usually zero because the user almost always stops speaking before they
stop recording. Second, it lets you skip silence entirely, so a recording with long pauses
costs less compute and is less likely to produce whisper's silence hallucinations.

**What changes.** Part C confirmed whisper.cpp has proper Silero-based detection built in
since v1.7.6 (June 2025), and it is callable from Swift because it is plain C in `whisper.h`.
Three fields on `whisper_full_params`: `vad`, `vad_model_path`, `vad_params`. The tuning knobs
are `threshold` (0.5), `min_speech_duration_ms` (250), `min_silence_duration_ms` (100),
`speech_pad_ms` (30) and `samples_overlap` (0.1). The model file is `ggml-silero-v6.2.0.bin`,
about 864 KB, fetched by `models/download-vad-model.sh`.

There is also a standalone set of functions for detecting speech without transcribing:
`whisper_vad_init_from_file_with_params`, `whisper_vad_detect_speech_no_reset` (the `_no_reset`
variant is made for streaming, it keeps state across calls), `whisper_vad_reset_state`, and
`whisper_vad_segments_from_samples` with getters for each segment's start and end in seconds.
That is the route to use if the goal is "tell me when he paused so I can cut there", separate
from transcription.

Work needed: add the small model to `ModelStore` and the download flow, use `withCString` so
the path outlives the C call, and set the three parameters. Smaller than writing a good
detector by hand.

**Gotchas found in Part C, worth writing down before starting.**

- `params.vad` is handled by `whisper_full()` and `whisper_full_parallel()` only.
  **`whisper_full_with_state()` ignores it** (open issue whisper.cpp#3402, fix PR #3423 not
  merged). Nivi calls `whisper_full`, so this is fine, but it closes the door on combining
  VAD with option 5b.
- Segment-level timestamps are correctly mapped back to the original timeline (PR #3173), so
  `whisper_full_get_segment_t0/t1` still work and `StreamWindow` still functions. Token-level
  timestamps are still wrong in some cases (issue #3754). Nivi only uses segment-level, so
  this does not matter.
- Open bugs around no-speech results causing crashes or stale output (issues #3595, #3918).
  Handle an empty VAD result explicitly.
- No documentation was found on how VAD interacts with an `audio_ctx` override. In the code
  they are independent (VAD only reshapes the buffer before the normal pipeline), but there is
  no evidence it is tested together. Do not assume.

**Do option 5e first.** It gives most of the battery benefit for a fraction of the work, with
no model to ship. Only reach for full VAD if chunk edges are still visibly wrong after
options 1b and 3.

**Risk.** Medium. Thresholds are fiddly and depend on the microphone and the room. Getting them
wrong means either chunks that never fire or chunks that fire mid-word anyway.

**Effort.** 2 to 3 days, including adding the VAD model to `ModelStore` and the download flow.

---

### Option 4: a quality dial the user can pick per profile

This is not a separate piece of work. Adding `batchFastFinish` as a fourth `InsertionMode`
**is** the dial, because profiles already carry a mode and Preferences already renders every
case. The user gets:

- **`batch`** = best accuracy. whisper sees the whole recording at full context. Wait is
  proportional to length.
- **`batchFastFinish`** = instant finish. Wait is about a second regardless of length.
  Slightly lower accuracy.

That is a real choice presented in the user's own words at the place he already goes to
configure a profile. He can keep his main Hebrew profile on `batch` while he evaluates, and
have a second Hebrew profile on `batchFastFinish` bound to a different hotkey, and compare
them on the same sentences.

**Recommendation on the default.** Do not change the default. Ship `batchFastFinish` as an
option, use it yourself for a week on real Hebrew, and only then decide whether it deserves
to be the default.

One extra label worth adding while you are in there: the two names should say what they cost,
not what they do internally. Something like "Batch, best accuracy" and "Batch, fast finish".

---

### Option 5b: split the clip and transcribe the pieces in parallel at stop

**The idea.** Do not stream at all. At stop, cut the recording into K overlapping pieces and
transcribe them at the same time.

**The API exists.** `whisper_full_parallel(ctx, params, samples, n, n_processors)` creates
extra `whisper_state` objects against one context, so model weights are shared read-only while
each state gets its own scratch and its own key-value caches. That is the sanctioned pattern.

**But whisper.cpp's own header comment warns against it:**

> It seems this approach can offer some speedup in some cases.
> However, the transcription accuracy can be worse at the beginning and end of each chunk.

On top of that, Part C found: the chunk split is naive equal slices with no regard for silence;
per-token timestamps are wrong with more than one processor (issue #3726, fix PR #3766 closed
unmerged); prompt context does not cross the joins, so punctuation continuity is lost exactly
at the boundaries; VAD is not applied per state; and each extra state duplicates the cross
key-value cache, which is sized by `n_audio_ctx` and is not cheap for a large model on a Mac.

There is also a Nivi-side cost. `WhisperCppRecognizer` serializes every call onto a single
`DispatchQueue` on purpose, and that serialization is load-bearing for the `whisper_free`
safety described in the comments at lines 131-136. Going parallel means reworking that.

**And even if all of it worked perfectly, the finish is still proportional to N**, just with a
smaller constant. Options 1a and 1b make it flat. Flat beats a smaller slope. You would take on
every boundary problem that chunking has, and not get chunking's actual benefit.

**Verdict.** Not worth it. Skip.

---

### Option 5c: change engine

This started as a footnote and the research promoted it. **It is the biggest single lever in
this document, and it is also the best-supported explanation of what the competitor actually
did.**

The measured numbers, from Part C. NVIDIA Parakeet compiled to Core ML on the Neural Engine, on
an M4 Pro, runs at roughly **140 to 155 times real time** on English (FluidAudio's benchmark
document, 19452.5 seconds of audio in 125.0 seconds, word error rate 2.5%). whisper
large-v3-turbo on comparable hardware is roughly 15 to 20 times real time.

In the language of Part B, that takes `r` from about 0.06 down to about 0.007. A 60-second
dictation would finish in **under half a second with no chunking at all**: no accuracy trade,
no extra battery, no new failure modes at chunk boundaries. It simply removes the problem
instead of trading against it.

**What the evidence says about the competitor.** Spokenly added "NVIDIA Parakeet Unified, a
new fully on-device transcription model" in June 2026, and one month later added "Customize
Parakeet Unified latency for speed and energy use". There is no changelog entry anywhere
describing chunked local transcription. Superwhisper's story is the same shape: "Introducing
Parakeet Realtime transcription offline" (January 2026) and "Parakeet is now 2x faster for
long recordings" (July 2025). Two competitors, same answer, and it is an engine answer.

**The honest catch, and it is a big one for this user.** All the impressive numbers are
English. Parakeet's multilingual FLEURS average is a word error rate of 14.7% against 2.5% for
English. Nothing was found about Hebrew specifically. Hebrew is exactly the case where a
model's training data thins out. **Do not adopt Parakeet on the English numbers.** Record ten
real Hebrew dictations and measure both engines on the same audio before deciding anything.

There is already a document on this at
`docs/parakeet/2026-08-24-parakeet-integration-options.md`.

**The two options are not alternatives.** A faster engine makes chunking cheaper too, and
chunking makes a fast engine feel instant. They multiply. But if Parakeet turns out to be good
enough in Hebrew, chunking stops being worth its accuracy cost, and options 1 to 3 should be
dropped rather than shipped. That is a reason to measure Parakeet's Hebrew accuracy **early**,
before investing in options 1b, 2 and 3.

---

### Recommended sequence

**This week, cheap and unconditional:**

1. **Option 5a**, warm the model at recording start. One hour. Free win regardless of
   everything else.
2. **Option 5d**, size `audio_ctx` to the real slice with `+128` slack. Two hours. Fixes a real
   loss that exists in overlay-live and in-app-live today.
3. **Measure `r`.** Read the two existing log lines in `DictationController.swift` over a week
   of real dictations. Every number in this document is built on `r = 0.1`. If the real value
   is 0.03, batch mode is already fine and none of this is urgent. If it is 0.3, it is worse
   than described.

**Then the main change:**

4. **Option 1a**, `batchFastFinish` as a fourth insertion mode reusing the existing loop.
   Half a day, about ten lines across two files. This is the whole user-visible win.
   **Ship it as an option, not a default.**
5. **Option 5e**, skip a streaming pass when the tail is silent. Half a day, same change.
   Cuts the battery cost of 1a and reduces silence hallucination.
6. **Use it for a week on real Hebrew.** Keep the main Hebrew profile on `batch`, put a second
   Hebrew profile on `batchFastFinish` with a different hotkey, and say the same sentences into
   both. Save the recordings and diff the text. Do not judge this by feel.

**In parallel, and arguably more important:**

7. **Measure Parakeet on Hebrew** (option 5c). This is the fork in the road. If Parakeet is
   good enough in Hebrew, its roughly 10x speed advantage removes the latency problem outright
   and steps 8 to 10 below should never be built. If it is not good enough in Hebrew, whisper
   stays and chunking is the only route.

**Only if step 6 shows a specific problem and step 7 rules Parakeet out:**

8. **Option 3**, prompt carryover, if punctuation and style are the main complaint.
9. **Option 1b**, forward-only chunking, if battery or fan noise is the main complaint.
10. **Option 2**, full Silero VAD, only if chunk edges are still visibly wrong after 8 and 9.

**Never:** option 5b, parallel chunks at stop.

---

## Appendix: things this document is not sure about

Listed so nobody later mistakes a guess for a finding.

- **`r = 0.1` is an assumption, not a measurement.** Everything downstream of it is arithmetic
  on a guess. whisper.cpp publishes no official real-time-factor table for Apple Silicon. The
  best end-to-end figure found in its issue tracker is about 11 to 12 times real time for
  `medium.en` on a base M4. Measure Nivi's own number first.
- **There is no public evidence that Spokenly does local chunked transcription.** Their
  changelog is real and detailed, and every realtime entry in it names a cloud engine or
  Apple's system engine. The chunking idea is a reasonable guess about a plausible technique.
  It is not a documented fact, and this document does not treat it as one.
- **Spokenly's changelog version numbers are unstable.** Two fetches of the same page returned
  different version numbers and dates for the Parakeet Unified entry. The entry text was
  stable. Re-check before quoting a version.
- **No safe minimum for `audio_ctx` is documented anywhere.** The `+128` slack formula comes
  from one user report on 200 English clips (whisper.cpp issue #1855), not from a maintainer
  benchmark. It is the best evidence available, which is not the same as good evidence.
- **Nothing was found about Parakeet's Hebrew accuracy.** The 2.5% word error rate is English.
  The multilingual FLEURS average is 14.7%. Hebrew was not broken out.
- **No documentation was found on whisper.cpp's VAD interacting with an `audio_ctx` override.**
  They look independent in the code. There is no evidence they are tested together.
- **The claim that Hebrew suffers more than English from lost context is reasoning, not
  measurement.** It follows from Hebrew being written without vowel marks and from whisper
  having less Hebrew training data. No benchmark was found that measures it. This is exactly
  why step 6 above says to record real Hebrew and diff the output.

