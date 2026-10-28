# Fast finish: the implementation plan

Date: 2026-10-26
Status: plan only. No code changed.
Design: [2026-08-24-fast-finish-transcription.md](2026-08-24-fast-finish-transcription.md)

## What this plan is for

The goal: when you release the hotkey, the text lands in about one second, however
long you spoke.

The design picked a way to get there. Transcribe each piece of audio once, while
the user is still speaking, and never go back to it. The design calls this
"forward-only chunking" (option 1b). At stop, only the last unfinished piece is
left to do.

This plan turns that design into steps. Each step is one PR. Each step can be
turned off or reverted on its own.

## Read this first: the log says the finish is already fast

The design was written in August, when no streaming code was on `main`. A lot has
shipped since then. And the log on this Mac answers some of its open questions.

**What already shipped from the design:**

| Design option | State today | Where |
|---|---|---|
| 1a: `batchFastFinish` mode, reusing the live loop | Shipped | `Sources/NiviCore/Settings.swift:3-21`, `Sources/Nivi/DictationController.swift:326-330` |
| 5d: size `audio_ctx` to the real slice, plus 128 slack | Shipped | `Sources/NiviCore/AudioContext.swift:50-56`, used at `Sources/Nivi/StreamingTranscriber.swift:90-91` |
| Metal multiple-of-4 rule | Shipped | `Sources/NiviCore/AudioContext.swift:30`, re-checked at `Sources/Nivi/WhisperCppRecognizer.swift:109-114` |
| 5a: warm the model when recording starts | Done for every streaming mode by `startStreaming` (`DictationController.swift:266-272`). Plain batch still loads at stop | |
| 1b: forward-only chunking | Not built | |
| 5e: skip a pass when the audio is silent | Not built | |
| 3: carry the prompt across chunks | Not built | |

**What the log says.** `~/Library/Logs/Nivi/nivi.log` holds 470 finished
dictations since 2026-08-27. Step 0 explains how to read it. The short version:

- With the Hebrew model (`ivrit-large-v3-turbo`) in a streaming mode, the wait
  after stop is already about **0.8 s on average**, and it does not grow with
  length. 125 dictations, longest 92 s, worst wait 3.74 s.
- With `whisper-small-en` in plain batch, `r` is about **0.015**. A 122 s
  dictation finished in 1.6 s.
- The "6 s for 60 s, 18 s for 3 min" figures in the design were arithmetic on a
  guessed `r = 0.1`. Nobody has measured plain batch with the Hebrew model.

So today's `batchFastFinish` already meets the one-second goal in daily use.
What forward-only adds is mostly **less work**, not a faster finish. The current
loop transcribes each second of audio about 6 to 7 times, and forward-only
transcribes it about 1.3 times. That means less battery, less heat, and a GPU that
is free sooner. It also puts a lower ceiling on the leftover tail.

There is one real speed gain left, and it is not chunking. The tail pass always
runs whisper's full 30-second encoder, even on half a second of audio. That sets
a floor of about 0.6 s on every finish. Step 5 deals with it.

**The log also shows a live reliability bug.** It loses dictations, and it hits
the streaming modes hardest. Step 1 fixes it before anything else, because the
owner puts reliability ahead of accuracy work (see `docs/decisions.md`,
"Reliability comes before accuracy work").

## The steps at a glance

| Step | What changes | Changes app behaviour? | How to turn it off |
|---|---|---|---|
| 0 | Measure `r` from the log | No, read only | n/a |
| 1 | Fix the model cache race, and log what each pass costs | Yes, bug fix only | `git revert` |
| 2 | A small replay tool that checks accuracy and finish time | No, tools only | n/a |
| Gate | Decide from the numbers whether to go on | | |
| 3 | Forward-only rules in NiviCore, and the setting that picks them | No | n/a |
| 4 | `batchFastFinish` runs forward-only when the setting says so | Yes, opt-in | `fastFinishStrategy = slidingWindow` |
| 5 | A shorter last pass, and no waiting behind a wasted pass | Yes, opt-in | same setting |
| 6 | Only if Step 2 shows bad seams: carry the prompt, pin the language | Yes, opt-in | `carryPromptAcrossChunks = false` |
| 7 | Pick the default and update the docs | Maybe | the setting stays |

Every step that touches code ends with the same checks. See "Checks every step
runs" near the end.

---

## Step 0: Measure `r` from the log you already have

`r` means seconds of compute per second of audio. The design rests every latency
number on it, and asks for it to be measured before building anything.

**No code. Nothing to build. Do not dictate to produce data.** The log already has
months of real use.

### Where the lines come from

All three are in `stopAndTranscribe` in `Sources/Nivi/DictationController.swift`:

| Line | Log text | What it tells you |
|---|---|---|
| 362 | `Recording stopped (12.3s)` | How long the user spoke |
| 369 | `Final pass: profile …, model …, language …` | Which model ran |
| 394 | `Inference completed in 0.66s` | How long the final pass took, timed from line 373 |

One more line tells the two kinds of dictation apart. `startStreaming` logs
`Streaming: profile …` at line 299. If that line appears after
`Recording started` and before `Recording stopped`, the dictation streamed.

### How to read it

- **Plain batch** (no `Streaming:` line): the final pass covered the whole
  recording. So `r = inference seconds / recording seconds`.
