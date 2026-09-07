# Architecture

How the parts of Nivi fit together, as the code is today (2026-09-07).

This describes what exists. The design notes under
[superpowers/](superpowers/) describe what was planned, which is not always the
same thing. Where they differ, this file is right and the differences are called
out below.

Read [../CLAUDE.md](../CLAUDE.md) first for the build rules. Read
[state-of-the-project.md](state-of-the-project.md) for what works and what does
not.

## The path a dictation takes

```
hotkey
  HotkeyRouter          global NSEvent monitors, one detector per modifier key
    DictationController.hotkeyActivated(profileID:)
      startRecording()
        AudioRecorder.start()          async, off the main thread, 8s deadline
        StreamingTranscriber.start()   only if the mode streams
  ...user speaks...
    DictationController.stopAndTranscribe()
      AudioRecorder.stop()             hands over the samples
      WhisperCppRecognizer.transcribe  the final pass
      TranscriptFinishing.finish       clean, then apply word rules
      HistoryStore.record              saved before insertion, on a background queue
      TextInserter.insert              clipboard and Cmd-V, or typed characters
```

`DictationController` is the only object that knows the whole flow. Everything
else does one job and is handed what it needs.

### 1. The hotkey

`HotkeyRouter` installs four `NSEvent` monitors: global and local, for
`flagsChanged` and `keyDown`. Global monitors are what need permissions, and the
two grants are not the same one:

- `flagsChanged`, which is how modifier taps are seen, needs **Accessibility**.
- `keyDown`, which is how Esc-to-cancel is seen, needs **Input Monitoring**.

An app with only Accessibility has working hotkeys and a dead Esc key. That
partial failure looks like a bug in the key handling and is not.

Each modifier-tap profile gets one `ModifierTapDetector`, keyed by the modifier's
`keyCode`. That keying is why two profiles cannot both use right Command with
different tap counts: there is one detector per key.

While recording, `beginRecording(profileID:)` switches the active profile's
detector to single tap, so one tap stops what two taps started. `endRecording()`
puts every detector back using `originalModes`. `fire(_:)` drops activations from
any other profile while a recording is running.

Global monitors can stop delivering after the machine sleeps, so
`DictationController.start()` re-arms them on `NSWorkspace.didWakeNotification`.

### 2. Recording

`AudioRecorder` captures microphone input and converts it to 16 kHz mono
`Float32`, which is what whisper.cpp wants. Two queues:

- `samplesQueue` guards `samples` and `isCapturing`. The audio tap appends from a
  real-time thread, so nothing else may touch them directly.
- `engineQueue` owns every `AVAudioEngine` and CoreAudio call.

`currentSamples()` returns a snapshot of the growing buffer. That is what the
streaming loop re-transcribes. `stop()` hands the buffer over and drops its own
copy, then stops the hardware in the background so it returns immediately even
when CoreAudio is slow.

The engine is **kept between recordings** and rebuilt only when the answer to
"which microphone" changes: a different preferred device, a different system
default, or an `AVAudioEngineConfigurationChange`. It is dropped after 90 seconds
idle. See [decisions.md](decisions.md) for why, and
`AudioRecorder.readyEngine()` for how.

### 3. Transcription

`WhisperCppRecognizer` wraps whisper.cpp behind the `SpeechRecognizer` protocol.
All inference runs on one serial queue, `com.dvir.nivi.whisper`. Two entry
points:

| Method | Returns | Used by |
|---|---|---|
| `transcribe(samples:language:)` | one `String` | the final pass, file transcription, model test |
| `transcribeSegments(samples:language:audioCtx:)` | `[TranscriptSegment]` with timestamps | the streaming loop only |

Only the segments entry point sets `audio_ctx`, because only the streaming loop
transcribes a short slice. The final pass leaves it at whisper's default, which
is the model's full context.

`RecognizerCache` is an actor holding loaded models by id, least-recently-used
first out. Capacity defaults to 1. `DictationController` releases everything
after `idleUnloadSeconds` (default 120) of sitting idle, which takes an idle app
from about 1.6 GB back down to about 34 MB.

Freeing is serialized against inference. `unload()` clears the pointer and calls
`whisper_free` **on the inference queue**, so a free can never overlap a running
`whisper_full`. With live streaming an in-flight pass is the normal state, and
both "Reload model" and the idle timer are reachable mid-recording.

### 4. Insertion

