# Handoff

A map of this project for someone picking it up. Every link points at a real
file. Read this first, then follow the links you need.

This file is a map, not an explanation. The explanations live in the documents it
points to.

## Start here, in this order

| Read | For |
|---|---|
| [CLAUDE.md](../CLAUDE.md) | How to work in this repo. The build and safety rules are hard rules. |
| [docs/state-of-the-project.md](state-of-the-project.md) | What is built, what is released, what is open, what is untested. |
| [docs/architecture.md](architecture.md) | How the code fits together, and what a change must not break. |
| [docs/decisions.md](decisions.md) | Settled calls and why. Do not reopen without a reason. |

Also installed globally, outside this repo:
`~/.claude/skills/macos-app-dev/SKILL.md`. It covers building without Xcode,
code signing, the macOS permission traps, and how to verify the app visually
without taking over the owner's machine. Read it before any of that work.

## What Nivi is

An offline dictation app for macOS. You hold a hotkey, speak, and the text is
pasted into whatever app you were typing in. It runs Whisper models locally, so
nothing is sent to a server. See [README.md](../README.md) for the user-facing
description and [INSTALL.md](../INSTALL.md) for what an installer does.

The app was called Dictato until 27 August 2026. The repository directory is
still named `dictato`. The app, the bundle id and the GitHub repo are all Nivi.

## The code

Two Swift targets plus a C shim. `NiviCore` is pure logic with no AppKit and no
AVFoundation, which is what makes it testable without Xcode.

### The dictation path

Follow these in order to understand one dictation end to end.

| File | Job |
|---|---|
| [HotkeyRouter.swift](../Sources/Nivi/HotkeyRouter.swift) | Watches for the hotkey. One detector per modifier key. |
| [DictationController.swift](../Sources/Nivi/DictationController.swift) | The state machine and the orchestrator. Start here for almost any change. |
| [AudioRecorder.swift](../Sources/Nivi/AudioRecorder.swift) | Records 16 kHz mono samples. Keeps one engine between recordings. |
| [StreamingTranscriber.swift](../Sources/Nivi/StreamingTranscriber.swift) | Transcribes while you are still speaking. |
| [WhisperCppRecognizer.swift](../Sources/Nivi/WhisperCppRecognizer.swift) | The whisper.cpp call itself. |
| [RecognizerCache.swift](../Sources/Nivi/RecognizerCache.swift) | Holds a loaded model, and releases it when idle. |
| [TextInserter.swift](../Sources/Nivi/TextInserter.swift) | Puts the text in the target app, by paste or by typing. |

The pure pieces behind streaming:

| File | Job |
|---|---|
| [StreamWindow.swift](../Sources/NiviCore/StreamWindow.swift) | Freezes settled text and slides the window forward. |
| [StablePrefixTracker.swift](../Sources/NiviCore/StablePrefixTracker.swift) | Turns repeated transcripts into a prefix that only grows. Used by `inAppLive` only. |
| [AppendOnlyTail.swift](../Sources/NiviCore/AppendOnlyTail.swift) | Finds what has not been typed yet. Used by `inAppLive` only. |
| [AudioContext.swift](../Sources/NiviCore/AudioContext.swift) | Sizes `audio_ctx`. The multiple-of-4 rule lives here and is not negotiable. |
| [TranscriptCleaning.swift](../Sources/NiviCore/TranscriptCleaning.swift) | Removes whisper's sound notes such as `(people chattering)`. |
| [TranscriptFinishing.swift](../Sources/NiviCore/TranscriptFinishing.swift) | Cleaning then word replacement, in that order, in one place. |

### Settings, profiles and models

| File | Job |
|---|---|
| [Settings.swift](../Sources/NiviCore/Settings.swift) | Every setting key, and the `InsertionMode` enum. |
| [DictationProfile.swift](../Sources/NiviCore/DictationProfile.swift) | A profile ties one hotkey to one model and one language. |
| [ManagedModel.swift](../Sources/NiviCore/ManagedModel.swift) | The model catalogue. |
| [ModelStore.swift](../Sources/Nivi/ModelStore.swift) | Downloading and installing models. |
| [MicrophonePriority.swift](../Sources/NiviCore/MicrophonePriority.swift) | Which microphone to try first. |

### Preferences

The design system is the thing to read before adding any row or tab.

| File | Job |
|---|---|
| [PrefKit.swift](../Sources/Nivi/Preferences/PrefKit.swift) | `PrefPage`, `PrefGroup`, `PrefRow` and the typed rows. Every tab is built from these. |
| [PrefTheme.swift](../Sources/Nivi/Preferences/PrefTheme.swift) | Colours and spacing tokens. |
| [SettingsView.swift](../Sources/Nivi/Preferences/SettingsView.swift) | The sidebar, the tab list, and the window background. |
| [PreferencesWindow.swift](../Sources/Nivi/PreferencesWindow.swift) | The window itself, and the traffic lights pinned into the sidebar. |
| [UITuning.swift](../Sources/Nivi/UITuning.swift) | Layout numbers, adjustable live from the Layout tab. |

Tabs are in [Sources/Nivi/Preferences/](../Sources/Nivi/Preferences/), one file
each.

### Recording displays

| File | Job |
|---|---|
| [OverlayView.swift](../Sources/Nivi/Overlay/OverlayView.swift) | The floating panel, including the moving border glow and the timer. |
| [NotchOverlayView.swift](../Sources/Nivi/Overlay/NotchOverlayView.swift) | The bar that merges with the MacBook camera notch. |
| [OverlayModel.swift](../Sources/Nivi/Overlay/OverlayModel.swift) | The state both displays read. |