- **Streaming** (has a `Streaming:` line): the final pass covered only the
  unfrozen tail. So the number is the **wait after stop**, not `r`. The log does
  not say how long the tail was. Step 1 adds that.

This command pairs the lines and groups them. It reads the log and writes one
scratch file in `/tmp`:

```sh
awk '
/Recording started/   {stream=0}
/Streaming: profile/  {stream=1}
/Recording stopped \(/ {s=$0; sub(/.*stopped \(/,"",s); sub(/s\).*/,"",s); dur=s+0}
/Final pass:/         {m=$0; sub(/.*model /,"",m); sub(/,.*/,"",m)}
/Inference completed in/ {t=$0; sub(/.*in /,"",t); sub(/s.*/,"",t);
                          printf "%s %s %.1f %.2f\n", (stream?"S":"B"), m, dur, t+0}
' ~/Library/Logs/Nivi/nivi.log > /tmp/nivi-r.txt

# r for plain batch, recordings of 5 s or more
awk '$1=="B" && $3>=5 {n[$2]++; a[$2]+=$3; c[$2]+=$4}
     END {for (k in n) printf "%s n=%d r=%.3f\n", k, n[k], c[k]/a[k]}' /tmp/nivi-r.txt

# wait after stop for streaming dictations
awk '$1=="S" {n[$2]++; w[$2]+=$4; if ($4>m[$2]) m[$2]=$4}
     END {for (k in n) printf "%s n=%d mean=%.2fs max=%.2fs\n", k, n[k], w[k]/n[k], m[k]}' /tmp/nivi-r.txt
```

### What it showed on 2026-10-26

| Model | Kind | Count | Result |
|---|---|---|---|
| `whisper-small-en` | batch, 5 to 15 s | 119 | `r = 0.027` |
| `whisper-small-en` | batch, 15 to 30 s | 88 | `r = 0.016` |
| `whisper-small-en` | batch, 30 to 60 s | 42 | `r = 0.015` |
| `whisper-small-en` | batch, over 60 s | 12 | `r = 0.013` |
| `ivrit-large-v3-turbo` | streaming, under 15 s | 104 | wait 0.87 s mean, 3.74 s max |
| `ivrit-large-v3-turbo` | streaming, 15 to 30 s | 7 | wait 0.92 s mean |
| `ivrit-large-v3-turbo` | streaming, 30 to 60 s | 11 | wait 0.80 s mean |
| `ivrit-large-v3-turbo` | streaming, over 60 s | 3 | wait 0.68 s mean |

Two things stand out:

1. **There is no `r` for the Hebrew model.** It has only ever run in streaming
   modes, apart from one 0.5 s batch dictation. Step 2 measures it offline from
   recorded audio, so nobody has to dictate to get it.
2. **Very short streaming dictations still wait about 0.6 s.** A 0.5 s recording
   took 0.63 s. That is the full-context encoder floor, described in Step 5.

The log also cannot say which streaming mode ran (`overlayLive` or
`batchFastFinish`), because no line names the mode. Step 1 adds it.

**Done when:** the numbers above are re-run and pasted into the PR for Step 1, so
there is a "before" to compare against.

---

## Step 1: Stop the model cache from handing out an unloaded model, and log what each pass costs

### The bug

Sometimes `RecognizerCache` hands back a model it has already unloaded. The
dictation then fails with `Inference failed: Model not loaded`. Nothing is pasted,
and the user has lost what they said. It keeps failing like that until the idle
timer clears the cache two minutes later.

The log shows it 5 times: on 2026-10-12 at 09:53:03, and three times on
2026-10-21 between 08:54:46 and 08:54:58. In the same moments,
`Streaming pass failed: Model not loaded` shows the live loop failing too. So the
fast finish quietly falls back to the slow whole-buffer pass, or fails outright.

### Why it happens

`RecognizerCache` is an actor. An actor lets other callers in while it waits at
an `await`. In `recognizer(id:modelPath:)` (`Sources/Nivi/RecognizerCache.swift:19-31`):

1. Call A finds no model and starts loading it. It waits at `await recognizer.load()` (line 25).
2. Call B arrives for the same model, also finds nothing, and starts a second load.
3. A finishes, stores its model, and adds the id to `order`.
4. B finishes, stores its own model over A's, and adds the id to `order` **again**.
5. `evictIfNeeded()` (lines 47-54) sees two entries against a capacity of 1. It
   removes the first one. That is the same id, so it unloads the model B just
   stored, and B returns that unloaded model to its caller.
6. `order` now holds an id with no model behind it. Every later call loads a
   model, stores it, and evicts it again straight away. That lasts until
   `evictAll()` clears `order`.

Two callers ask for a cold model at almost the same moment: `startStreaming`
(`DictationController.swift:271`) and `stopAndTranscribe` (line 371). A short
dictation right after the idle unload is enough. The design's option 5a (warm
the model at record start) would add a third caller, so this has to be fixed
first.

### What changes

- `Sources/Nivi/RecognizerCache.swift`: keep one load task per model id, in a
  `loading: [String: Task<SpeechRecognizer, Error>]` dictionary. A second caller
  waits on the same task instead of starting its own load. When a load finishes,
  never add an id to `order` twice.