`TextInserter.insert` decides between three outcomes:

- **typed**: the user picked "Type it out". `typeUnicode` posts Unicode key
  events, chunked by `Character` (not UTF-16 unit, or an emoji's surrogate pair
  would be split) and paced with `usleep(1000)` because Electron apps drop a
  burst that arrives faster than they drain it.
- **pasted**: text on the clipboard, then synthetic Cmd-V.
- **copiedToClipboard**: copy-only, or no Accessibility grant.

`focusedElementAcceptsText()` asks the Accessibility API whether the focused
element accepts text. It is **only** allowed to decide whether the previous
clipboard is restored afterwards. It must never gate pasting or the transient
marker, because it returns false in Electron and web views even when typing works
there, and that false negative already caused one bug. See
[decisions.md](decisions.md).

## The state machine

`DictationStateMachine` in `Sources/NiviCore/` is pure and testable. Six states:

```
loadingModel --modelLoaded--> idle
idle --startRequested--> recording
recording --stopRequested--> transcribing
recording --cancelRequested--> idle
transcribing --transcriptionSucceeded--> inserting
transcribing --transcriptionFailed--> error
inserting --insertionCompleted--> idle
error --errorDismissed--> idle
any --modelFailed--> error
```

`handle(_:)` ignores anything that is not a valid pair and returns `false`, so an
unexpected event cannot put the app in a strange state.

### The trap in `transition(_:)`

`DictationController.transition` does this:

```swift
if machine.state != .recording {
    router.endRecording()
    activeProfileID = nil
}
```

**Leaving `.recording` clears `activeProfileID`.** So anything that needs to know
which profile was recording must read it **before** calling `transition`.

This already caused a real bug. `stopAndTranscribe` used to resolve the profile
inside the async block that runs after `transition(.stopRequested)`. By then
`activeProfileID` was nil, so it fell back to the primary profile, and a
non-primary English profile produced Hebrew text from the final pass. The fix is
one line moved earlier, and the comment at that line says so:

```swift
let activeProfile = profileStore.set.profile(id: activeProfileID ?? profileStore.set.primaryID)
transition(.stopRequested)
```

It is an easy thing to reintroduce. If you add anything to the stop path that
needs the profile, resolve it above that line.

### `recordingGeneration`

`state == .recording` cannot tell two recordings apart. Loading a cold model
takes about a second, during which the user can stop one recording and start
another. Without a check, the streamer being set up for the first recording would
attach to the second, typing the old profile's transcript into the document.

So `startRecording` increments `recordingGeneration`, and every async
continuation checks it against the value it captured. `startStreaming` and
`handleStreamingUpdate` both do this.

## The four insertion modes

`InsertionMode` lives in `Sources/NiviCore/Settings.swift`. A profile picks one.

| Mode | Streams while recording | Shows during | Inserts at the end |
|---|---|---|---|
| `batch` | no | nothing | the whole text |
| `batchFastFinish` | yes | nothing | the whole text |
| `overlayLive` | yes | live text in the overlay | the whole text |
| `inAppLive` | yes | live text in the overlay, and types into the app | only the unsaid tail |

`InsertionMode.streamsDuringRecording` is `self != .batch`. That one property is
the gate in `startRecording`, so no call site lists modes by hand.

The difference between the three streaming modes is entirely in
`handleStreamingUpdate`:

- `overlayLive` sets `overlayModel.liveText = fullText`.
- `inAppLive` sets `liveText` too, and calls `typeAppendOnly(stableText)` unless
  the user turned on copy only.
- `batchFastFinish` does nothing at all. Its `case` is an explicit `break` with a
  comment, so it reads as deliberate rather than forgotten.

They all reach the same final pass. `batchFastFinish` exists because streaming
freezes text as it goes, so the final pass only has the tail left and stopping
feels instant however long you spoke.

## Streaming, as shipped

Three pieces, and it is worth being precise about which mode actually uses each.

### `StreamWindow` (used by all three streaming modes)

The live loop re-transcribes only a trailing window, because whole-buffer passes
get slower the longer you speak and fall further behind the speaker.

That means committing to text for audio that falls out of the window.
`StreamWindow` does it on **whole segment boundaries**, because segment
timestamps are the only way to know which words belong to which audio. Splitting
anywhere else would duplicate or drop words at the seam.

`advance(segments:windowSampleCount:maxWindowSamples:sampleRate:)`:

1. If the window is not over its cap, nothing freezes.
2. If it is over, freeze leading segments in order until the frozen boundary
   reaches or passes the excess, **including** the segment that crosses it.
3. Never freeze the last segment. It is still being spoken and its text will keep
   changing. If that segment alone overflows the window, the window simply runs
   long for a while. A correct seam matters more than an exact window size.

It keeps two things:

- `frozenText`: the transcript for `[0, windowStartSample)`. Never revised.
- `windowStartSample`: where the live window begins. Only ever moves forward.

### The stitch at the end

`stopAndTranscribe` reads both values off the streamer before stopping it, then:

```
frozenText            covers [0, windowStartSample)
tail pass             covers [windowStartSample, end)
```

The two partition the recording exactly, so joining them is plain concatenation
with a space. There is no overlap to reconcile and no seam-finding. That is the
whole reason freezing happens on segment boundaries.

The tail pass uses the full context, not the reduced one, because quality matters
more than speed for the text the user keeps. The cost, stated plainly: frozen
text never gets a whole-buffer correction. That is the accuracy price of
`batchFastFinish`.

If `windowStartSample` is 0, nothing ever froze and the final pass transcribes
the whole buffer as normal.

### `StablePrefixTracker` (used only by `inAppLive`)

Turns successive whole-text transcripts into a committed prefix that only grows.
A word counts as stable once it has survived `stabilityPasses` consecutive passes
unchanged (default 2). Committed entries are never rewritten.

Its output reaches only `StreamingUpdate.stableText`, and only `inAppLive` reads
that. The other two modes use `fullText`. So if you are working on the overlay
preview, the tracker is not in your path.

**This differs from the 2d.1 spec.** The spec said to feed the window's text
through the tracker and then call `window.advance(...)`, making `stableText`
"frozen plus the tracker's committed prefix". The shipped code runs
`window.advance(...)` first and feeds the tracker the resulting whole live text.
The comment in `StreamingTranscriber.runPass()` explains why: the tracker only
ever sees the whole text, so its committed prefix stays monotonic across a
freeze. Same guarantee, simpler construction.

### `AppendOnlyTail` (used only by `inAppLive`)

`appendOnlyTail(alreadyTyped:fullText:)` returns the text to add so the document
grows toward the transcript without ever deleting or rewriting.

It matches on **words**, not characters, with case and punctuation ignored.
Whisper re-punctuates and re-capitalizes words it already emitted as it gets more
context, so `"hello world this is"` becomes `"Hello, world. This is a test."`. A
character offset into one string means nothing in the other and would re-emit
half a word.

`DictationController.typedText` is what has actually been typed. It is reset in
`startRecording` and in `finishWithError`, never left for a later path to clear.

## Invariants

Break one of these and the failure is silent, or fatal, or lands in someone's
document where it cannot be taken back.

**`audio_ctx` must be a multiple of 4.** Metal's matrix kernels need an aligned
row stride, ggml checks it, and a bad value calls `ggml_abort`:
`ggml/src/ggml-metal.m:1925: GGML_ASSERT(nb01 % 8 == 0) failed`. That is not an
error Swift can catch. It kills the process and the user loses the dictation they
were in the middle of. `audioContext(forSampleCount:sampleRate:)` rounds up to a
multiple of 4, and `isUsableAudioContext` is checked again in
`WhisperCppRecognizer` before the value reaches whisper. Verified: every multiple
of 4 from 256 to 1500 runs; 257, 258, 259, 371, 629 and 631 all abort.

**Size `audio_ctx` from the slice actually being transcribed**, not from the
configured window length. The window runs long whenever the last segment is still
being spoken, and a context cut to the nominal length silently drops that overrun
before whisper ever hears it. This was a real accuracy bug.

**Insertion into the user's document is append-only.** `inAppLive` has already
typed text that cannot be retracted. Never delete, never rewrite, only add. If
the final transcript disagrees with what was typed, the disagreement stays.

**The recorder must never block the main thread.** CoreAudio calls go through the
system audio daemon and can block with no upper bound. One of them once hung the
app forever with no way to quit it. Everything goes through `engineQueue`, and
`start()` has an 8 second deadline via `withDeadline`.

**`Sources/NiviCore/` imports Foundation only.** The test harness compiles it as
one module. One `import AVFoundation` there breaks every test at once. See
[../CLAUDE.md](../CLAUDE.md).

