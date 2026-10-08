# State of the project

Written 2026-09-07. This is the catch-up document: what is built, what is
released, what is known to be wrong, and what nobody has tested yet.

For what the app does, read [README.md](../README.md). For settled decisions,
read [decisions.md](decisions.md).

## What is built

### Dictation

The core loop works and is used daily. A hotkey starts a recording, whisper.cpp
transcribes it, and the text goes into the app in front.

There are four insertion modes. A profile picks one.
`Sources/NiviCore/Settings.swift` defines them as `InsertionMode`.

| Mode | What it does |
|---|---|
| `batch` | Records, then transcribes the whole recording, then pastes. The wait at the end grows with how long you spoke. |
| `batchFastFinish` | Transcribes while you speak but shows nothing. On stop, only the unfinished tail is left, so the wait is short however long you spoke. |
| `overlayLive` | Same as above, but the words appear in the overlay as you speak. |
| `inAppLive` | Types the words into the app as you speak, appending only what is new. |

Everything except plain `batch` runs the transcriber during the recording. That
is `InsertionMode.streamsDuringRecording`.

The streaming machinery is a sliding window (`StreamWindow`), a monotonic
committed prefix (`StablePrefixTracker`), and an append-only seam finder
(`AppendOnlyTail`) so already-typed words are never rewritten.

### Profiles and hotkeys

A profile ties one hotkey to one model, one language and one insertion mode. One
profile is primary, which decides the menu bar glyph. Hotkeys are modifier taps
(double-tap right Command, and so on), detected by `ModifierTapDetector`. Esc
cancels a running recording, and that needs Input Monitoring, which is a separate
grant from Accessibility.

### Models

The catalogue is in `Sources/NiviCore/ManagedModel.swift`:

- **ivrit-ai Large v3 Turbo** (Hebrew, the default)
- **Whisper Large v3 Turbo** (auto-detect, about a hundred languages)
- **Whisper Small (English)**
- **NVIDIA Parakeet TDT 0.6B v3 and v2**, listed but `isRunnable` is false. No
  engine exists for them. See "Parakeet" below.

Models download from Hugging Face on first use. `RecognizerCache` keeps one model
in memory and releases it after two minutes idle.

### Preferences

Rebuilt from scratch in August, modelled on the competitor app Spokenly. There is
a small design system in `Sources/Nivi/Preferences/PrefKit.swift` and
`PrefTheme.swift`: `PrefPage`, `PrefGroup`, `PrefRow` and typed row wrappers,
plus `PrefBanner` and `PrefEmptyState`. Every tab has a large title, a one-line
grey description, and named section headings that sit outside their cards.

Nine tabs, in `PrefSection`:

General, Dictation Models, Profiles, Hotkeys, Speech, Transcribe File, History,
Layout, Debug.

Layout and Debug are developer tools and are **absent from a release build**, not
merely disabled. See `Sources/Nivi/DeveloperMode.swift`. The escape hatch for
running a release build with them on is
`defaults write com.dvir.nivi showDeveloperTabs -bool true`.

### History

Every dictation is appended to `~/Library/Application Support/Nivi/history.jsonl`
as JSON Lines, mode 0600. Text only, never audio: text is about 500 bytes a
record, so 30 days costs under 2 MB, while audio would be 3.84 MB a minute.
Retention defaults to 30 days and is configurable, with a keep-forever option.
Search, filter, delete one, delete all, and an off switch. The filtering and
retention logic is pure and lives in core.

### Transcribe File

Drag an audio or video file in, or pick one, and get the text back. Decoding uses
AVFoundation, so no new dependency. Long files are split by `AudioChunkPlanner`
and transcribed chunk by chunk with real progress and working cancellation. It
refuses to start while a dictation is running, the same way `ModelTester` does,
so it can never steal the microphone. Verified working on `.m4a`, `.wav` and
`.mp4`. A 12.5 minute WAV ran as 3 chunks in 16 seconds.

### Word replacements

Find-and-replace pairs applied to every transcript. Useful for names the model
keeps getting wrong. The matching logic is pure (`WordReplacement`,
`TranscriptFinishing`).

### Microphone priority

A drag-to-reorder list of input devices. Nivi records from the first one that is
present. Enumeration is CoreAudio (`MicrophoneDevices.swift`), and the device is
bound with `setDeviceID` on a stopped engine. Only device ids are stored, so a
device never seen this session shows its id rather than its name.

### Recording displays

Two looks, picked in General:

- **Panel**: 296x56pt, floats near the bottom, rounded corners, a soft animated
  glow travelling around the border, and a live waveform.
- **Notch**: 294x32pt, hugs the top and merges with the MacBook camera notch.
  Height comes from `NSScreen.safeAreaInsets.top`, and it is pinned to
  `auxiliaryTopLeftArea.maxX` so it lines up on any notched display.