- Move the order bookkeeping into core, so the rule gets tests. A small
  `RecentlyUsedOrder` struct in `Sources/NiviCore/` with `touch(id)`,
  `insert(id) -> [String]` (it returns the ids to evict) and `removeAll()`. The
  cache keeps the models and the awaits. The struct keeps the order. This logic
  exists inline today (`touch` at lines 42-45, eviction at 47-54). We only need to
  move it and make "insert the same id twice" safe.
- Logging, in `Sources/Nivi/DictationController.swift` and
  `Sources/Nivi/StreamingTranscriber.swift`:
  - Add the mode to the `Final pass:` line (369), for example `mode batchFastFinish`.
  - Add what the final pass covered to the `Inference completed` line (394),
    for example `Inference completed in 0.66s (tail 7.4s of 63.0s)` or
    `(whole 12.3s)`.
  - At stop, `StreamingTranscriber` logs one summary line per recording:
    `Streaming summary: 14 passes, 92.0s of audio transcribed, 9.1s of compute, frozen up to 55.6s`.
    Count passes, the audio seconds sent to whisper, and the compute seconds, in
    `runPass()` around the call at lines 94-95. One line per recording, not one
    per pass, so the log does not fill up.

With that line, `r` for the Hebrew model is compute divided by audio, read
straight from real use. And "audio transcribed" divided by recording length is
how many times each second was redone. That is the number forward-only is meant
to cut.

### Tests

In `Tools/core-tests/main.swift`, add a `// --- RecentlyUsedOrder ---` section
next to the other cache-free sections:

- Inserting the same id twice leaves one entry, and evicts nothing at capacity 1.
- Inserting a second id at capacity 1 evicts the first, never the one just inserted.
- `touch` moves an id to the most-recent end.
- `removeAll` leaves nothing to evict.

### Verify

- `bash Tools/run-core-tests.sh` prints `ALL CORE CHECKS PASSED`.
- `make dev` builds and signs.
- Over a normal day of use, `grep "Model not loaded" ~/Library/Logs/Nivi/nivi.log`
  finds no new lines, and `Recognizer loaded into cache` never shows twice in a row
  for the same model.

### Roll back

`git revert`. This is a bug fix with no setting. The new log fields are harmless
to keep.

---

## Step 2: A small replay check for accuracy and finish time

### Why this step exists

`docs/state-of-the-project.md` lists this as an open blocker: `batchFastFinish`
has no accuracy baseline, so any streaming change is made blind. The owner ranks
reliability and shipping above a full accuracy study. So this step aims for the
smallest check that still makes changes measurable. It is not a benchmark.

### The idea

Record three Hebrew passages once, as audio files. Then a small command-line tool
plays each file through the **real** whisper.cpp in three ways and prints the
results side by side:

1. **Whole pass**: one pass over the whole file. This is what plain `batch` does.
2. **Sliding window**: what `batchFastFinish` does today. Growing slices,
   `StreamWindow` with a 10 s cap, a pass every 500 ms after the last one
   finishes.
3. **Forward-only**: the new rules from Step 3. The tool reports "not built yet"
   for this one until Step 3 lands.

The same audio goes through every path. So any difference comes from the method,
not from saying the words differently on a second take.

**Reading aloud gives a real reference.** Read each passage from written Hebrew
text, for example a news paragraph. The written text is then the right answer, so
the tool can count real word errors, not just differences between methods.

### What the owner does (about 10 minutes, once)

- Pick three written Hebrew passages: one short (about 20 s read aloud), one about
  60 s, and one about 3 minutes. At least one should mix in English words or
  names, since that is where Hebrew models stumble.
- Read each one aloud into QuickTime Player (File, New Audio Recording). **Not
  into Nivi.** Save as `.m4a`.
- Put each audio file and its text (`passage-1.m4a`, `passage-1.txt`) in the
  private workspace, for example `~/personal/dev-workspace/nivi/fast-finish-check/`.
  They are the owner's voice, so they stay out of the public repo.

### What the tool prints, per file and per method

- The text.
- Word errors against the written text: count and percentage.
- Word differences against the whole pass.
- Total compute seconds, and compute per second of audio. For the whole pass,
  this is `r` for that model, which answers the gap from Step 0.
- The simulated wait after stop: the rest of any pass still running at the end
  of the audio, plus the tail pass.

A line at the bottom gives the totals for all three files, so a later run can be
compared at a glance.

### What changes

**This already exists; we only need to add a word count.** `AppendOnlyTail.swift:47-51`
already has the right normalising rule, `normalized(_:)`: lower case, letters and
digits only. That also strips Hebrew vowel points, which suits text written
without them. It is `private` today. We only need to make it internal and reuse it.

- New `Sources/NiviCore/WordErrorCount.swift`: word-level edit distance between a
  reference and a result, after `normalized`. It returns substitutions,
  insertions, deletions and the reference word count. Pure Foundation.