**One text pipeline.** Everything the user sees, pastes and keeps goes through
`TranscriptFinishing.finish`, so the saved text and the pasted text can never
differ.

## Threading

| Where | What runs there |
|---|---|
| Main actor | `DictationController`, `StreamingTranscriber`, `ModelTester`, all UI |
| `engineQueue` | every `AVAudioEngine` and CoreAudio call in `AudioRecorder` |
| `samplesQueue` | the sample buffer and `isCapturing`, written from the audio tap's real-time thread |
| `com.dvir.nivi.whisper` | all inference and every `whisper_free` |
| `RecognizerCache` actor | loading, eviction, the cache dictionary |

**A `Task { }` inside a `@MainActor` type inherits the main actor.** It does not
hop off. This is the single most expensive thing anyone has got wrong on this
project: `startRecording` wrapped a blocking `engine.inputNode` call in a plain
`Task { }`, which ran it on the main thread with no time limit. One cold access
measured 15 seconds and there is no upper bound. The menu bar died with it, and
because the app runs as an accessory it never appeared in Force Quit.

So: if work inside a main-actor type must not block the main thread, it needs an
explicit queue or a `nonisolated` boundary. `AudioRecorder.start()` is `async`
and hops to `engineQueue` internally, which is why the call site can stay simple.

`MainThreadWatchdog` is the backstop. It pings the main queue every second, logs
after 5 seconds of silence, and stops the process after 45. Quitting deliberately
does not restore the output volume, because that is itself a CoreAudio call and
CoreAudio is the usual suspect. `SystemVolume.restoreAfterCrash()` handles it at
the next launch instead.

## Settings

`Sources/NiviCore/Settings.swift` is a struct over `UserDefaults`. Every key has
a registered default, a private `Key` constant, and a computed property with a
`nonmutating set`. The domain is `com.dvir.nivi`, so anything is reachable from
the terminal:

```sh
defaults read com.dvir.nivi
defaults write com.dvir.nivi streamingWindowSeconds -int 12
```

To add a setting:

1. Add the key to the private `Key` enum.
2. Add its default to the `defaults.register(defaults:)` call in `init`.
3. Add the computed property.
4. Add a row in the right Preferences tab using `PrefKit`
   (`PrefToggleRow`, `PrefPickerRow`, `PrefStepperRow`).
5. If the value is not a plain Bool or Int, add a core test for encoding and
   decoding it.

Two things to know. `defaults.register` never overrides a value already written
to disk, so changing a default does nothing for anyone who already has the old
one; `migrateToLighterMemoryDefaults()` is the pattern for fixing that, and it
runs once and only clears the exact old values. And a setting read repeatedly
during a recording should be read **once** when the recording starts:
`activeReplacements` does this, because parsing the same JSON several times a
second is waste, and a rule edited mid-recording changing the text halfway
through would be worse than surprising.

## Tests

There is no XCTest, because `swift test` needs full Xcode and only Command Line
Tools are installed. Instead `Tools/run-core-tests.sh` compiles every core file
plus the test file as **one module** and runs it:

```sh
swiftc -O Sources/NiviCore/*.swift Tools/core-tests/main.swift -o .build/core-tests
```

Run it with:

```sh
bash Tools/run-core-tests.sh     # prints ALL CORE CHECKS PASSED
```

`Tools/core-tests/main.swift` is one long script, currently about 760 lines. The
whole framework is six lines at the top:

```swift
var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if !cond { print("FAIL: \(msg)"); failures += 1 }
}
```

and the exit at the bottom. To add a test, append a section under a
`// --- Name ---` comment near related ones, and write `check(...)` calls. The
message is what a reader sees when it fails, so write what was expected, not the
name of the function.

Because it is one module, the test file must **not** `import NiviCore`, and
neither may any core file.

Things that need a real app, a microphone or a window cannot be tested here. That
is deliberate: it is the reason as much logic as possible lives in core. For
checking the UI, use the screenshot harnesses named in
[../CLAUDE.md](../CLAUDE.md), never synthetic clicks.

For `UserDefaults`, make a throwaway suite rather than touching the real domain:

```swift
let suite = UserDefaults(suiteName: "com.dvir.nivi.coretest")!
suite.removePersistentDomain(forName: "com.dvir.nivi.coretest")
let s = Settings(defaults: suite)
```
