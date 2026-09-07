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

Version 0.1.0, build 2, published 2026-09-02.

- Repo: `Dvirco1234/nivi`, public
- Download page: https://dvirco1234.github.io/nivi/
- Update feed: https://dvirco1234.github.io/nivi/appcast.xml
- DMG: a GitHub Release asset, 5.6 MB

It is **self-signed and not notarised**. macOS blocks it on first launch and says
the app "cannot be checked" or is "damaged". It is neither.
[INSTALL.md](../INSTALL.md) walks through it.

## Not yet released, and this is why 0.2.0 is wanted

Four fixes have landed on `main` since 0.1.0 went out. Anyone who downloads today
gets none of them.

- **Dictations still show in clipboard history** (`c16eb77`). The transient
  marker was only applied when the Accessibility API confirmed a text field had
  focus. In Electron and web apps, which is where most dictation goes, the
  focused element is an `AXGroup` or `AXWebArea` and that check says no. So the
  setting silently did nothing in Slack, Arc and VS Code.
- **The app could freeze with no way to quit it** (`45251ec`). An unqualified
  `Task { }` inside a `@MainActor` method inherits the main actor, so the
  blocking `engine.inputNode` call ran on the main thread with no time limit. One
  cold access measured 15 seconds, and there is no upper bound. The menu bar died
  with it, and because the app runs as an accessory it never appeared in Force
  Quit.
- **A watchdog now quits a wedged app** (`4ae17de`). It pings the main queue every
  second, logs after 5 seconds of silence, and stops the process after 45.
- **`make dev` could not sign at all** (`dc6b345`). The iCloud FinderInfo problem,
  described in [CLAUDE.md](../CLAUDE.md).

Cutting 0.2.0 also finally tests the update path, which has never been proven.

## Open work and known issues

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

**The CoreAudio story is an explanation, not a proof.** The app hung on
2026-09-06 and `coreaudiod` was at 68% CPU, dropping to 0% the moment Nivi was
killed. What was proven: the main-thread block that made it fatal, and the churn
that fed it (an `AVAudioEngine` built and destroyed per recording, 200 times in
2000 log lines, each one making CoreAudio build a hidden aggregate device). What
was **not** proven: that this churn is what drove `GetSubDevices` into an
unbounded spin. Measured improvement over 40 record cycles: `coreaudiod` after
went from 11.3% to 2.4%, worst main-thread stall from 183 ms to 46 ms.

**The 45 second watchdog threshold has never fired in anger.** If some legitimate
operation ever blocks the main thread that long, the app quits on its own. That
is a judgement call, not a measurement.

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
  completely invisible.
- `Could not select <mic>` means the microphone binding is failing again.
