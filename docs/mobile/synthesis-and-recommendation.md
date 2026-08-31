# iPhone + Apple Watch dictation — synthesis and recommendation

Date: 2026-07-26
Status: research complete, awaiting two device probes before any design work

Companion fact-sheets: `ios-keyboard-constraints.md`, `model-landscape.md`.
This file is the synthesis, including corrections to earlier assumptions.

## The goal

Offline whisper-quality Hebrew dictation, matching what the macOS app achieves
with `ivrit-ai/whisper-large-v3-turbo-ggml`:
1. iPhone — seamless dictation in **every** app.
2. Apple Watch — dictate on the wrist, note saved on the iPhone.

The friction to eliminate (from existing App Store solutions): switch keyboard →
bounced to the app to approve permissions → navigate back → talk.

## Verdict up front

**"Seamless in every app with our own whisper model" is not achievable on
current iOS.** Not a memory problem — a capability problem. Two independent
constraints, both verified:

- **App extensions cannot open the microphone.** Blocked at the entitlement
  level regardless of Full Access. Runtime error, verbatim from Apple's forums:
  `CMSUtility_IsAllowedToStartRecording: Client … was NOT allowed to start
  recording because it is an extension and doesn't have entitlements to record
  audio`. Apple's App Extension Programming Guide states custom keyboards "have
  no access to the device microphone, so dictation input is not possible." A
  developer filed FB16791704 after `AVAudioEngine` failed even with Full Access
  **and** mic permission granted; unresolved as of Sept 2025.
- **The documented workaround is the friction itself.** The standard pattern is
  keyboard → `extensionContext.open()` → container app records and transcribes →
  result to a shared App Group → keyboard polls and calls
  `textDocumentProxy.insertText`. That visible app switch is exactly what we set
  out to remove, and it has a known failure mode: the container app gets
  suspended mid-recording when the user leaves it.

## Corrections to earlier assumptions

| Earlier claim | Reality |
|---|---|
| Keyboard extension memory (~60–80MB) is the deciding constraint | Wrong emphasis. The real blocker is mic access. The limit is also unofficial — empirical reports cluster ~30–48MB, no Apple-published number. |
| Architecture A (keyboard records → IPC → host app holds the big model) is viable and recommended | **Dead.** The keyboard cannot record. IPC works, but only with a visible app switch. |
| Architecture B (self-contained keyboard with a small model) trades quality for robustness | **Dead twice over:** no mic in-extension, and no small Hebrew-tuned model exists (below). |
| A model would have to fit in the extension's memory budget | Not for Apple's API — `SpeechAnalyzer`'s model runs **out of process**. WWDC25 session 277, verbatim: "It operates outside of your application's memory space, so you don't have to worry about exceeding the size limit." Served by the `speechrecognitiond` XPC daemon. Irrelevant while the mic is blocked, but it kills the memory objection to Apple's API. |
| Apple's iOS 26 speech API is ~4× better and may just solve this | Half-true and possibly misleading — see the benchmark conflict below. |

## Models: no smaller Hebrew option exists

Every ASR repo in the `ivrit-ai` HuggingFace org is large-class (large-v3,
large-v3-turbo, large-v2, plus ct2/ggml/onnx format variants). There is **no**
`small`/`base`/`tiny`/`distil` Hebrew fine-tune published. So shrinking the
footprint means either abandoning ivrit.ai's Hebrew tuning for stock small/base
whisper (Hebrew quality untested, and stock whisper's Hebrew is known to be
mediocre — ivrit.ai exists precisely because of that), or training a mid-size
fine-tune ourselves using ivrit.ai's public recipe.

## Apple's on-device speech: promising, but the accuracy story conflicts

Verified:
- `SpeechAnalyzer` / `SpeechTranscriber` are iOS 26+, **on-device only**, no
  server path. Models download via `AssetInventory` and are shared across apps.
- Hardware floor appears to be A14 / iPhone 12 and later (correlates with the
  16-core Neural Engine), **not** the stricter Apple Intelligence bar. Apple
  refuses to publish a device list; use `isAvailable` at runtime.
- **Hebrew on-device dictation exists on iOS today.** Apple's own feature
  availability page lists "Hebrew (Israel)" under *Dictation: On-Device and
  Modeless Dictation*. (Notably Hebrew has no Siri support at all — a reasonable
  proxy for how much investment Hebrew gets.)
- `he_IL` appears in a 42-locale `SpeechTranscriber.supportedLocales` dump from
  two independent sources, one claiming live-device verification (2026-06-04) —
  but this is **not** Apple-published.

The benchmark conflict, and why it matters more than the "4× better" headline:

| Source | Finding |
|---|---|
| 9to5Mac, 2025-07-03 | Whisper large-v3-turbo **0.4–1.4% WER**; Apple **8.2–10.3%**. Apple faster, clearly less accurate. |
| get-inscribe, 2026-07 | LibriSpeech: Apple 2.12%/4.56% vs Whisper Small 3.74/7.95, and legacy `SFSpeechRecognizer` 9.02/16.25. **Whisper large-v3 was never tested.** |
| MacStories, 2025-06-18 | ~2.2× faster than MacWhisper large-v3-turbo, "no noticeable quality difference." |
| Argmax, 2025-06-20 | Apple 14.0% WER on earnings calls; no diarization, and **custom vocabulary was dropped** vs `SFSpeechRecognizer`. |

The "~4× improvement" is Apple's new API vs the *legacy* `SFSpeechRecognizer`
(9.02% → 2.12% on the same harness) — a real and large gain, but it is **not**
evidence of parity with whisper large. Where large-v3 was actually tested, it
won decisively. **And every published benchmark is English-only — nobody has
measured Hebrew for any of these.** Since Hebrew quality is the entire point,
that number has to be produced locally.

## Apple Watch: the platform answers this for us

- **watchOS has no Speech framework at all** — not `SFSpeechRecognizer`, not
  `SpeechAnalyzer` (still absent in the 27.0 betas). A watch app cannot run its
  own transcription, ours or Apple's.
- It can record in the **foreground** (`AVAudioRecorder`, watchOS 4+) and hand
  off via `WCSession.transferFile`. Background recording is not a supported path;
  extended runtime sessions permit playback, not recording.
- watch→phone **can** wake the phone app in the background; phone→watch cannot
  wake the watch app. Transfers are opportunistic and throttled — fine for
  store-and-forward, not for anything interactive.
- App Groups do **not** span watch and phone (device-level), so WatchConnectivity
  is the only channel.
- **watchOS 26 ships the Notes app**, and it creates notes by dictation, syncing
  to iPhone via iCloud. That is the stated watch requirement, already solved,
  with zero code — at Apple's Hebrew dictation quality.

## Recommendation

**Step 1 — two device probes before any design work.** Cheap, and between them
they decide everything:

1. On an iOS 26 device, print `SpeechTranscriber.supportedLocales` and check
   `SFSpeechRecognizer(locale: "he-IL")?.supportsOnDeviceRecognition`. Settles
   whether Hebrew is genuinely available on the new API.
2. **Benchmark Hebrew by ear on your own speech:** built-in iOS dictation vs the
   Mac app's ivrit.ai output on the same few sentences. This is the whole
   decision. If Apple's Hebrew is now good enough, the seamless-everywhere
   problem is already solved for free and no project is needed. Given the
   English data where whisper large won decisively, expect Apple to lose — but
   your subjective bar is what matters, and your "Apple Hebrew is bad"
   impression may predate iOS 26.

**Step 2 — if Apple's Hebrew is not good enough:** build the Action Button /
Shortcut path (previously "architecture C"). Action Button → app records →
transcribes with full ivrit turbo in the foreground app, where RAM is plentiful
and the out-of-process/extension limits don't apply → text to the clipboard,
ready to paste. Full quality, one paste, no fighting the platform. Not
"types into the field", but genuinely low-friction and it cannot be blocked.

**Watch:** use the built-in watchOS 26 Notes app. Only build a watch recorder +
`transferFile` + phone-side transcription if Apple's Hebrew dictation fails your
ear test *and* wrist capture matters enough to justify a second app.

**Account:** the paid Apple Developer Program ($99/yr) is the practical
requirement. Free "Personal Team" means 7-day provisioning expiry, 3 apps, and
10 App IDs per week (each extension consumes its own). Nothing in 2026 removes
the 7-day re-sign — every sideloading tool merely automates it. TrollStore is
dead for modern iOS; LiveContainer explicitly does not support app extensions;
EU/Japan/Brazil alternative distribution requires being physically in an eligible
region, so it is unavailable in Israel and requires paid membership anyway.

## Open questions

1. Hebrew WER for Apple's `SpeechTranscriber` vs whisper large-v3 — unmeasured
   anywhere. Probe 2 above.
2. `he_IL` in `SpeechTranscriber.supportedLocales` is secondary-sourced only.
3. Whether App Groups genuinely work on a free Personal Team — Apple's
   capability matrix says yes, folklore says no. Only matters if a
   keyboard+container design is revived, which the mic block makes unlikely.
4. Apple's dictation customization hooks (vocabulary biasing) — unexplored, and
   worth a look only if probe 2 comes back "close but not quite". Note Argmax
   reports custom vocabulary was *dropped* in the new API.