- New `Tools/fast-finish-check/main.swift` and `run.sh`:
  - `run.sh` follows `Tools/whisper-stress/run.sh` closely. It uses the same
    link line (lines 28-32) and the same check that whisper really ran on Metal
    (lines 40-46). Use `Tools/pinned-sdk.sh` for `swiftc`, as `CLAUDE.md` requires
    of every script that calls it.
  - Build `NiviCore` as a module first
    (`swiftc -parse-as-library -emit-library -static -emit-module -module-name NiviCore Sources/NiviCore/*.swift`).
    Then compile the tool against it, together with
    `Sources/Nivi/SpeechRecognizer.swift` and
    `Sources/Nivi/WhisperCppRecognizer.swift`. That way the tool calls whisper
    with **exactly** the app's parameters, not a copy that can drift. Those files
    reference `AudioRecorder.sampleRate` and `Log`. Add a two-line stand-in for
    each in the tool folder, not in the app.
  - Decode audio with `AVAudioFile` in the tool, or compile
    `Sources/Nivi/FileTranscription/AudioFileDecoder.swift` in if it builds alone.
  - The sliding-window run drives the real `StreamWindow` and `audioContext(...)`
    on a simulated clock. A pass that starts at time `t` sees audio `[windowStart, t)`.
    The next pass starts at `t + measured compute + 0.5 s`. That copies the loop
    at `StreamingTranscriber.swift:59-69`.

### Tests

In `Tools/core-tests/main.swift`, under `// --- WordErrorCount ---`:

- Identical texts give 0 errors.
- One swapped word gives 1 substitution.
- Case and punctuation do not count: `"Hello, world."` against `"hello world"` is 0.
- A dropped word and an added word each count once.
- Hebrew works, and vowel points are ignored: `"שָׁלוֹם עולם"` against `"שלום עולם"` is 0.
- An empty reference does not divide by zero.

### Verify

- `bash Tools/run-core-tests.sh` prints `ALL CORE CHECKS PASSED`.
- `bash Tools/fast-finish-check/run.sh <folder>` prints a table for all three files.
- Run it twice. Text and error counts should match exactly, since decoding is
  greedy. Times will move a little.

### Save the baseline

Paste the first full output into
`~/personal/dev-workspace/nivi/fast-finish-check/baseline-2026-xx-xx.txt`. Put a
short summary, with numbers only and no passage text, in
`docs/state-of-the-project.md`. That closes the open blocker: there is now a
baseline, and it can be repeated after every change.

### Roll back

Tools only. Nothing in the app changes.

---

## Decision gate: is forward-only worth building?

Read the Step 1 summary lines from a week of real use, and the Step 2 table.

- **Stop here** if both hold: the sliding window's compute per audio second is
  low enough that battery and fan noise are not a complaint, and its word errors
  are close to the whole pass. Then the fast finish already works, and the
  remaining gain is Step 5 alone. Step 5 can be done without Steps 3 and 4, by
  applying it to the sliding window.
- **Go on** if the sliding window costs a lot of compute (the design expects 6 to
  7 times the whole pass). Or go on if the owner notices heat or fan noise during
  long dictations.

Write the decision and the numbers in `docs/decisions.md`.

---

## Step 3: Forward-only rules in NiviCore, and the setting that picks them

