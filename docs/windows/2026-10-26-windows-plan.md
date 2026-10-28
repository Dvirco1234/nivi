# Nivi for Windows: plan

Date: 2026-10-26. Status: plan only. No code changed, nothing built.

This document answers four questions:

1. How much of the Mac app can a Windows version reuse?
2. Which language and toolkit should it be written in?
3. Which Windows PCs are fast enough to make it worth using?
4. In what order should it be built, and where do we stop and decide?

Read these first if you have not: [../architecture.md](../architecture.md),
[../decisions.md](../decisions.md),
[../streaming/2026-08-24-fast-finish-transcription.md](../streaming/2026-08-24-fast-finish-transcription.md)
and [../parakeet/2026-08-24-parakeet-integration-options.md](../parakeet/2026-08-24-parakeet-integration-options.md).
The fast-finish streaming plan that is being written at the same time,
[../streaming/2026-10-26-fast-finish-plan.md](../streaming/2026-10-26-fast-finish-plan.md),
covers how streaming should change. This plan does not repeat it. It only says
when the Windows build picks that work up.

## How to read the numbers

Every number is marked one of two ways:

- **[measured]** means someone else measured it. The source link is next to it.
- **[estimate]** means it is my own arithmetic or judgement. Treat it as a guess
  to be checked in the spike (milestone 2).

Speed is given as `r`, the same way the streaming doc does: **seconds of compute
per second of audio**. `r = 0.1` means a 60 second dictation takes 6 seconds to
transcribe in one pass. "Real time factor" and "RTF" mean the same thing.
"30x real time" is `r = 0.033`.

## Summary

**Recommended stack: a Rust core with a Tauri v2 shell and a React settings UI,
running whisper.cpp through a thin binding we own, and borrowing the proven
Windows parts from Handy, an open-source app that already does this.**

Why, in four lines:

- Handy ([cjpais/Handy](https://github.com/cjpais/Handy), MIT license) is a
  push-to-talk dictation app on Tauri v2, Rust and React. It already solves
  modifier-only hotkeys, paste, Vulkan whisper and auto-start on Windows. We can
  depend on its crates and read its code instead of finding every trap again.
- The settings UI is about half the work. In Tauri it is React and TypeScript,
  which the owner already writes every day at work.
- Swift on Windows would let us reuse `NiviCore` as it is, but the UI options are
  thin and its best-known app, Arc, is being shut down. Too much risk for one
  part-time developer.
- C# and .NET is the solid second choice. Pick it if the owner would rather learn
  C# than Rust.

**The hardware answer depends on the language you dictate in.**

- Hebrew needs the ivrit-ai Large v3 Turbo model. That model needs a GPU on
  Windows. A recent NVIDIA, AMD or Intel Arc graphics card is fine. A recent
  built-in laptop GPU (Radeon 780M and newer, Intel Core Ultra) is borderline and
  must be measured. A CPU alone is too slow for Hebrew.
- English runs well on a CPU alone, with Whisper Small, or much faster with
  Parakeet (no Hebrew).

**The plan is 8 milestones, about 6 to 8 months at roughly 10 hours a week
[estimate].** Milestone 1 freezes the shared formats. Milestone 2 is a spike on
three real Windows machines, with a go / no-go decision before the full build.

---

## Part 1: what already exists and can be reused

The Mac app has two Swift targets:

- `Sources/NiviCore/`: 28 files, about 2,100 lines. Pure logic, Foundation only.
  Covered by `Tools/core-tests/main.swift`, 874 lines and 302 checks.
- `Sources/Nivi/`: everything that touches macOS. AppKit, SwiftUI, AVFoundation,
  CoreAudio, Accessibility, Sparkle, Metal.

The labels below mean:

- **reuse as-is**: same logic, same tests, only translated into the new language
  (or compiled directly, if the stack is Swift).
- **port logic**: the idea and most of the code carry over, but one part is
  platform-specific and changes.
- **rewrite**: the job is the same, but the Windows API is different enough that
  the code is new.
- **drop**: not needed on Windows.

### `Sources/NiviCore/`, file by file

This already exists and is tested. On Windows we only need to translate it and
run the same test cases against the translation.

| File | Label | Notes for Windows |
|---|---|---|
| `AppendOnlyTail.swift` | reuse as-is | Word-level seam finder for `inAppLive`. |
| `AudioChunkPlanner.swift` | reuse as-is | Cuts long files at quiet moments. |
| `AudioContext.swift` | reuse as-is | The multiple-of-4 rule came from a Metal assert. Keep it on Windows anyway: it costs nothing, and nobody has checked Vulkan or CUDA. The stress test in milestone 2 checks it. |
| `ChunkedTranscription.swift` | reuse as-is | Joins chunk texts. |
| `DictationProfile.swift` | reuse as-is | Same JSON shape. Only the hotkey inside changes, see `HotkeyBinding`. |
| `DictationStateMachine.swift` | reuse as-is | Six states, same events. |
| `DurationFormatting.swift` | reuse as-is | |
| `HistoryFiltering.swift` | reuse as-is | |
| `HistoryRecord.swift` | reuse as-is | `history.jsonl` keeps the exact same format. `sourceName` holds the front app's name, taken from the window's process on Windows. |
| `HistoryRetention.swift` | reuse as-is | |
| `HotkeyBinding.swift` | port logic | `ModifierKey` names Mac keys (`rightCommand`) and stores Mac key codes (54, 55, 61, 62). `keyCombo` stores `NSEvent` modifier bits. Windows needs its own key list (right Ctrl, right Shift, right Alt, the Windows key) using Windows virtual-key codes. The JSON shape gets a platform field. See Part 5. |
| `LegacyNameMigration.swift` | drop | The Dictato rename never happened on Windows. |
| `ManagedModel.swift` | port logic | Reuse the types. The seeded catalog changes: Windows wants quantized variants (q5_0, q8_0) and a hint for which backend each model needs. The Parakeet entries point at Core ML repos and need ONNX sources instead. |
| `MicrophonePriority.swift` | reuse as-is | It works on opaque id strings. Windows endpoint ids are strings too. |
| `ModelCatalogStore.swift` | port logic | Merge-presets logic carries over. `ModelPaths` hard-codes `~/Library/Application Support/Nivi`. Windows uses `%LOCALAPPDATA%\Nivi\models`. |
| `ModelSpec.swift` | reuse as-is | The ggml magic number and size check work on any file. `RecordingDisplay.notch` has no meaning on Windows; see the overlay section. |
| `ModifierTapDetector.swift` | reuse as-is | Pure logic: down, up, "another key was pressed". It needs no Mac APIs. |
| `Settings.swift` | port logic | The keys, defaults and `InsertionMode` / `TextInputMethod` enums carry over. The storage does not: it sits on `UserDefaults`. Windows stores a JSON file. See Part 5. |
| `StablePrefixTracker.swift` | reuse as-is | |
| `StallWatch.swift` | port logic | The rule carries over. It needs a clock that stops during sleep. On Windows that is `QueryUnbiasedInterruptTime`. |
| `StreamWindow.swift` | reuse as-is | |
| `TranscribableFormat.swift` | port logic | The extension list matches what Apple's decoders read. Windows Media Foundation reads a different set (no `.caf`, adds `.wma`). |
| `TranscriptCleaning.swift` | reuse as-is | |
| `TranscriptDocument.swift` | reuse as-is | Paragraph splitting, text direction and file names are pure. |
| `TranscriptFinishing.swift` | reuse as-is | The one text pipeline. Keep the invariant: everything shown, pasted and saved goes through it. |
| `TranscriptSegment.swift` | reuse as-is | |
| `TypedNumber.swift` | reuse as-is | |
| `WordReplacement.swift` | reuse as-is | Stored as the same JSON. |

So 20 of 28 files carry over unchanged in logic, 7 need a platform-specific
change, and 1 is dropped.

The 302 checks in `Tools/core-tests/main.swift` are the other big asset. They
define what "correct" means for `StreamWindow`, cleaning, word replacement and
the rest. Milestone 1 turns the important ones into shared test files, so the
Windows code is checked against exactly the same cases. See Part 5.

### `Sources/Nivi/`, file by file

| File | Label | Windows replacement |
|---|---|---|
| `main.swift`, `AppDelegate.swift` | rewrite | Tauri app setup. |
| `DictationController.swift` (581 lines) | port logic | The orchestrator. The flow, the `recordingGeneration` check, and the "read the profile before `transition`" trap all carry over. Timers and threading change. Port it carefully, line by line, with the architecture doc open. |
| `HotkeyRouter.swift` | rewrite | Low-level keyboard hook or Raw Input on its own thread. See Part 3. |
| `AudioRecorder.swift` (399 lines) | rewrite | WASAPI through `cpal`, plus resampling to 16 kHz mono. Keep the design rules: never block the UI thread, a deadline on start, retire a stuck session. |
| `MicrophoneDevices.swift` | rewrite | `IMMDeviceEnumerator`, plus `IMMNotificationClient` for plug and unplug. |
| `WhisperCppRecognizer.swift` | port logic | It uses only 7 whisper.cpp functions. The same calls through Rust FFI. Keep "free on the inference queue". |
| `RecognizerCache.swift` | port logic | LRU of loaded models, idle unload. Plain logic. |
| `StreamingTranscriber.swift` | port logic | Foundation only today. The loop carries over. Pick up the changes from the 2026-10-26 fast-finish plan when milestone 5 starts. |
| `TextInserter.swift` | rewrite | Clipboard plus Ctrl+V, or `SendInput` with Unicode. See Part 3. |
| `ModelManager.swift` | port logic | Download with resume and ggml validation. `reqwest` in Rust. |
| `ModelStore.swift`, `ProfileStore.swift`, `History/HistoryStore.swift` | port logic | Foundation only, apart from `ObservableObject`. The logic moves to Rust, and the UI reads it through Tauri commands. |
| `ModelTester.swift` | port logic | |
| `FileTranscription/FileTranscriptionService.swift` | port logic | The chunk loop carries over. |
| `FileTranscription/AudioFileDecoder.swift` | rewrite | Media Foundation, or the `symphonia` crate. |
| `TranscriptExporter.swift` | rewrite | macOS writes `.docx`, `.rtf` and `.odt` for free through `NSAttributedString`. Windows has no equivalent. `.txt` is trivial. `.docx` needs a small writer (the `docx-rs` crate). `.rtf` and `.odt` can wait. |
| `MenuBarController.swift`, `LanguageGlyph.swift` | rewrite | Tray icon and menu. The language glyph becomes a set of tray icons. |
| `Overlay/*` (5 files) | rewrite | A transparent, always-on-top window that never takes focus. Panel only. |
| `Preferences/*` (15 files), `PreferencesWindow.swift` | rewrite | React pages in Tauri. The page structure and wording carry over: `PrefPage`, `PrefGroup`, `PrefRow` become React components with the same names. |
| `InterfaceSettings.swift` | rewrite | Light or dark theme only. No Dock icon on Windows. |
| `LoginItem.swift` | rewrite | `tauri-plugin-autostart` (HKCU Run key), or a `StartupTask` under MSIX. |
| `UpdateController.swift` | rewrite | See Part 3, updates. |
| `PermissionManager.swift` | rewrite, much smaller | Windows has no Accessibility or Input Monitoring grants. Only the microphone privacy switch. |
| `SystemVolume.swift` | rewrite | `IAudioEndpointVolume` on the default output device. |
| `SoundPlayer.swift` | rewrite | `PlaySound` or `rodio`. |
| `Haptics.swift` | drop | |
| `MainThreadWatchdog.swift`, `WithDeadline.swift` | port logic | Same rules, new threads. |
| `Log.swift` | rewrite | The `tracing` crate to `%LOCALAPPDATA%\Nivi\logs\nivi.log`. |
| `DeveloperMode.swift`, `UITuning.swift` | port logic or drop | Keep developer tabs out of release builds. `UITuning` can wait. |

### whisper.cpp and the two patches

whisper.cpp is the speech engine on both platforms. It already builds on
Windows with CUDA, Vulkan and CPU backends. **This already exists; we only need
a build of it for Windows.**

The two carried patches:

| Patch | Metal-specific? | Needed on Windows? |
|---|---|---|
| `0001-ggml-alloc-guard-stale-buffer-id.patch` | No. The bug is in ggml's graph allocator, shared by every backend. | Yes, if we built v1.7.2. But the patch README says upstream ggml fixed it later. |
| `0002-metal-embed-works-in-paths-with-spaces.patch` | Yes. It fixes how the Metal shader file is glued together. | No. |

**Recommendation: build Windows from a newer whisper.cpp, 1.8.3 or later, not
1.7.2.** Version 1.8.3 is the one that made Vulkan use built-in laptop GPUs
([PR #3492](https://github.com/ggml-org/whisper.cpp/pull/3492)), and the Windows
hardware story depends on that. Before trusting it, check that the upstream fix
for patch 0001 is in that release. Then port `Tools/whisper-stress/run.sh` and
run it on each backend. That test is the real proof, on any version.

This leaves the Mac on v1.7.2 and Windows on 1.8.x for a while. That is a known
cost. It is also a reason to move the Mac pin forward later, which the patch
README already suggests.

### Models

**The catalog and the download already exist; we only need Windows paths and a
few more entries.**

- The ivrit-ai model file is the same ggml file on both platforms.
- Add quantized versions of Large v3 Turbo for weaker GPUs. A quantized model
  stores its weights in fewer bits: smaller, faster, slightly less accurate.
  `whisper.cpp`'s own repo publishes `ggml-large-v3-turbo-q5_0.bin` and
  `-q8_0.bin`. For ivrit-ai there is no published quantized file that I found.
  We would make one with whisper.cpp's `quantize` tool and host it. Check the
  model's license allows that (open question).
- Add Whisper Base and Small for CPU-only machines.
- Add Parakeet for English on CPU, as an ONNX model, later (milestone 8).

### Settings, profiles and history

These formats already exist. We only need to write them down as a contract and
make Windows follow it. See Part 5.

---

## Part 2: which stack

### The three options

**(a) Swift on Windows, sharing `NiviCore` directly.**

What is true today:

- Swift 6.4.1 is current and ships for Windows x64 and ARM64, installed with
  `winget install --id Swift.Toolchain` plus Visual Studio 2022
  ([swift.org](https://swift.org/install/windows/)).
- Swift has a Windows workgroup since January 2026
  ([announcement](https://swift.org/blog/announcing-windows-workgroup/)).
- Foundation on Windows is now swift-foundation, so `JSONEncoder`, `Date` and
  `Data` behave like on the Mac
  ([forum](https://forums.swift.org/t/swift-foundation-now-available/73530)).
- `UserDefaults` works but writes a plist straight into `AppData\Local`
  ([forum](https://forums.swift.org/t/userdefaults-standard-on-windows-stores-plist-file-in-appdata-local/81072)).
- Combine does not exist outside Apple. `ObservableObject` would need replacing.
- Static linking of the Swift runtime is not supported on Windows. The app ships
  the Swift and ICU DLLs next to it
  ([forum](https://forums.swift.org/t/swift-required-dlls-on-windows-10/49000)).
- UI choices: WinUI 3 through The Browser Company's `swift-winrt` bindings,
  SwiftCrossUI with a WinUI backend
  ([repo](https://github.com/stackotter/swift-cross-ui)), or raw Win32 through
  the `WinSDK` module. None of them runs the existing SwiftUI code.
- Arc for Windows was the flagship Swift Windows app. It is in maintenance mode
  and shuts down on 22 December 2026
  ([Wikipedia](https://en.wikipedia.org/wiki/Arc_(web_browser))).

What it buys: all of `NiviCore` and its 302 checks compile as they are, plus
about nine Foundation-only app files. Probably 3,000 lines or more of tested code
reused without translation [estimate].

What it costs: the whole UI, hotkey, audio, paste, tray and overlay are still
new code, now written against Win32 or WinRT from Swift, with the smallest
community and the thinnest tooling of the three options.

**(b) Rust core with a native shell (Tauri v2).**

- `whisper-rs` 0.16.0 has `cuda` and `vulkan` features. Its GitHub repo is
  archived and work moved to Codeberg
  ([docs.rs](https://docs.rs/crate/whisper-rs/latest)).
- `cpal` uses WASAPI by default on Windows
  ([docs.rs](https://docs.rs/crate/cpal/latest)).
- Tauri's global-shortcut plugin uses `RegisterHotKey`. It reports key down and
  key up, but cannot do modifier-only hotkeys
  ([Tauri docs](https://v2.tauri.app/plugin/global-shortcut/)). So it cannot do
  Nivi's double-tap of right Ctrl.
- `handy-keys` 0.3.4 can. It supports modifier-only hotkeys, reports press and
  release, and uses a low-level keyboard hook on Windows
  ([docs.rs](https://docs.rs/handy-keys)).
- Handy 0.9.8 is the reference app. Tauri v2, React, Rust. Hotkeys through
  `handy-keys`. Paste through the clipboard and then restore it. Speech through
  `transcribe-cpp`: Vulkan on Windows x64, CPU on Windows ARM64, and Parakeet V3
  for CPU users. Auto-start and updates through Tauri plugins
  ([Cargo.toml](https://raw.githubusercontent.com/cjpais/Handy/main/src-tauri/Cargo.toml)).

What it buys: a working reference for every hard Windows piece, a web UI the
owner already knows, Tauri's installer and updater, and a small binary.

What it costs: `NiviCore` is translated by hand into Rust, about 2,100 lines plus
the tests. The owner learns Rust. Two codebases drift unless the shared test
files keep them honest.

**(c) C# and .NET (WinUI 3 or WPF), with whisper.cpp through Whisper.net.**

- Whisper.net 1.9.1 ships runtime packages for CPU, CUDA 12 and 13, Vulkan,
  OpenVINO and more, and picks one at run time
  ([GitHub](https://github.com/sandrohanea/whisper.net),
  [NuGet](https://www.nuget.org/packages/whisper.net.runtime.vulkan)).
- WinUI 3 supports NativeAOT since Windows App SDK 1.6, which starts faster and
  ships smaller
  ([Microsoft](https://blogs.windows.com/windowsdeveloper/2024/09/04/whats-new-in-windows-app-sdk-1-6/)).
- `H.NotifyIcon` is a maintained tray library for WPF and WinUI.
- Velopack, the best Windows updater, is built for .NET first.

What it buys: the most Windows-native result, the best debugger, and Microsoft's
own docs for every API. Hotkeys and `SendInput` are a few lines of P/Invoke.

What it costs: `NiviCore` is translated into C#. The owner learns C# and XAML.
Whisper.net decides which whisper.cpp version we get, and we cannot carry our own
patch on top as easily.

### Comparison

Scores are my judgement [estimate]. 5 is best.

| | (a) Swift | (b) Rust + Tauri | (c) C# / .NET |
|---|---|---|---|
| Code reused from the Mac | 5. Core compiles as is. | 2. Translate core and tests. | 2. Translate core and tests. |
| Effort for the whole app | 2. UI and Win32 from Swift are slow going. | 4. Handy shows the way. UI in React. | 3. Familiar platform, unfamiliar language. |
| Hotkey and paste reliability | 3. Same Win32 calls, no reference app. | 4. Proven in Handy on real users. | 4. Same Win32 calls, easiest to debug. |
| Packaging and updates | 2. Ship runtime DLLs, no updater. | 4. Tauri bundler and updater built in. | 5. Velopack, MSIX tooling. |
| Maintenance by one part-time developer | 2. Smallest community, showcase app shutting down. | 4. Large community, owner knows the UI half. | 4. Large community. |
| Owner's existing skills | 4. Knows Swift from this app. | 4. Knows React and TypeScript. Rust is new. | 2. C# and XAML are new. |
| **Total** | **18** | **22** | **20** |

### Recommendation

**Pick (b): a Rust core plus Tauri v2, with a React UI.**

Three details that matter:

1. **Own the whisper.cpp binding.** Nivi uses only 7 whisper.cpp functions. A
   small `nivi-whisper-sys` crate that builds a pinned whisper.cpp with `cmake`
   and exposes those 7 calls is a few hundred lines. That is the same approach
   as `Sources/CWhisper/` on the Mac. It keeps the pin and any patch under our
   control, which the Mac history shows we need. Use `whisper-rs` or
   `transcribe-cpp` only as references.
2. **Depend on Handy's crates, do not fork the whole app.** Use `handy-keys` for
   the hotkey. Read Handy's paste, overlay and auto-start code before writing
   ours. Do not take Handy's settings model or UI: Nivi's profiles, history and
   catalog already exist and are the contract.
3. **Keep the Mac app in Swift.** This plan does not touch it. The two apps share
   formats and test cases, not source code.

Pick (c) instead if the owner would rather learn C# than Rust. Everything in
Parts 3 to 6 still applies.

There is one more option the owner should decide on first: **do not build it.**
Handy already runs on Windows and is free. If the goal is only "friends on
Windows can dictate English", sending them Handy costs nothing. Nivi for Windows
earns its cost through what Handy lacks: Hebrew as the default, a hotkey per
language, fast finish, file transcription and history. See open questions.

---

## Part 3: the Windows pieces

### Global hotkey

Nivi's default is a modifier tap: double-tap a modifier to start, tap once to
stop, Esc to cancel. Windows has three ways to watch keys.

| Method | Modifier-only taps? | Key up? | Can block keys? | Catch |
|---|---|---|---|---|
| `RegisterHotKey` | No. It needs a normal key. | No | Yes | Fails if another app took the combination ([Microsoft](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey)). |
| Low-level keyboard hook (`WH_KEYBOARD_LL`) | Yes | Yes | Yes | If the callback is slow, Windows removes the hook **silently**. Since Windows 10 1709 the limit is at most 1 second ([Microsoft](https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelkeyboardproc)). |
| Raw Input with `RIDEV_INPUTSINK` | Yes | Yes | No | Observe only. There is no timeout to break it. |

Nivi only needs to **observe** keys. It never blocks them, on the Mac either.

**Plan:**

- Use the low-level hook through `handy-keys` first, because it is proven.
- Run it on its own thread with its own message loop. The callback does nothing
  except push the event into a channel and return. This is what Microsoft
  advises, and it keeps us far below the 1 second limit even when inference is
  busy.
- The removal is silent, so build a check. After resume from sleep, and every
  few minutes, re-install the hook. This is the Windows version of what
  `DictationController` already does on `didWakeNotification`.
- In the spike, also try Raw Input. If it sees right Ctrl reliably, it is the
  more robust choice, because it has no timeout.
- `ModifierTapDetector` is the same pure logic. Only the event source changes.

**Default hotkey: double-tap right Ctrl.** Not right Alt. On many keyboard
layouts, Hebrew included, right Alt is AltGr, which types characters. Tapping it
alone would also open the menu bar in many apps.

### Text insertion

Two ways, the same two Nivi has on the Mac.

**Clipboard plus Ctrl+V (default).**

1. Save the current clipboard.
2. Put the text on the clipboard. Also add the named format
   `ExcludeClipboardContentFromMonitorProcessing`. That keeps the dictation out
   of Windows clipboard history (Win+V) and out of cloud sync
   ([Microsoft](https://learn.microsoft.com/en-us/windows/win32/dataxchg/clipboard-formats)).
   This is the Windows version of the `org.nspasteboard.TransientType` marker.
3. Send Ctrl+V with `SendInput`.
4. Restore the old clipboard after a delay. Handy found that restoring too early
   under load pastes the wrong text. So the delay must be generous, and tested.

**Typed characters (`SendInput` with `KEYEVENTF_UNICODE`).** Each character is a
key down and a key up with the character in the scan code field. Use it for "Type
it out" and for `inAppLive`. Carry over two Mac lessons: send whole characters,
never half of an emoji's surrogate pair, and pace the events, because Electron
apps drop a burst.

**Where neither works:**

- **Apps running as administrator.** Windows blocks input from a normal app to an
  elevated one. This is called UIPI. The way around it, `uiAccess="true"`, needs
  a signed app installed under Program Files
  ([Microsoft](https://technet.microsoft.com/en-us/library/jj852244.aspx)). That
  does not fit a per-user install. Plan: detect that the front window is
  elevated, leave the text on the clipboard, and say so in the overlay. The same
  `copiedToClipboard` outcome the Mac already has.
- **Games** with their own input handling or anti-cheat. Out of scope.
- **Remote Desktop and terminals.** Nobody has published how they behave. Test
  Windows Terminal and an RDP window in the spike.

### Microphone

- WASAPI in shared mode through `cpal`. Resample to 16 kHz mono `Float32`.
- Enumerate devices with `IMMDeviceEnumerator` and watch plug and unplug with
  `IMMNotificationClient`. Endpoint ids are strings, so `MicrophonePriority`
  works unchanged.
- Windows has a privacy switch, "Let desktop apps access your microphone". When
  it is off, opening the device fails with access denied. Detect that and open
  `ms-settings:privacy-microphone` with a plain message. Windows 11 is adding
  per-app switches for desktop apps
  ([TweakTown](https://www.tweaktown.com/news/113172/windows-11-is-finally-adding-per-app-controls-for-desktop-programs-accessing-your-microphone-camera-and-location/index.html)).
- Keep the Mac design rules even though WASAPI is less fragile than CoreAudio:
  audio never on the UI thread, a deadline on start, and a stuck session is
  thrown away and replaced.

### Tray and overlay

- **Tray:** Tauri's tray icon and menu. The language glyph becomes one small
  icon per language, drawn at build time.
- **Overlay:** a second Tauri window that is transparent, always on top, has no
  taskbar button, and **never takes focus** (`WS_EX_NOACTIVATE`,
  `WS_EX_TOOLWINDOW`, and click-through with `WS_EX_TRANSPARENT`). If the
  overlay ever takes focus, the paste lands in the overlay instead of the user's
  app. That is the single most important property to test.
- Panel only. The notch bar has no Windows equivalent. Handy reports crashes from
  its overlay and screen-capture hooks (issue #2049), so keep ours simple.

### Auto-start

- Normal install: the HKCU `Run` key, through `tauri-plugin-autostart`.
- Microsoft Store (MSIX) install: `Run` keys do not work. Declare a
  `windows.startupTask` instead. The user can turn it off, and the app must run
  once before it shows up
  ([Advanced Installer](https://www.advancedinstaller.com/startup-programs-msix.html)).

### Updates

| Option | What it is | Fit |
|---|---|---|
| Tauri updater | Built into Tauri. Signs with minisign. Works with NSIS or MSI installers and a JSON feed on GitHub. Handy uses it. | **Use this for direct downloads.** Same shape as today: GitHub Releases plus a feed on GitHub Pages. |
| Velopack | Delta updates, its own `Setup.exe`, GitHub hosting, signs with Azure Artifact Signing ([docs](https://docs.velopack.io/packaging/signing)). | Best choice if the stack is C#. |
| WinSparkle | Reads Sparkle-style appcasts with EdDSA signatures. v0.9.3, slow releases ([GitHub](https://github.com/vslavik/winsparkle/releases)). | It could reuse the appcast tooling, but the Tauri updater is already in the box. |
| Microsoft Store (MSIX) | The Store installs and updates. | **Use this as the main channel.** See signing. |

Use a separate signing key from the Mac's Sparkle key. Back it up the same way.
Losing it means no Windows install can update.

### Code signing and SmartScreen

SmartScreen is the Windows warning "Windows protected your PC" on downloaded
apps. Smart App Control on Windows 11 can block unsigned apps outright.

The facts that decide this:

- **EV certificates no longer skip SmartScreen.** Every signed app now builds
  reputation over time, which "can take several weeks and hundreds of clean
  installs" ([Microsoft](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)).
- **Store apps never get SmartScreen download warnings** (same page).
- **The Store is free for individual developers** since September 2025
  ([Microsoft](https://blogs.windows.com/windowsdeveloper/2025/09/10/free-developer-registration-for-individual-developers-on-microsoft-store/)).
  The Store signs MSIX packages itself.
- **Azure Artifact Signing** (formerly Trusted Signing) costs $9.99 a month. Only
  individuals in the US and Canada can use it. Organizations in Israel can
  ([quickstart](https://learn.microsoft.com/azure/artifact-signing/quickstart),
  [pricing](https://azure.microsoft.com/en-us/pricing/details/artifact-signing/)).
  So the owner could use it only through a registered business.
- A Certum cloud code-signing certificate starts at about 49 euros
  ([Certum](https://shop.certum.eu/code-signing.html)). Still slow reputation.

**Plan:**

- **Main channel: Microsoft Store, as MSIX.** Free, signed by Microsoft, no
  SmartScreen warning, updates handled.
- **Second channel for testers: a direct NSIS installer** from GitHub Releases
  with the Tauri updater. Unsigned during the friends beta, with an `INSTALL.md`
  that explains the warning, the same way the Mac does today. Buy a certificate
  only if strangers need the direct download.

Two things to check before relying on the Store (both are open risks):

- Tauri does not produce MSIX directly. It makes MSI and NSIS. We need an extra
  packaging step with Microsoft's tools.
- An app with a global keyboard hook and `SendInput` must pass Store review.
  Full-trust desktop apps can use both, and keyboard tools are in the Store, but
  confirm against the current Store policy before milestone 7.

### Antivirus

An unsigned app that hooks the keyboard and sends keystrokes looks like a
keylogger to antivirus tools. Expect false alarms on direct downloads. Store
distribution and signing both help. Test with Windows Defender in the spike.

---

## Part 4: which hardware is fast enough

### What "fast enough" means

The goal: **when you stop talking, the text lands within about 1 to 2 seconds,
even after a 30 to 60 second dictation.**

Nivi has two ways to get there, from the streaming doc:

- **`batch`:** transcribe everything after you stop. The wait is `r * N` for an
  N second recording. For 60 seconds to finish in 2 seconds, `r` must be about
  0.03 or lower.
- **`batchFastFinish`:** transcribe while you speak, so only the leftover is
  done at the end. The wait is `r * leftover`. Today the leftover is up to one
  streaming window, 10 seconds by default, so `r` of 0.15 gives about 1.5
  seconds. The forward-only design in the fast-finish plan shrinks the leftover
  further and lets a slower machine still finish fast.

The streaming modes also keep the GPU busy for the whole recording, so on a
laptop they cost battery and heat. A machine that only reaches the target with
streaming is "good", not "great".

**Verdict scale used below:**

| Verdict | `r` | What it means |
|---|---|---|
| Great | 0.03 or less | Even plain `batch` is fine for a 60 second dictation. |
| Good | 0.03 to 0.15 | Fine with `batchFastFinish`. Wait about 1 to 1.5 s at any length. |
| Borderline | 0.15 to 0.3 | Only with the forward-only fast finish. 2 to 3 s waits. Measure before promising anything. |
| Not worth it | over 0.3 | Slower than the Mac by a lot. Use a smaller model or a different engine. |

For reference, the streaming doc assumed `r = 0.1` for the Mac with Metal. That
is itself an assumption, not a measurement. The Mac logs the real figure, so
read it before comparing.

### The Hebrew constraint

The Hebrew model, ivrit-ai Large v3 Turbo, has the same encoder as Whisper Large
v3. Only its decoder is smaller. The encoder is the expensive part, and it runs
once per 30 second window. So Hebrew always costs a large-model encoder pass, and
there is no small Hebrew model in the catalog. Parakeet has no Hebrew at all.

**This is the single fact that shapes the hardware answer.** English can fall
back to small, fast models. Hebrew cannot.

### Measured numbers by others

The useful ones, all **[measured]**:

| Hardware | Backend | Model | Number | Source |
|---|---|---|---|---|
| AMD RX 9070 XT, Windows 11 | Vulkan, flash attention, whisper.cpp 1.8.3 | large-v3 | Encoder: 88.5 ms per 30 s window | [whisper.cpp #89](https://github.com/ggml-org/whisper.cpp/issues/89) |
| NVIDIA RTX 3070 Ti | CUDA, whisper.cpp 1.7.2, beam 5 | large-v2 | 13 min of audio in 65 s, so `r` about 0.083 | [faster-whisper README](https://github.com/SYSTRAN/faster-whisper) |
| RTX 4090 Laptop, Windows 11 | CUDA and Vulkan | small / large-v3 | 11 s clip: CUDA 0.84 / 3.90 s, Vulkan 0.82 / 3.73 s. CUDA and Vulkan are about equal. | [starwhisper.ai](https://starwhisper.ai/whisper-benchmark.html) |
| Radeon 890M (built-in GPU) | Vulkan | base.en | Encoder 86 ms. The same chip on its CPU: 395 to 437 ms. | [whisper.cpp #89](https://github.com/ggml-org/whisper.cpp/issues/89) |
| Radeon 680M and Intel Core Ultra 7 155H built-in GPUs | Vulkan, 1.8.3 | not stated | CPU `r` about 0.3. Built-in GPU 3 to 4 times better. | [PR #3492](https://github.com/ggml-org/whisper.cpp/pull/3492) |
| Intel Arc, first generation | Vulkan, beam 5 | large-v3-turbo q8_0 | `r` = 0.27 on a 24 minute file | [Varashi/k8s #356](https://github.com/Varashi/k8s/issues/356) |
| Ryzen 9 5950X, CPU only, 8 threads | CPU (2023 code) | small / large | Encoder 1.39 s / 8.1 s per 30 s window | [whisper.cpp #89](https://github.com/ggml-org/whisper.cpp/issues/89) |
| i7-12700K, CPU only | whisper.cpp 1.7.2 / with OpenVINO encoder | small, beam 5 | 13 min in 2m05s / 1m45s, so `r` about 0.16 / 0.13 | [faster-whisper README](https://github.com/SYSTRAN/faster-whisper) |
| Snapdragon X Elite X1E78100, CPU | whisper.cpp 1.6.2 | small.en | Same time as a Core Ultra 7 155H on the same test | [OpenBenchmarking](https://openbenchmarking.org/test/pts/whisper-cpp) |
| Snapdragon X Elite, NPU (Qualcomm AI Hub, not whisper.cpp) | QNN | large-v3-turbo | Encoder 561 ms, decoder 8.5 ms per token | [Hugging Face](https://huggingface.co/qualcomm/Whisper-Large-V3-Turbo) |
| i7-12700K, CPU | ONNX Runtime int8 | Parakeet TDT 0.6B v3 | About 30x real time, so `r` about 0.033 | [groxaxo](https://github.com/groxaxo/parakeet-tdt-0.6b-v3-fastapi-openai) |
| Ryzen 7 9800X3D, CPU | onnx-asr | Parakeet v2/v3 | 36x real time, so `r` about 0.028 | [onnx-asr](https://github.com/istupakov/onnx-asr) |
| Ryzen 7 5700X / i5-6500, CPU | transcribe-rs int8 | Parakeet | About 20x / 5x real time | [transcribe-rs](https://github.com/cjpais/transcribe-rs) |

Caveats about this data:

- Some of these runs use beam search (beam 5), which Nivi's default greedy
  decoding does not. Greedy is faster, so these numbers are pessimistic for us.
- The starwhisper numbers look slow for a 4090 and may include model loading.
  Use them for the CUDA versus Vulkan comparison, not as absolute speed.
- **Missing:** clean numbers for desktop RTX 3060 / 4060, the Radeon 780M, Intel
  Lunar Lake and Meteor Lake GPUs, the Snapdragon's Adreno GPU, and
  large-v3-turbo on x86 CPUs. The spike fills the most important of these gaps.

### Tier table

`r` here is for **Large v3 Turbo** unless the model column says otherwise. All
`r` values in this table are **[estimate]**, derived from the measured rows
above.

| Hardware class | Backend | Model for Hebrew | Model for English | Expected `r` (Hebrew model) | Verdict |
|---|---|---|---|---|---|
| NVIDIA RTX 30, 40, 50 series, desktop or laptop, 6 GB or more | Vulkan (CUDA optional) | ivrit-ai Turbo, full size | Turbo | 0.01 to 0.03 | **Great** |
| AMD RX 6000 / 7000 / 9000, Intel Arc B series | Vulkan | ivrit-ai Turbo, full size or q8_0 | Turbo | 0.01 to 0.05 | **Great** to good |
| Intel Arc A series (first generation) | Vulkan | ivrit-ai Turbo q8_0 | Turbo q8_0 | about 0.15 with greedy decoding (0.27 measured with beam 5) | **Good** to borderline |
| Recent built-in GPU: Radeon 780M / 880M / 890M, Intel Core Ultra (Meteor Lake, Lunar Lake) | Vulkan, whisper.cpp 1.8.3 or later | ivrit-ai Turbo q5_0 or q8_0 | Small, or Parakeet on CPU | 0.1 to 0.3 | **Borderline.** Fast finish only. This is the class the spike must measure. |
| Older built-in GPU: Intel Iris Xe, Radeon Vega | CPU | not recommended | Base or Small, or Parakeet | 0.5 or more | **Not worth it for Hebrew.** English fine with Parakeet. |
| CPU only, modern desktop, 8 cores or more | CPU (AVX2 / AVX-512) | not recommended | Parakeet (`r` 0.03 to 0.05 [measured]), or Small | 0.3 to 0.6 | **Not worth it for Hebrew.** **Great** for English with Parakeet. |
| CPU only, laptop, 4 to 8 cores | CPU | not recommended | Parakeet (`r` about 0.05 to 0.2) or Base | 0.6 or more | English only. |
| Snapdragon X (Windows on ARM) | CPU now. NPU later, through a different runtime. | not at launch | Parakeet on the ARM CPU | CPU like a Core Ultra 155H. NPU about 1 s per utterance. | **English only at launch.** Hebrew on the NPU is a research project. |

### Parakeet changes the picture for English on a CPU

Parakeet is 3 to 5 times faster than Whisper Small on the same CPU, and more
than 10 times faster than Turbo [estimate from the measured rows]. Even a 2016
i5-6500 runs it at about 5x real time [measured, transcribe-rs]. So an
English-only user with no GPU gets a fast app.

It does not help Hebrew, which is the owner's main use. So Parakeet is
milestone 8, an optional engine for English users, not part of the core build.
If ivrit-ai or NVIDIA ever publish a fast Hebrew model of this kind, the same
engine slot is ready.

### Minimum spec

**For Hebrew:**

- Windows 10 22H2 or Windows 11, x64.
- 8 GB RAM.
- A GPU with a working Vulkan driver and at least 2 GB of video memory, dedicated
  or shared. Turbo at full size needs about 1.6 GB for its weights. q8_0 needs
  about 0.85 GB.
- A first-run speed check that measures `r` of 0.3 or lower.

**For English:** any x64 CPU with AVX2 and 8 GB RAM.

**Not supported at launch:** Windows on ARM, Windows 10 before 22H2, CPUs
without AVX2.

### How the app picks the backend and model on first run

Nivi already logs inference time. On Windows we turn that into a short check at
first run, and keep watching it after.

1. **Find the devices.** whisper.cpp's backend list tells us which GPUs are
   usable through Vulkan (and CUDA, if we ship it). No GPU means CPU.
2. **Quick check with a small download.** Download Whisper Base (about 150 MB),
   which is needed anyway as the fallback. Transcribe a bundled 11 second test
   clip (whisper.cpp ships `jfk.wav`) on each device, after one warm-up pass.
   This takes seconds. It gives us `r` for Base on each device.
3. **Predict Turbo.** Multiply by a ratio between Turbo and Base, measured once
   on the test machines in the spike. Pick the fastest device.
4. **Recommend, do not force.** If the language is Hebrew and the predicted `r`
   is 0.3 or lower, recommend ivrit-ai Turbo (q8_0 if `r` is above 0.1), and
   set the profile to `batchFastFinish` if `r` is above 0.03. If it is too slow,
   say so plainly and still let the user try.
5. **Confirm with the real model.** After the big download, run the clip once
   more with the real model and store the measured `r`.
6. **Keep measuring.** Log `r` for every dictation, as the Mac does. If the
   average over the last 10 dictations is far worse than the first-run number,
   say so in Preferences and suggest a smaller model. This catches a broken GPU
   driver that silently falls back to the CPU, the Windows version of the Metal
   problem in `vendor/patches/README.md`.

Ship Vulkan as the default GPU backend. CUDA and Vulkan measured about the same
on an RTX 4090 Laptop, and CUDA's libraries add hundreds of megabytes. Handy also
ships Vulkan only. Offer CUDA later only if the spike shows a real gap on NVIDIA.

---

## Part 5: the shared contract, frozen first

Everything that both apps read or write gets written down and frozen in
milestone 1, before any Windows feature code. After that, milestones only add
implementation.

| Contract | Mac today | Windows | What to write down |
|---|---|---|---|
| Settings | `UserDefaults`, domain `com.dvir.nivi` | `%APPDATA%\Nivi\settings.json` | Every key name and default from `Settings.swift`, unchanged. The same value encodings: `profilesJSON` stays the same JSON, word replacements stay the same JSON. A `schemaVersion` field. |
| Hotkey | `HotkeyBinding` with Mac key codes | Same enum shape | Add a `platform` field and a Windows key list. Mac keeps decoding its old values. The two never read each other's hotkeys. |
| Profiles | `ProfileSet` JSON | Same | No change. |
| Model catalog | `models/catalog.json`, `ModelCatalog` | `%LOCALAPPDATA%\Nivi\models\catalog.json` | Add optional fields: `quantization`, `sha256`, `minBackend`. Optional, so the Mac's decoder ignores them. |
| History | `history.jsonl`, one `HistoryRecord` per line | `%LOCALAPPDATA%\Nivi\history.jsonl` | No change. Same field names, epoch seconds, skip broken lines. |
| Logs | `~/Library/Logs/Nivi/nivi.log` | `%LOCALAPPDATA%\Nivi\logs\nivi.log` | The same key lines, including `Inference completed in ...s` with the audio length, so `r` can be read the same way. |

Big files and history go in `%LOCALAPPDATA%`, which does not roam between PCs.
The 1.6 GB model must never roam, and history is private.

**Shared test cases.** Extract the important cases from
`Tools/core-tests/main.swift` into JSON files: input and expected output for
`StreamWindow`, `TranscriptCleaning`, `WordReplacing`, `appendOnlyTail`,
`audioContext`, `AudioChunkPlanner`, `ModifierTapDetector`, history parsing and
catalog merging. The Rust tests read them. Later, the Swift tests can read them
too, so both apps are checked against the same cases. This is how two codebases
stay in agreement.

Changing the Mac test harness to read those files is optional and can wait. It
should not block Windows work.

---

## Part 6: milestones

About 10 hours a week is assumed. Effort is **[estimate]**, in weeks at that
pace.

### M1. Write down and freeze the shared formats (2 weeks)

- **Scope:** Part 5 as a document in `docs/windows/`. The JSON test-case files.
  A Rust `nivi-core` crate with only the types: settings, profiles, hotkey,
  catalog, history. Decide the Windows hotkey key list.
- **Done when:** the types read the Mac's real `history.jsonl` and
  `catalog.json`, and write them back byte for byte where the Mac would. The
  format document is reviewed and marked frozen.

### M2. Spike on three machines, then decide go or no-go (3 weeks)

- **Scope:** a bare Tauri tray app, no settings UI. Double-tap right Ctrl starts
  recording, one tap stops. whisper.cpp 1.8.x on Vulkan transcribes with ivrit-ai
  Turbo. Paste with the clipboard. A command-line `bench` that prints `r` for
  Base, Small, Turbo q5_0, q8_0 and full size, on every device. A port of
  `Tools/whisper-stress/run.sh`.
- **Test it on three machines:** one NVIDIA desktop, one AMD 780M-class laptop,
  one Intel Core Ultra laptop. See the matrix below.
- **Done when:** the go / no-go checklist below is filled in with real numbers.

### M3. Port the core logic with its tests (3 weeks)

- **Scope:** translate the 20 reuse-as-is files and the 7 port-logic files of
  `NiviCore` into `nivi-core`. All shared test cases pass.
- **Done when:** `cargo test` passes every shared case. Each core check that
  could not become a shared case has a Rust test of its own.

### M4. The dictation path, end to end, in batch mode (4 weeks)

- **Scope:** audio through WASAPI with device priority and the "retire a stuck
  session" rule. `RecognizerCache` with idle unload. The final pass,
  `TranscriptFinishing`, history write, paste and typed input, elevated-window
  detection. Tray with profiles. The overlay panel that never takes focus. Esc to
  cancel. Mute while recording. The watchdog and the hook re-install after sleep.
- **Done when:** a full day of real use on the owner's Windows machine with no
  crash and no lost dictation. The paste works in every app in the spike list.

### M5. Streaming modes (3 weeks)

- **Scope:** `StreamingTranscriber` and the three streaming modes, built from the
  design in [../streaming/2026-10-26-fast-finish-plan.md](../streaming/2026-10-26-fast-finish-plan.md)
  as it stands when this milestone starts. `batchFastFinish` first, because it is
  what makes built-in GPUs usable. Then `overlayLive`, then `inAppLive`.
- **Done when:** a 60 second dictation finishes within 2 seconds on the "good"
  tier machine. The stress test passes with streaming on.

### M6. Settings UI and first-run setup (4 weeks)

- **Scope:** the React pages, matching the Mac's tabs: General, Dictation Models
  (download, delete, test), Profiles, Hotkeys (record a hotkey), Speech, History
  (search, filter, delete), Word replacements. The first-run flow from Part 4:
  microphone check, speed check, model recommendation, download.
- **Done when:** someone who has never seen Nivi can install it and dictate in
  Hebrew without help. Watch one friend do it.

### M7. Packaging, updates and the Store (3 weeks)

- **Scope:** NSIS installer and the Tauri updater with a feed on GitHub Pages.
  MSIX package and Store submission. Auto-start for both. A release script in the
  style of `Tools/publish-release.sh`. Back up the updater signing key.
- **Done when:** an installed old version updates itself to a new one, seen
  working. That is the step the Mac still has not proven, so do not repeat that
  gap. The Store listing is approved.

### M8. Friends beta, then optional extras (3 weeks, then open-ended)

- **Scope:** beta with 3 to 5 friends on different hardware. Fix what they find.
  Then, only if wanted: Transcribe a file (Media Foundation decode, `.txt` and
  `.docx` export), the Parakeet engine for English on CPU, CUDA, Windows on ARM.
- **Done when:** a week of beta with no crash reports and no lost dictations.

**Total: about 25 weeks of work, so 6 to 8 months with gaps [estimate].** M1 and
M2 together are 5 weeks, and are the only commitment before the go / no-go
decision.

### Test hardware matrix

| # | Machine | Why | Needed by |
|---|---|---|---|
| A | Desktop, NVIDIA RTX 3060 or 4060, Windows 11 x64 | The "great" tier, and the most common gaming GPU | M2 |
| B | Laptop, AMD Ryzen 7840U / 8840HS (Radeon 780M) | The built-in GPU borderline case | M2 |
| C | Laptop, Intel Core Ultra (155H or 258V) | The other borderline case, and the most common new business laptop | M2 |
| D | Older laptop, Intel 11th gen with Iris Xe | The floor. Checks the "too slow" message and English on CPU | M6 |
| E | Any Windows 10 22H2 machine | Windows 10 differences in tray, privacy and Store | M7 |
| F | Snapdragon X laptop | Only if Windows on ARM is in scope | M8 |

A Windows VM on the Mac is fine for UI work, but it cannot test GPU speed,
hotkeys under real load, or paste into real apps. The spike needs real machines.
Friends' machines with a shared test build are enough for B, C and D.

Agents must not drive the owner's own Windows machine with synthetic input, for
the same reasons as on the Mac. Automated paste tests run only on a dedicated
test machine or VM that nobody is using.

### Go / no-go after the spike (end of M2)

Fill in for each of machines A, B and C:

| Check | Pass when |
|---|---|
| Hotkey | Double-tap right Ctrl is caught 50 out of 50 times. Still works after sleep and after one hour of normal use. Esc cancels. |
| Paste | Correct Hebrew and English text lands in Notepad, Word, Chrome, VS Code, Slack or Teams, and Windows Terminal. The old clipboard comes back. The text is not in Win+V history. An elevated window gets a clear "on the clipboard" message. |
| Speed | `r` for ivrit-ai Turbo, each size, on the best device. |
| Stability | The ported stress test runs 40 dictations of alternating pass shapes with no crash, on Vulkan. |
| Antivirus | Windows Defender does not quarantine the test build. |

**Go** if hotkey, paste, stability and antivirus pass on all three, and machine
A reaches "great" for Hebrew.

**Go, with a smaller promise** if B or C reach only "borderline". Then Windows
Hebrew is sold as "needs a graphics card", and built-in GPUs get English plus a
"try it" Hebrew mode.

**No-go, or rethink** if hotkey or paste fail in ways Handy's code does not
explain, or if even machine A cannot reach "good" for Hebrew. At that point the
cheaper answer is to point Windows friends at Handy.

---

## Part 7: risks and open questions

### Risks

| Risk | Why it matters | What reduces it |
|---|---|---|
| Hebrew needs a GPU | Many friends may have business laptops with built-in GPUs, the borderline class. | Measure in M2 before committing. Fast finish helps. |
| Two codebases drift apart | A fix on the Mac never reaches Windows, or the reverse. | Shared formats and shared test cases from M1. Port fixes as a habit, with a checklist in the release notes. |
| Two whisper.cpp versions | Mac on 1.7.2 with a patch, Windows on 1.8.x. A bug fixed on one may live on in the other. | Move the Mac pin later. Run the stress test on both. |
| The keyboard hook is removed silently | Hotkeys stop with no error, the worst kind of failure for this app. | Hook on its own thread, callback does nothing slow, re-install after sleep and on a timer. Try Raw Input in the spike. |
| Paste fails in some apps | Admin windows, games, RDP, some terminals. | Detect elevated windows and fall back to the clipboard with a message. Test the list in M2. |
| Clipboard restore races | Restoring too early pastes the old clipboard. Handy saw this. | Generous delay, tested under load. |
| Antivirus flags the app as a keylogger | Install fails or the app is quarantined. | Store distribution, signing, test with Defender in M2. |
| The Store rejects a keyboard-hooking app, or MSIX packaging of Tauri is painful | The free, warning-free channel is gone. | Check the policy before M7. Fallback: a certificate (about 49 euros and up) and the direct installer. |
| Built-in GPU Vulkan drivers misbehave | Crashes or wrong output on some laptops. Handy turns off some Vulkan layers by default for this reason. | Test B and C. Keep a CPU fallback with a clear message. Watch `r` in use. |
| Owner time | A 6 to 8 month side project competes with the Mac work, where notarisation and the update path are still open. | M1 and M2 are only 5 weeks. Decide after them. |
| Rust is new to the owner | Slower start. | The Rust part is smaller than the UI part, and Handy is a working example to read. |

### Open questions for the owner

1. **Who is the Windows version for?** Friends who dictate Hebrew, English
   speakers, or strangers? This decides whether a GPU requirement is acceptable.
2. **What hardware do those friends have?** If most have business laptops with
   built-in graphics, Hebrew on Windows is borderline for them.
3. **Would Handy be enough for some of them?** It is free and works today for
   English.
4. **Rust and Tauri, or C# and .NET?** The plan recommends Rust because the UI is
   React. If you would rather learn C#, the plan still holds.
5. **Is the Microsoft Store acceptable as the main channel?** It is free and
   avoids the warning, but every release goes through review.
6. **Is there budget for a signing certificate**, or a business that could use
   Azure Artifact Signing at $9.99 a month?
7. **May we host a quantized copy of the ivrit-ai model?** Check its license and
   ask ivrit-ai if needed. Without it, built-in GPUs get only the full-size
   model.
8. **Is there a Windows PC to develop on?** A VM covers the UI, not the spike.
9. **Which features are in version 1?** The plan assumes dictation, profiles,
   streaming, history and word replacements. Transcribe a file, export and
   Parakeet are in M8 as extras.
10. **Should this wait until the Mac is notarised and self-update is proven?**
    The decision log says reliability and the install experience come first.
    Windows is new scope, and it competes for the same hours.