### Safety nets

Added after the app froze on 6 September. Read
[docs/architecture.md](architecture.md) for why.

| File | Job |
|---|---|
| [WithDeadline.swift](../Sources/Nivi/WithDeadline.swift) | Runs blocking work off the main thread and gives up after N seconds. It does not free the queue; read the note on it. |
| [MainThreadWatchdog.swift](../Sources/Nivi/MainThreadWatchdog.swift) | Logs after 5 seconds of a stuck main thread, quits the app after 45. |
| [StallWatch.swift](../Sources/NiviCore/StallWatch.swift) | The watchdog's rule, kept pure so it can be tested. Explains why sleep used to look like a stall. |

## Build, test and release

| File | Job |
|---|---|
| [Makefile](../Makefile) | Every build target. `make dev` is the one you want. |
| [Tools/run-core-tests.sh](../Tools/run-core-tests.sh) | The test harness. Must print `ALL CORE CHECKS PASSED`. |
| [Tools/core-tests/main.swift](../Tools/core-tests/main.swift) | Every test. Plain `check(cond, msg)` asserts, no XCTest. |
| [Tools/publish-release.sh](../Tools/publish-release.sh) | Uploads a release. Two steps, `feed` then `upload`, and the order matters. |
| [docs/release-pipeline.md](release-pipeline.md) | How releasing works, and the one-time setup. |
| [vendor/patches/](../vendor/patches/) | Fixes carried on top of whisper.cpp v1.7.2. `make vendor` applies them. Read the README before touching the pin. |

Safe ways to look at the UI without driving the running app:

| File | Job |
|---|---|
| [Tools/make-pref-shots.sh](../Tools/make-pref-shots.sh) | Renders real Preferences tabs in a throwaway app and photographs them. |
| [Tools/make-recording-thumbnails.sh](../Tools/make-recording-thumbnails.sh) | Regenerates the Panel and Notch pictures shown in Preferences. |

Use these instead of clicking. See the skill for why.

## Research and history

Kept because the reasoning is often more useful than the result.

| Folder | What is in it |
|---|---|
| [docs/streaming/](streaming/) | How to finish a long transcription fast, and what it costs. |
| [docs/parakeet/](parakeet/) | Why the Parakeet model was investigated and not adopted. No Hebrew. |
| [docs/ios/](ios/), [docs/mobile/](mobile/) | Whether iPhone and Apple Watch are possible. Short answer, not seamlessly. |
| [docs/ui/](ui/) | The Preferences redesign plan. |
| [docs/naming/](naming/) | How the name Nivi was chosen, and every name that was rejected. |
| [docs/superpowers/](superpowers/) | Design specs and plans from July and early August. **History, not current.** |

The `docs/superpowers/` notes stop at milestone 2d.1 and describe what was
planned. Some of it changed while being built.
[docs/architecture.md](architecture.md) is the authority where they disagree.
See [docs/superpowers/README.md](superpowers/README.md).

## Things that live outside the repo

A new session will not find these by reading code.

| What | Where |
|---|---|
| The installed app | `/Applications/Nivi.app` |
| Models, history, layout tuning | `~/Library/Application Support/Nivi/` |
| Logs | `~/Library/Logs/Nivi/nivi.log` |
| Settings | the `com.dvir.nivi` defaults domain |
| Signing identity | `Nivi Self-Signed` in the login keychain |
| Sparkle update signing key | login keychain, "Private key for signing Sparkle updates". Backed up by the owner. Losing it means no existing install can ever update. |
| GitHub release token | login keychain, account `nivi-release`, service `nivi-gh-token` |
| Private working notes | `~/personal/dev-workspace`, a separate private repo. `.claude/` and `.superpowers/sdd/` here are symlinks into it. |
| Source repo | `Dvirco1234/nivi`, public |
| Download page and update feed | https://dvirco1234.github.io/nivi/ |

Note that `~/personal` is a symlink to a folder inside iCloud Drive, so this repo
has two valid paths. There is one checkout, not two. That also causes a code
signing trap, explained in [CLAUDE.md](../CLAUDE.md).

## Where the project stands

Version 0.1.0 is released and downloadable. It is signed by its author and not
notarised by Apple, so the first launch shows a warning.

Four fixes have landed since 0.1.0 and are not in anyone's hands yet: the
clipboard history fix, the audio main-thread fix, the watchdog, and the iCloud
signing fix. A 0.2.0 is wanted.

The full picture, including every open issue, is in
[docs/state-of-the-project.md](state-of-the-project.md). The two most valuable
next steps, in order:

1. **Measure the fast finish accuracy in Hebrew.** It is the first open issue in
   that document. Until it is measured there is no baseline, so no later change
   to the streaming path can be judged better or worse.
2. **Cut 0.2.0.** It ships the four fixes and is the only way to find out whether
   Sparkle's self-update actually works, which has never been proven.

## What only the owner can decide

The documents carry the reasoning. They do not carry taste. Design and wording
calls were made by the owner throughout, often by looking at a screenshot and
saying what was wrong. Expect to work the same way rather than guessing.

Three examples of decisions that went back and forth before settling, so that
they are not accidentally undone: the app icon is grey with a white letter and a
soft round highlight near the top; the recording panel is deliberately small with
a thin moving glow; the notch bar is exactly as tall as the camera notch. All
three are recorded in [docs/decisions.md](decisions.md).