No app behaviour changes in this step. It adds pure logic, tests, and the settings
keys. All the settings keys go in here, up front, so later steps only add behaviour
and never change what is written to disk. `Settings.swift` already does this for
the Preferences redesign (the block that starts "Settings the Preferences redesign
will use").

### Reuse first

| Need | What exists | What to add |
|---|---|---|
| Freeze everything except the last segment, every pass | **This already exists.** `StreamWindow.advance` with `maxWindowSamples: 0` freezes every segment but the last (`StreamWindow.swift:30-52`, the loop at 41-44) | A test that pins this behaviour, because forward-only depends on it |
| Freeze a lone segment that is clearly finished | Not there. Today a single segment never freezes (lines 41-44) | One rule, below |
| Tell quiet from speech in a short stretch of audio | **Half exists.** `AudioChunkPlanner.quietestWindowStart` (`AudioChunkPlanner.swift:79-101`) already finds the quietest stretch with a running sum. It is `private` | Expose a small public helper on top of it |
| Size `audio_ctx` for the slice | **This already exists.** `audioContext(forSampleCount:sampleRate:)` | Nothing |
| Join text pieces | **This already exists.** `StreamWindow` joins frozen text itself, and `ChunkedTranscription.join` drops empty pieces | Nothing |

### What changes

**1. `Sources/NiviCore/Settings.swift`: three keys.**

| Key | Type | Default | Meaning |
|---|---|---|---|
| `fastFinishStrategy` | `FastFinishStrategy` (`slidingWindow`, `forwardOnly`) | `slidingWindow` | How `batchFastFinish` transcribes during the recording |
| `forwardChunkSeconds` | Int, clamped 4 to 20 | 8 | How much new audio to collect before a forward-only pass |
| `carryPromptAcrossChunks` | Bool | false | Nothing reads this until Step 6 |

Follow the five steps in `docs/architecture.md`, "To add a setting". Skip the
Preferences row for now. These are set with `defaults write` until Step 7.
`FastFinishStrategy` is not a plain Bool or Int, so it gets an encode and decode
test. Only `batchFastFinish` reads the strategy. `overlayLive` and `inAppLive` keep
the sliding window, because their preview needs frequent passes to look live.

**2. `Sources/NiviCore/ForwardChunkPolicy.swift`: when to run a pass.**

A pure function. On each tick it gets the amount of unfrozen audio, whether the
last 200 ms are quiet, and whether the unfrozen audio has any speech at all. It
returns one of three answers:

- `.wait`: not enough new audio yet.
- `.run`: run a pass now. This happens when the unfrozen audio is at least
  `forwardChunkSeconds` and the speaker is pausing. It also happens when the audio
  reaches `forwardChunkSeconds + 6` with no pause, so a speaker who never pauses
  still gets passes.
- `.skipSilent`: the whole unfrozen stretch is quiet, so do not call whisper. This
  is option 5e from the design. It saves battery, and it gives whisper no silence
  to invent words from.

Waiting for a pause puts the end of each slice in a gap between words. That is
where a cut costs least.

**3. `Sources/NiviCore/AudioLoudness.swift`: is this stretch quiet?**

Build it on the running-sum code that is already in `AudioChunkPlanner`. The rule
is relative, as in WhisperKit: compare the last 200 ms against the quietest 100 ms
of the previous 2 s. A soft speaker is then not mistaken for silence. Move
`quietestWindowStart` here and have `AudioChunkPlanner` call it, so there is one
copy.

**4. `Sources/NiviCore/StreamWindow.swift`: one new rule for a lone segment.**

Add `advanceForwardOnly(segments:windowSampleCount:sampleRate:settledGapMs:)`. It
does what `advance(... maxWindowSamples: 0 ...)` does, plus one thing. It also
freezes the **last** segment if that segment ended at least `settledGapMs`
(default 2000) before the end of the slice. Speech that ended two seconds before
the slice did is finished, not cut off.

Without this, a speaker who talks in single long sentences gets one segment per
pass. Nothing then freezes, and the tail grows without limit. That is the failure
the warning at `StreamingTranscriber.swift:102-107` already watches for.

Keep the existing guard: an empty pass freezes nothing (`StreamWindow.swift:27`).

### Tests

Under `// --- StreamWindow ---` (`Tools/core-tests/main.swift:281`):

- `advance` with `maxWindowSamples: 0` freezes all segments but the last.
- `advanceForwardOnly` freezes a lone segment that ended 3 s before the slice end.
- It does not freeze a lone segment that runs to the slice end.
- An empty pass changes nothing.
- `windowStartSample` only ever moves forward over three passes.
- Frozen text plus the last segment's text equals what a single join of all the
  segments would give, so no word is dropped or repeated at the seam.

New `// --- ForwardChunkPolicy ---` and `// --- AudioLoudness ---` sections:

- Under `forwardChunkSeconds`, the answer is `.wait`.
- At `forwardChunkSeconds` with a quiet tail, it is `.run`.
- At `forwardChunkSeconds` with speech still going, it is `.wait`.
- At `forwardChunkSeconds + 6`, it is `.run` even mid-speech.
- All silence gives `.skipSilent`, however long it is.
- Constant low-level speech is not called silence (the relative baseline).
- Pure zeros count as silence and do not divide by zero.

The existing `// --- AudioChunkPlanner ---` checks (line 515) must still pass
unchanged. They prove the moved helper behaves the same.

Under `// --- streaming settings ---` (line 235): the defaults, the clamp on
`forwardChunkSeconds`, and an unknown stored strategy falling back to
`slidingWindow`.

### Also in this PR

Add the forward-only method to the Step 2 tool. It now runs the same
`ForwardChunkPolicy` and `advanceForwardOnly` on the simulated clock. Run it on the
three passages and paste the table into the PR.

### Verify

- `bash Tools/run-core-tests.sh` prints `ALL CORE CHECKS PASSED`.
- `make dev` builds. Nothing in the app reads the new code yet.
- The Step 2 tool shows forward-only with: compute per audio second near the
  whole pass (the design expects about 1.3 times), a simulated wait under one
  second, and word errors no more than a few points worse than the sliding window.
  If the errors are much worse, tune `forwardChunkSeconds` and `settledGapMs`
  in the tool first. Tuning there is cheap. Tuning in the app means dictating.

### Roll back

Nothing to roll back in the app. The defaults keep today's behaviour.

---

## Step 4: `batchFastFinish` runs forward-only when the setting says so

### What changes

**`Sources/Nivi/StreamingTranscriber.swift`.**

- Take the strategy and chunk size at init. `DictationController.startStreaming`
  reads them once at recording start, next to the other two settings
  (`DictationController.swift:294-295`). That follows the rule in
  `docs/architecture.md`: a setting is read once per recording.
- For `forwardOnly`, the loop changes shape:
  - Tick every 250 ms. On each tick, ask `ForwardChunkPolicy` what to do.
  - On `.run`: take the slice from `windowStartSample`, size the context with
    `audioContext(...)` as today (lines 90-91), call `transcribeSegments`, then
    fold the result in with `advanceForwardOnly`.
  - On `.wait` or `.skipSilent`: do nothing until the next tick.
- Keep the 1 s minimum (line 85). Keep both `Task.isCancelled` checks (lines 96
  and 121). Keep the once-only failure log (lines 127-130).
- Scale the stall warning (lines 102-107) to the chunk: warn when the unfrozen
  audio is over `3 * forwardChunkSeconds`, not `2 * windowSeconds`.
- Add the forward-only figures to the Step 1 summary line, for example
  `strategy forwardOnly, 3 passes skipped as silent`.

**`Sources/Nivi/AudioRecorder.swift`: stop copying the whole recording to check its length.**

`currentSamples()` (lines 218-220) copies the entire buffer. `runPass()` then
copies the slice again (`StreamingTranscriber.swift:79-82`). Both happen on the
main actor. At the 600 s limit that is 9.6 million samples, about 38 MB, copied
on every pass. Forward-only ticks four times a second, but only needs the
**length** on most ticks. Add `currentSampleCount()` and
`samples(from start: Int) -> [Float]`, both under `samplesQueue` like
`currentSamples()`. The sliding-window path can switch to `samples(from:)` too,
which helps the main thread in every live mode.

The loudness check needs only the last 2 s, so it reads
`samples(from: count - 2 * 16000)`.

**`Sources/Nivi/DictationController.swift`.** Almost nothing. The stitch at stop
(lines 375-390) already does exactly what forward-only needs: frozen text, plus
one pass over `[windowStartSample, end)`. **This already exists; we only need to
pass the two new settings into `StreamingTranscriber`.** No state machine change:
`DictationStateMachine` has no idea how the transcript was made, and it should
stay that way.

### Verify

- `bash Tools/run-core-tests.sh` prints `ALL CORE CHECKS PASSED`.
- `make dev`.
- `bash Tools/whisper-stress/run.sh`. Forward-only sends whisper a new pattern of
  graph shapes: repeated `audio_ctx` values around 400 to 600, then a full-context
  tail. The allocator crash fixed by `vendor/patches/0001` lived exactly in shape
  changes. Extend `Tools/whisper-stress/main.c` (loop at lines 39-52) with a second
  pattern: slices of 8 to 14 s at their sized context, then a short tail at
  context 0. It must still print `WHISPER GRAPH STRESS PASSED (on Metal)`.
- The owner turns it on for one profile:
  `defaults write com.dvir.nivi fastFinishStrategy forwardOnly`, on a profile set
  to `batchFastFinish`. Then dictates as normal for a few days. Agents must not
  dictate.
- Read the log. `Streaming summary` should show audio transcribed close to
  1.3 times the recording length, against 6 or so before. The `Inference completed`
  tail should stay under about `forwardChunkSeconds + 6` seconds.
  `Streaming window is not advancing` should not appear.

### Roll back

`defaults write com.dvir.nivi fastFinishStrategy slidingWindow`, or delete the
key. The old path is unchanged and stays the default. Setting the profile back to
`batch` turns streaming off entirely.

---

## Step 5: Shorten the last second: size the tail pass, and use the pass already running

Two separate wastes sit in the finish today. Both apply under `forwardOnly` only,
so the same setting turns them off.

### 5a. The tail pass always pays for 30 seconds of audio

`transcribe(samples:language:)` (`WhisperCppRecognizer.swift:36-81`) never sets
`audio_ctx`. So whisper encodes a full 30 s window even for a 3 s tail. The log
shows the result: a 0.5 s recording waited 0.63 s.

Run the tail with a sized context instead. **This already exists; we only need to
call it.** `transcribeSegments(samples:language:audioCtx:)` already takes a sized
context, rounds it safely, and falls back to full context if the value is bad
(lines 105-114). Call it from `stopAndTranscribe` (line 380) with
`audioContext(forSampleCount: tail.count, sampleRate: 16000)`, then join the
segment texts.

Only do this when the tail is under 30 s. A longer tail (a stall, or a long
silence) keeps the full-context `transcribe`, because whisper splits long audio
into 30 s windows itself.

The design's evidence that sized context is close to free comes from one user
report (whisper.cpp issue #1855, English). So the Step 2 tool must confirm it on
Hebrew before this ships: run the tail both ways and compare word errors.

### 5b. Stop waits behind a pass whose result it throws away

At stop, `stopAndTranscribe` reads `windowStartSample` and `frozenText` (lines
348-349), then calls `streamer.stop()`. If a pass is running at that moment,
whisper cannot be interrupted. It finishes on the serial queue
(`WhisperCppRecognizer.swift:8`), and then its result is dropped by the
`Task.isCancelled` check (`StreamingTranscriber.swift:121`). The tail pass waits
in the queue behind it, and then transcribes the same audio again. A forward-only
pass covers 8 to 14 s, so this can add a few tenths of a second.

Use the result instead. Add `func finish() async` to `StreamingTranscriber`. If a
pass is running, it waits for that pass and folds the result in with
`advanceForwardOnly`. Then it stops. `stopAndTranscribe` calls `await finish()`
before it reads `windowStartSample` and `frozenText`. The tail then starts after
the last segment the running pass settled.

Keep two rules:

- **Cancel must not wait.** `cancelRecording` (lines 447-460) and
  `showTransientError` (lines 549-565) keep calling `stop()`, which drops the
  result. A cancelled recording should never wait on whisper.
- **Read the profile before `transition(.stopRequested)`**, as the comment at
  lines 356-360 says. If `finish()` is awaited, put the await inside the `Task` at
  line 364, after `activeProfile` is captured. Never put it before line 360.

whisper.cpp v1.7.2 also has an `abort_callback` on `whisper_full_params`
(`vendor/whisper.cpp/include/whisper.h:562-563`). It could cut a running pass
short. Do not use it in this step. Nobody knows whether the Metal path checks it
in v1.7.2. A half-finished pass on a context that the next call reuses is exactly
the kind of state that crashed the allocator before. Waiting for a pass that
finishes anyway is safe.

### Verify

- `bash Tools/run-core-tests.sh` prints `ALL CORE CHECKS PASSED`. `finish()` lives
  in the app target, but the folding rule it uses is the one Step 3 tested.
- `make dev`.
- `bash Tools/whisper-stress/run.sh`. 5a adds another graph shape: a sized tail
  right after sized passes, with timestamps on.
- The Step 2 tool: the simulated wait should drop from about 0.6 to 0.9 s to
  well under that, and word errors should not move.
- In the log: `Inference completed` for short tails is well below the 0.6 s floor
  from Step 0.

### Roll back

`fastFinishStrategy slidingWindow`. If only one half misbehaves, revert that half.
They are separate commits.

---

## Step 6: Only if Step 2 shows bad seams: carry the prompt, pin the language

Skip this step unless the replay tool shows one of these problems in forward-only
text:

- **Broken punctuation at chunk edges.** Sentences end early, or capitals appear
  mid-sentence where chunks meet.
- **The same name spelled two ways.** In Hebrew the same name can often be spelled
  several ways, and each chunk picks on its own.
- **Language flips with `auto`.** With a language set to `auto` (Whisper Large v3
  Turbo), each pass detects the language again. A short chunk full of English
  names can come back as English in the middle of a Hebrew dictation.

### What changes

- **Carry the prompt.** `SpeechRecognizer.transcribeSegments` gets a
  `prompt: String?` parameter. `WhisperCppRecognizer` sets `params.initial_prompt`
  (`whisper.h:516`) inside the queue block, with `strdup` and `free`, the same
  way it handles `language` (lines 97-99). The prompt is the last 150 or so
  characters of `frozenText`. Do **not** use `carry_initial_prompt`. Its own PR
  warns that it raises the risk of repeats.
  The design names three guards, and all three go in:
  1. Keep temperature fallback on. It is on in `whisper_full_default_params`, so
     do not turn it off.
  2. Cap the prompt hard, at 150 characters, cut at a word boundary.
  3. If a pass's output starts with a long copy of the prompt, drop that pass's
     prompt and redo it once without one.
  Put guard 3 in core as a pure function, `promptEchoLength(prompt:output:)`,
  with tests.
- **Pin the language.** When the profile language is `auto`, read the language
  of the first pass that froze any text, with `whisper_full_lang_id`
  (`whisper.h:615`). Pass that language to every later pass and to the tail. This
  needs `transcribeSegments` to return the detected language too.

Both only run when `carryPromptAcrossChunks` is true (added in Step 3) and the
strategy is `forwardOnly`.

### Verify

- `bash Tools/run-core-tests.sh` prints `ALL CORE CHECKS PASSED`.
- `make dev`, then `bash Tools/whisper-stress/run.sh`.
- The Step 2 tool, with a fourth method: forward-only plus prompt. Also run it on
  a recording with long pauses, because repeat loops start in silence. Ship only
  if word errors go down and no output repeats itself.

### Roll back

`defaults write com.dvir.nivi carryPromptAcrossChunks -bool false`.

---

## Step 7: Pick the default and update the docs

After a week or more of forward-only in daily use:

- If it held up, make `forwardOnly` the default for `fastFinishStrategy`. Keep
  `slidingWindow` as a choice. Add one picker row to the Speech tab, next to the
  "Live preview" group in `SpeechSection` (`Sources/Nivi/Preferences/SettingsView.swift:531-540`).
  Its label should say what each choice costs, not how it works inside. For
  example: "Fast finish: lighter on battery" and "Fast finish: more context".
  Re-shoot the tab with `bash Tools/make-pref-shots.sh speech`. Never with clicks.
- `defaults.register` does not override a value already on disk (see
  `docs/architecture.md`, Settings). Users who never set the key get the new
  default. Anyone who set it by hand keeps their value. That is fine here, because
  only the owner has set it.
- If Step 6 never ran, remove `carryPromptAcrossChunks`, so no key sits on disk
  that nothing reads.
- Update `docs/state-of-the-project.md`: the modes table, the baseline numbers,
  and remove the blocker. Update `docs/architecture.md`: the "Streaming, as
  shipped" section, and the cache race as a new invariant. Add the decisions to
  `docs/decisions.md`, with the numbers from the replay tool.

### Roll back

The setting stays, so the old path is always one `defaults write` away.

---

## Risks, and which step handles each

### Words cut at a chunk edge

Forward-only never joins two transcripts at a point it chose itself. It freezes
only at an end time that whisper reported for a segment (`StreamWindow.swift:50`),
and the last segment of each pass is always transcribed again in the next one.
That is the same seam rule the sliding window uses today. Step 3 adds two more
protections. A pass runs when the speaker pauses, so the slice ends in a gap. And
a lone segment is only frozen when its speech ended two seconds before the slice
did. The Step 3 tests check that no word is dropped or repeated at the seam.
The Step 2 tool checks it on real audio.

### Hebrew and other languages

The design expects Hebrew to lose more than English from short context. Hebrew is
written without vowels, so the model leans on the words around each one. This is
reasoning, not a measurement. The Step 2 tool turns it into a measurement, on the
owner's own Hebrew. Mitigations, in order: chunks of 8 s or more (never 2 to 3 s),
cuts at pauses, the tail at full or properly sized context, and then Step 6. RTL
text needs nothing new: pieces are joined with a plain space, as today. Language
flips under `auto` are Step 6.

### The Metal `audio_ctx` rule

Any `audio_ctx` that is not a multiple of 4 aborts the whole app:
`GGML_ASSERT(nb01 % 8 == 0) failed`. Swift cannot catch it. The rule: every new
place that sets `audio_ctx` must get its value from
`audioContext(forSampleCount:sampleRate:)`, and must go through
`isUsableAudioContext` before it reaches whisper. Today that is only
`WhisperCppRecognizer.swift:109-114`. Step 5a reuses that same entry point rather
than adding a second one. Steps 4, 5 and 6 each run `Tools/whisper-stress/run.sh`,
and Step 4 extends it with the forward-only pattern of shapes.

### Made-up words in silence

whisper sometimes writes words that nobody said when it gets silence. In Hebrew a
common one is a "thank you" sign-off. `TranscriptCleaning` removes notes such as
`[BLANK_AUDIO]` by their shape, but it cannot catch invented words that look like
speech. whisper's own `no_speech_thold` is marked `TODO: not implemented` in
v1.7.2 (`whisper.h:537`), so it is no help. Step 3's `.skipSilent` keeps silence
away from whisper during the recording. Step 6's guard drops a prompt that echoes
back. The tail pass still sees any silence at the very end. That is what happens
today too, so it is no worse.

### Stall watch

Two different things go by this name, and both matter.

- **The window that never advances.** If whisper returns one segment per pass,
  nothing freezes, and the tail grows. `StreamingTranscriber.swift:102-107` logs
  `Streaming window is not advancing`. Step 3's lone-segment rule removes the
  usual cause. Step 4 scales the warning to the chunk size. If it still happens,
  the result is safe: the tail just gets longer, and with no freeze at all the
  stop path falls back to the whole-buffer pass (`DictationController.swift:391-392`).
- **The main-thread watchdog** (`StallWatch`, `MainThreadWatchdog`). Inference
  runs on the whisper queue, not the main thread. But the sample copy in
  `runPass()` runs on the main actor, and it grows with the recording. Step 4's
  `currentSampleCount()` and `samples(from:)` remove the whole-buffer copy. Watch
  for `Main thread has not answered for Ns` in the log during long dictations.

### Cancel during a pass

`cancelRecording` stops the loop and drops whatever the running pass returns
(`StreamingTranscriber.swift:96, 121`). The pass itself finishes on the whisper
queue, because it cannot be interrupted. So the next recording's first pass may
wait behind it for up to one pass, which is well under a second. Unloading the
model during a pass is safe, because `unload()` runs on the same queue
(`WhisperCppRecognizer.swift:146-158`). Step 5b must keep cancel on `stop()`,
never on `finish()`. The `recordingGeneration` check
(`DictationController.swift:284-289`) already keeps a slow streamer setup from
attaching to the next recording.

### The model unloaded during a recording

This is what the Step 1 bug did in practice. Two other routes can still unload
the model mid-recording: "Reload model", and the idle timer. The idle timer only
fires in `.idle` (`DictationController.swift:486`). In both cases the streamer
holds a recognizer that is no longer loaded. Every pass then fails once, with one
log line, and the stop path loads a fresh model and transcribes the whole buffer.
That is slow, but correct. No change is planned beyond Step 1. The summary line
from Step 1 will show how often it happens.

## What this plan does not do

- **Parakeet.** It has no Hebrew. See `docs/parakeet/`.
- **Silero voice detection (option 2).** Step 3's loudness check covers the cheap
  part. Come back to it only if the replay tool still shows bad cuts after Step 6.
- **Parallel chunks at stop (option 5b).** The design ruled it out. The finish
  would still grow with length.
- **Changing `overlayLive` or `inAppLive`.** Their previews need frequent passes.
  They pick up two side benefits: the cache fix in Step 1, and the cheaper sample
  reads in Step 4.

## Checks every step runs

Before a commit:

1. `find Sources Tools -name "* [0-9].*"` finds nothing. iCloud's "name 2" copies
   break the build.
2. `bash Tools/run-core-tests.sh` prints `ALL CORE CHECKS PASSED`.
3. `make dev` builds and signs with `Nivi Self-Signed`. Never `swift build` on its
   own, never ad-hoc signing.
4. If the step touches anything whisper runs, `bash Tools/whisper-stress/run.sh`
   prints `WHISPER GRAPH STRESS PASSED (on Metal)`.
5. If the step changes what text comes out, run `bash Tools/fast-finish-check/run.sh`
   and paste the table into the PR.

Agents never dictate, never press keys, and never drive the app. Anything that
needs a real dictation goes to the owner, as a short list in the PR description.

A side note found while writing this: `Tools/run-core-tests.sh` calls `swiftc`
without `Tools/pinned-sdk.sh`, although `CLAUDE.md` says every script that calls
`swiftc` should use it. It works today. If the SDK breaks again, it is the next
place to look.