Both can show an elapsed timer, which is on by default and can be turned off.

The two thumbnails in Preferences are real screenshots of the real views,
regenerated by `Tools/make-recording-thumbnails.sh`. Re-run it whenever an
overlay changes, or the pictures go stale.

### Updates

Sparkle 2.9.6, added as a SwiftPM dependency. It ships as a prebuilt XCFramework,
so it builds with Command Line Tools only. The app checks once a day and always
asks before installing. The feed is a committed file served by GitHub Pages.

## What is released

Version 0.2.0, build 3, published 2026-10-08. The previous one was 0.1.0, build 2,
published 2026-09-02.

- Repo: `Dvirco1234/nivi`, public
- Download page: https://dvirco1234.github.io/nivi/
- Update feed: https://dvirco1234.github.io/nivi/appcast.xml
- DMG: a GitHub Release asset, 6.4 MB
- What changed: [release-notes/0.2.0.md](../release-notes/0.2.0.md)

It is **self-signed and not notarised**. macOS blocks it on first launch and says
the app "cannot be checked" or is "damaged". It is neither.
[INSTALL.md](../INSTALL.md) walks through it.

0.2.0 carries every fix described under "Open work and known issues" below, plus
four from before them: dictations kept out of clipboard managers in Electron and
web apps (`c16eb77`), starting a recording no longer able to freeze the app
(`45251ec`), the main-thread watchdog (`4ae17de`), and signing outside iCloud
Drive (`dc6b345`).

**Self-update is still unproven.** 0.2.0 is the first version an older install
can be offered. Nobody has yet watched a 0.1.0 copy notice it and install it.

## Open work and known issues

**Clicking into a long transcript crashed the app. Fixed 2026-10-08.** Three crashes
on 1 October, all the same:

    CFRelease() called with NULL
    __NSCoreTypesetterCreateBaseLineFromAttributedString
    ...
    SelectionTextField.Cell._selectOrEdit

SwiftUI's `Text(...).textSelection(.enabled)` hands the whole string to AppKit's
field editor on the first click, and the field editor lays it out as one line. A
file transcript was saved as one line of 67,248 characters. Measured in a harness:
10,000 characters survive, 33,000 crash. Long text now goes through
`LongSelectableText`, a read-only `NSTextView`, which selected all 67,248
characters without trouble. File transcripts are also split into paragraphs now
(`TranscriptParagraphs`), so no paragraph is longer than 2,000 characters. A stray
unclosed right-to-left mark in that transcript looked suspicious and turned out to
be harmless.

**Transcripts can be saved as Text, Word, Rich Text or OpenDocument.** Added
2026-10-08. `TranscriptExporter` writes all four with `NSAttributedString`, so no
new library. Each paragraph is marked right to left or left to right from its own
letters, so Word lines Hebrew up on the right. Checked by rendering a Word file of
the real 45 minute Hebrew transcript through Quick Look. Not yet opened in Word
itself, which is not installed on this Mac.

**File transcripts have their own list.** The Transcribe a file tab lists every
file transcript still in history, and in History a file entry is headed by its file
name with a document icon. Before, a file's name sat in the same grey tag a
dictation uses for its app, so a file looked like any other entry.

**Transcription ran on the CPU from 24 to 25 September 2026.** Rebuilding
whisper.cpp from the iCloud path broke the Metal shaders (see patch 0002 in
[vendor/patches/](../vendor/patches/README.md)), so every pass ran on the CPU.
Short clips went from about 0.7 s to about 2 s. Fixed, and `make vendor` now fails
if it happens again.

**The Preferences window buttons only responded along their top edge. Fixed
2026-09-25.** Nivi used to move the close, minimise and zoom buttons down into the
sidebar panel itself. AppKit still decided where the mouse counted as over them
from its own position for them, 9 to 23 pt from the top, while they were drawn at
21 to 35 pt, and the bottom 3 pt of each was outside the titlebar and took no
clicks. An empty unified toolbar now makes the titlebar taller and AppKit places
the buttons itself at 19 to 33 pt, where its hover area and hit area are too. The
three Traffic lights sliders on the Layout tab are gone, because nothing reads
them any more. **Not yet checked by eye:** a window that never becomes active does
not draw its buttons, so the screenshot tool cannot show them.

**Nivi crashed mid-dictation because of a bug in the vendored ggml. Fixed
2026-09-24.** Two `SIGSEGV` crashes inside twenty minutes, both identical:

    EXC_BAD_ACCESS (SIGSEGV)  KERN_INVALID_ADDRESS at 0x0000000000000020
    ggml_backend_buft_get_alloc_size
    ggml_gallocr_alloc_graph
    ggml_backend_sched_alloc_graph
    whisper_decode_internal
    whisper_full

