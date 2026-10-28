# Architecture

How the parts of Nivi fit together, as the code is today (2026-10-26).

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
`Float32`, which is what whisper.cpp wants. Two kinds of queue:

- `samplesQueue` guards `samples` and `isCapturing`. The audio tap appends from a
  real-time thread, so nothing else may touch them directly.
- Each `MicrophoneSession` owns one `AVAudioEngine` and the serial queue that
  every `AVAudioEngine` and CoreAudio call for it runs on.

There is normally one session for the life of the app. If `start()` hits its 8
second deadline, the session is **retired** and a fresh one replaces it. The
stuck call still owns the old queue, and a blocked Mach call cannot be cancelled,
so sharing that queue would make every later recording wait behind it. That is
exactly what happened on 2026-09-14, for 27 minutes. A retired session checks its
mark before installing the tap, so a start that returns late never opens the
microphone, and a teardown queued behind it closes the old engine.

`currentSamples()` returns a snapshot of the growing buffer. That is what the
streaming loop re-transcribes. `stop()` hands the buffer over and drops its own
copy, then stops the hardware in the background so it returns immediately even
when CoreAudio is slow.

Within a session, the engine is **kept between recordings** and rebuilt only
when the answer to "which microphone" changes: a different preferred device, a
different system default, or an `AVAudioEngineConfigurationChange`. It is dropped
after 90 seconds idle. See [decisions.md](decisions.md) for why, and
`AudioRecorder.readyEngine(in:)` for how.

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

So one whisper context is asked for two differently shaped graphs all day:
streaming passes with timestamps and a growing `audio_ctx`, then a final pass
with no timestamps and the full context. whisper.cpp v1.7.2 crashed on that
alternation, in ggml's graph allocator, with `KERN_INVALID_ADDRESS at
0x0000000000000020`. The fix is
`vendor/patches/0001-ggml-alloc-guard-stale-buffer-id.patch`, and
`Tools/whisper-stress/run.sh` repeats the alternation to prove it.

Inference runs on the GPU through Metal. If the Metal shaders fail to build,
whisper falls back to the CPU without telling Nivi, and every pass takes about
three times longer. `make vendor` checks the shaders, and the stress tool refuses
to pass on the CPU. See [../vendor/patches/README.md](../vendor/patches/README.md).

`RecognizerCache` is an actor holding loaded models by id, least-recently-used
first out. Capacity defaults to 1. Only one load per model id runs at a time: a
second caller waits on the first one's load. Which ids to unload is decided by
`RecentlyUsedOrder` in core, which never holds an id twice. `DictationController` releases everything
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

## Files, history and export

`FileTranscriptionService` turns a dropped file into text without touching
dictation. It decodes the file with AVFoundation, cuts it at quiet moments into
parts (`AudioChunkPlanner`), and runs each part through the same
`RecognizerCache` the dictation uses, stepping aside between parts whenever a
dictation is running. The parts are joined (`ChunkedTranscription.join`) and
split into paragraphs (`TranscriptParagraphs.format`), because whisper returns
one endless line. A finished transcript goes to `HistoryStore` with
`source == .file`; a stopped one does not.

`HistoryStore` keeps everything in one JSON Lines file and in memory.
`HistoryFiltering` (core) searches, filters by source and sorts. The History tab
and the **Transcribed files** list on the Transcribe a file tab both read the same
store and draw the same `HistoryEntryCard`.

`TranscriptExporter` writes a transcript as `.txt`, `.docx`, `.rtf` or `.odt`
through `NSAttributedString`, marking each paragraph's direction from its own
letters (`TextDirection`, core). `SaveTranscriptMenu` is the one Save as menu,
used on the result and on every file card.

**Long text is shown with `LongSelectableText`**, a read-only `NSTextView`, never
with SwiftUI's `.textSelection(.enabled)`. See the invariant below.

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
app forever with no way to quit it. Everything goes through the current
`MicrophoneSession`'s queue, and `start()` has an 8 second deadline via
`withDeadline`.

**A deadline frees the caller, not the queue.** Anything that retries after a
`withDeadline` timeout must use a different queue, or it waits behind the stuck
call. `AudioRecorder` does this by retiring the session.

**Never put a transcript in SwiftUI's selectable `Text`.** On the first click,
AppKit lays the whole string out as one line in its field editor, and past
roughly 10,000 characters Core Text crashes the app (`CFRelease() called with
NULL`). Use `LongSelectableText`.

**whisper must run on Metal.** A CPU fallback is silent and about three times
slower. After `make vendor`, run `bash Tools/whisper-stress/run.sh`.

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
| the current `MicrophoneSession`'s queue | every `AVAudioEngine` and CoreAudio call in `AudioRecorder` |
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
and hops to the session's queue internally, which is why the call site can stay simple.

`MainThreadWatchdog` is the backstop. It pings the main queue every second, logs
after 5 seconds of silence, and stops the process after 45. The rule is
`StallWatch` in core: time is measured on `systemUptime`, which stops while the
Mac sleeps, and quitting also needs 45 readings actually taken. Measured with
`Date()`, it used to quit a healthy app on the first tick after every sleep.
Quitting deliberately does not restore the output volume, because that is itself a
CoreAudio call and CoreAudio is the usual suspect.
`SystemVolume.restoreAfterCrash()` handles it at the next launch instead.

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

`Tools/core-tests/main.swift` is one long script, currently about 870 lines and
300 checks. The whole framework is six lines at the top:

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
[../CLAUDE.md](../CLAUDE.md), never synthetic clicks. `Tools/make-pref-shots.sh`
can draw `general`, `speech`, `layout`, `sidebar`, `history` and `files`; the
last two read the real history file on the Mac, read only. It cannot show the
window's close, minimise and zoom buttons, because a window that never becomes
active does not draw them.

Two checks live outside the core tests because they need more than Foundation:
`bash Tools/whisper-stress/run.sh` needs a downloaded model and the GPU, and the
throwaway harnesses described in [state-of-the-project.md](state-of-the-project.md)
were how the September and October crashes were reproduced.

For `UserDefaults`, make a throwaway suite rather than touching the real domain:

```swift
let suite = UserDefaults(suiteName: "com.dvir.nivi.coretest")!
suite.removePersistentDomain(forName: "com.dvir.nivi.coretest")
let s = Settings(defaults: suite)
```