`ggml_gallocr_node_needs_realloc` asked whether the **new** graph's tensor was a
view, then indexed with a `buffer_id` saved from the **old** graph, where the
allocator writes `-1` for views. A tensor that stopped being a view between two
passes read `galloc->bufts[-1]`, got `NULL`, and read the fifth function pointer
of the struct: offset `0x20`.

Nivi provokes it because it asks one whisper context for two differently shaped
graphs all day: streaming passes with timestamps and a growing `audio_ctx`, then
a final pass with no timestamps and the model's full context. A harness that
alternates the two crashed on the 12th simulated dictation and survived 40 after
the fix. The fix is carried as a patch: see [vendor/patches/](../vendor/patches/).

This is why the crashes started recently. The profile in daily use moved to a
streaming mode on the large Hebrew model; plain `batch` never sets `audio_ctx`
and never reshapes the graph.

**`make vendor` silently copied no libraries at all, from 6 September to 24
September.** `vendor/whisper.cpp/build` is a symlink to `build.nosync`, added to
keep iCloud Drive off the build tree, and `find` does not follow symlinks. So the
copy step matched nothing, said nothing, and exited 0. whisper.cpp was rebuilt
every time and the app kept linking libraries built on 21 July. `make vendor` now
uses `find -L` and fails loudly if the libraries are not there afterwards.

**The build broke on its own on 16 September, with no change to Nivi.** A Command
Line Tools update repointed `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`
from the 26 series to `MacOSX27.0.sdk`. The bundled Swift toolchain targets
macosx26 and has no `SwiftUIMacros` plugin, so every SwiftUI view failed with
`plugin for module 'SwiftUIMacros' not found`. The Makefile now pins `SDKROOT` to
the SDK matching the running system.

**`batchFastFinish` has no accuracy baseline, and that blocks work on streaming.**
The mode transcribes while you speak and only handles the leftover tail when you
stop, so the wait at the end stays about the same however long you spoke. The trade
is accuracy: the model gets less context around each chunk boundary, and it never
makes one pass over the whole recording. How much that costs in Hebrew has never
been measured, and it is the judgement that decides whether the mode is worth
keeping.

This is an open issue and not just a missing test, because of what it blocks. There
is no baseline to compare against, so nobody can say whether a later change to
`StreamWindow`, the freeze rule, `audio_ctx` or the tail pass made Hebrew better or
worse. Streaming work done before this is measured is done blind.

What is needed: dictate the same few Hebrew passages twice, once with a profile set
to `batch` and once with the same profile set to `batchFastFinish`. Write down the
finish time and an honest read of the accuracy for each. Keep the passages so the
comparison can be repeated after a change. A rough note is worth much more than
nothing here. It does not need to be a formal benchmark.

**Sparkle self-update has never been proven end to end.** The feed is well-formed
and the EdDSA signature verifies independently, but no one has watched an app
notice a new version and install it. That needs two real releases. This is the
biggest untested piece of the pipeline.

**Notarisation is written but never run.** `Tools/notarize.sh` exists and takes
its skip path when Apple credentials are absent, which is always so far. The
hardened-runtime re-sign and `Resources/Nivi.entitlements` have never executed.
It costs $99 a year. It is the single biggest barrier to anyone else installing
the app, because the current first-launch experience says the app is damaged.

**A wedged CoreAudio call used to kill dictation until it recovered. Fixed
2026-09-14.** On 14 September one `start()` blocked inside CoreAudio for 27
minutes. The app's own log measured it: `audio start took 1658094 ms`. The
recorder had one serial queue, and `withDeadline` frees the caller but not the
queue, so the five recordings tried in the meantime never ran at all. Each waited
its eight seconds behind a call that was going nowhere and reported a timeout it
had done nothing to earn. They all completed at once when the audio daemon finally
replied, at 3 ms, 2 ms, 1 ms, 79 ms and 76 ms.

The trigger was outside Nivi. Its private aggregate device
`CADefaultDeviceAggregate-71607-7` had degenerated to `Input:No | Output:No`, and
`coreaudiod` stopped answering property queries about it. It only came unstuck
when a Bluetooth device connected and forced a rebuild: `Device 189 died!`.

`AudioRecorder` now groups the engine and its queue into a `MicrophoneSession` and
retires the whole session when a start times out, so the next recording gets a
queue of its own. A retired session checks before it opens the microphone, because
the call it belongs to may return minutes after the user was told it failed. This
has no core test: it is AVFoundation and dispatch, which a Foundation-only module
cannot reach. It has not yet been seen to work against a real wedged daemon,
because the wedge has never been reproduced on purpose.

**The CoreAudio story is an explanation, not a proof.** The app hung on
2026-09-06 and `coreaudiod` was at 68% CPU, dropping to 0% the moment Nivi was
killed. What was proven: the main-thread block that made it fatal, and the churn
that fed it (an `AVAudioEngine` built and destroyed per recording, 200 times in
2000 log lines, each one making CoreAudio build a hidden aggregate device). What
was **not** proven: that this churn is what drove `GetSubDevices` into an
unbounded spin. Measured improvement over 40 record cycles: `coreaudiod` after
went from 11.3% to 2.4%, worst main-thread stall from 183 ms to 46 ms.

**The watchdog used to quit the app every time the Mac slept. Fixed 2026-09-14.**
It fired twice in anger, and both times it was wrong. It measured with `Date()`,
which is wall-clock time, and a sleeping Mac freezes the process while the wall
clock keeps running. On the first tick after waking, a healthy app looked like one
that had been stuck for the whole sleep:

    nivi.log  2026-09-09T15:20:14Z ERROR Main thread has been stuck for 946s. Quitting
    pmset     2026-09-09 18:20:15 +0300 DarkWake from Deep Idle

Those are the same second. The five-second warning that a real stall produces
first had never once been written to the log, which is the other half of the
proof: the app went from healthy to 946 seconds in a single tick.

The rule now lives in `Sources/NiviCore/StallWatch.swift` and is covered by core
tests. Two guards have to agree before the app stops itself: elapsed time on
`ProcessInfo.processInfo.systemUptime`, which stops while the Mac sleeps, and the
number of readings the watch actually took, so one late tick is never enough. On
this Mac `systemUptime` reads 450,846 s awake against 1,024,042 s of wall clock
since boot, so the difference the fix depends on is real and large.

Still a judgement call: whether 45 seconds is the right threshold for a genuine
stall. That has never been measured.

**The `'nope'` microphone error could not be reproduced.** The log showed
`Could not select MacBook Pro Microphone (status 1852797029)`, which is
`kAudioHardwareIllegalOperationError`. It needs the hardware state the user was
in at the time, with a Logitech MeetUp and an iPhone microphone present and then
dropping out. The binding is now rarer and harmless when it fails. If those lines
come back, the agreed fallback is a single "preferred microphone" picker instead
of the ordered list.

**Light mode has never been reviewed.** The whole Preferences redesign was built
and checked in dark mode only. The colours are semantic, so it should follow, but
nobody has looked.

**PR 7 polish from the UI plan is not done.** Empty states, keyboard navigation
and VoiceOver. See [ui/2026-08-24-preferences-redesign-plan.md](ui/2026-08-24-preferences-redesign-plan.md).

**iPhone and Apple Watch are parked.** The blunt finding: app extensions cannot
open the microphone at all, so a custom keyboard can never hear you, and no
public API gives a seamless third-party dictation experience on iOS. Every other
trigger (Action Button, Control Center, Shortcuts, Siri, App Intents) can only
launch your app, not capture audio. The best proven design costs about two taps
plus one visible app switch. Apple Watch is worse: no Speech framework at all.
Full detail in [ios/](ios/) and [mobile/](mobile/). The cheap next step, before
spending anything, is dictating five mixed Hebrew and English sentences into
Apple's own dictation and comparing them against Nivi. If Apple is good enough
now, the project is unnecessary. Note also that building for iOS needs Xcode,
which is not installed on this Mac.

**Parakeet was investigated and not adopted.** It has no Hebrew, which is the
primary use case. See [parakeet/](parakeet/). The catalogue entries exist but
`isRunnable` is false and no engine was written.

## What the owner has not tested yet

These all work as far as the code goes, but nobody has confirmed them by using
the app. Several need making noise or dictating, which agents must not do.

- **Fast finish accuracy in Hebrew.** The mode works. Whether the accuracy cost
  is acceptable is a judgement only the owner can make, and it is the whole point
  of the feature.
- **Mute while recording.** The CoreAudio setter was proven to work by writing
  back the value already there, so nothing has ever actually been muted and
  restored in a real recording.
- **Trackpad haptics** on start and stop.
- **The typed-text input method**, in an app where paste misbehaves.
- **Word replacements end to end**: add a rule, dictate the trigger word, check
  the replacement lands.
- **Microphone priority failover**: drag a microphone to the top, dictate, check
  the log says `Recording from <name>`, then disconnect it and dictate again.

## What to watch in the log

`~/Library/Logs/Nivi/nivi.log`.

- `audio start took NNN ms` should stay under about 150 ms. If it creeps into
  seconds over a long session, CoreAudio is degrading again and there is now a
  number to point at.
- `Main thread has not answered for Ns` is the early warning that used to be
  completely invisible. It has still never been seen. Until it is, a
  `Main thread has been stuck` line should be treated as suspicious rather than
  believed.
- `Audio engine abandoned: ...` means a start timed out and the recorder threw the
  whole session away. One line is a bad moment for the audio daemon. Several in a
  session means something is wrong with it.
- `Could not select <mic>` means the microphone binding is failing again.
