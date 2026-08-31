# iPhone and Apple Watch dictation: where we stand

Date: 2026-08-24. Status: research complete. No code was written.

Earlier work in this repo: `docs/mobile/ios-keyboard-constraints.md`,
`docs/mobile/model-landscape.md`, `docs/mobile/synthesis-and-recommendation.md`
(all 2026-07-26). This file re-checks those findings, corrects two of them, and
adds the parts they did not cover: every possible trigger on iOS, the real tap
cost of each one, and measured whisper speed on a modern iPhone.

---

## The honest bottom line

**You cannot get Apple-level seamless dictation on iPhone with your own whisper
model. Not today, not with any public API.** The reason is one hard rule, and it
is not about memory or model size:

> An app extension cannot open the microphone. Ever. Any extension, any
> permission, any setting.

A custom keyboard is an app extension. So the keyboard can never hear you. Only
a normal app can record. That means something has to wake the app up, and that
is where the friction you already hate comes from. Every third-party dictation
keyboard on the App Store has the same problem. They are not lazy. They are
boxed in.

There is one possible escape hatch, and it is real but unproven: keep your app
running in the background with a live microphone session, so the keyboard only
has to send it a message instead of launching it. I explain it below as
**Option S**. It would give you a true zero-switch experience. It also means an
orange microphone dot on your screen all day and real battery cost. Nobody has
published a working example. It needs a test, not a plan.

Everything else on iOS costs you at least one visible app switch per dictation.

The good news, and it is genuinely good:

- The speed problem is solved. `whisper-large-v3-turbo` runs on an iPhone 15 Pro
  at about 7 times faster than real time. Your model size is not a problem in a
  normal app.
- Hebrew is fine on the whisper side. Your existing `ivrit-ai` weights can be
  converted and shipped to iPhone.
- Apple Watch is a settled question. It cannot transcribe, at all, with anything.
  Record on the watch, send the file to the phone, transcribe there.

---

## What the July research got right, and the two things it got wrong

Right, and confirmed again today:

- Keyboard extensions cannot record audio. Apple's own App Extension Programming
  Guide says it in plain words: custom keyboards, like all app extensions,
  "have no access to the device microphone, so dictation input is not possible."
  Confirmed at runtime too, with the system error
  `CMSUtility_IsAllowedToStartRecording: ... was NOT allowed to start recording
  because it is an extension and doesn't have entitlements to record audio`.
- No small Hebrew whisper model exists. Everything in the `ivrit-ai` org is
  large-class.
- The paid Apple Developer Program at 99 USD a year is the practical choice. The
  free tier makes you re-sign every 7 days.

Wrong, or too pessimistic:

1. **"A 1.6 GB model is too heavy for iOS."** This was written about the keyboard
   extension, which is true there, but it leaked into the general conclusion. In
   a normal foreground app it is simply false. WhisperKit runs
   `large-v3-turbo` on an iPhone 15 Pro and transcribes 10 minutes of audio in
   about 82 seconds. That is over 7x real time, with under 200 ms to the first
   word in streaming mode. Source: arXiv 2507.10860 and the argmax benchmark
   discussion. Model size is a solved problem on the phone.

2. **"Build the Action Button / Shortcut path, text goes to the clipboard, you
   paste it."** The clipboard step is unnecessary and it makes the experience
   worse. If you also ship a keyboard extension, the app can write the text into
   a shared App Group container and the keyboard inserts it straight into the
   text field with `textDocumentProxy.insertText`. No paste, no long-press menu,
   no permission prompt. Same amount of work, better result.

One more correction to a thing not covered before: the July doc left open
whether an App Intent from the Action Button could record without opening the
app. **It cannot.** See the next section.

---

## Every way to start a dictation on iOS, and what each one really costs

Two questions decide everything: can this thing capture audio, and how many taps
does it cost you.

The rule underneath the whole table: **only a normal app process can record, and
it must be in the foreground at the moment recording starts.** Extensions cannot
record. Backgrounded apps cannot start a new recording.

| Trigger | Can it capture audio itself? | What actually happens | Cost per dictation |
|---|---|---|---|
| Custom keyboard extension | **No.** Hard block at the OS level. | Mic key opens your app with `extensionContext.open(URL)`. App records and transcribes. Text goes to a shared App Group container. Keyboard reads it and inserts it. | Tap mic, speak, tap the "back to app" chip. About 2 taps plus a visible screen switch. |
| Action Button (iPhone 15 Pro and later) | No, but it launches your app to the foreground, which can. | App opens, starts recording immediately. | 1 press, speak, then you still have to get the text into the field. |
| Control Center control (iOS 18 and later) | **No.** A control runs in a widget extension. | Same as Action Button: it can only open your app. | Swipe down, tap control, speak, get back. |
| Back Tap (Settings, Accessibility) running a Shortcut | No. | Runs a Shortcut, which opens your app. Same as Action Button but with no hardware button needed. | Double tap the back of the phone, speak, get back. |
| Shortcuts / App Intents / Siri | **No.** Confirmed. | An App Intent triggered from the background fails with `Live Activity start failed: The operation couldn't be completed. Target is not foreground`. Apple's forum answer is explicit: "you cannot start an audio recording from scratch using an intent (like via a Shortcut or the Action Button) if the app isn't already active." | Same as above. The intent has to set `openAppWhenRun` and bring the app forward. |
| `AudioRecordingIntent` (App Intents, iOS 18+) | No, not from cold. | This looked promising and it is not the answer. It can only pause and resume a session that was already started while the app was in the foreground. It also requires a Live Activity to be running the whole time. | Not a trigger. Useful only as a stop button on the Lock Screen. |
| Live Activity | No. | Same as above. It is a control surface for a recording already in progress, plus a way to keep the app alive and visible. | Useful as the stop button, not as the start button. |
| Share extension / Action extension | **No.** Also an extension. | Can only receive text or files that already exist. Useless for live speech. | Not applicable. |
| AirPods stem press | No, and not usable for this. | iOS 26 routes an AirPods stem click to `AVCaptureEventInteraction`. That API is for camera shutter apps and needs an active `AVCaptureSession`. It is not a general-purpose remote button for any app. | Not applicable. |
| Background audio mode (`UIBackgroundModes: audio`) | **Yes, but only to keep going.** | You can keep recording after the app goes to the background. You cannot start a new recording from the background. This is the basis of Option S below. | See Option S. |

### Option S: the one path to a true zero-switch experience

This is the only design I found that removes the app switch entirely. It is not
proven. Treat it as an experiment.

How it works:

1. You open Nivi once, in the morning. It starts an `AVAudioSession` and
   never stops it. The app declares `UIBackgroundModes: audio`, so iOS lets it
   keep running with a live microphone after you leave it.
2. You are now typing in WhatsApp. You tap the mic key on the Nivi keyboard.
3. The keyboard does not open the app. It fires a Darwin notification through
   `CFNotificationCenter`. The still-running app receives it, because it is
   running rather than suspended, and starts buffering audio from the session it
   already has open.
4. You speak. You tap the mic key again, or it stops on silence.
5. The app transcribes with whisper, writes the text into the App Group
   container, and posts another Darwin notification back.
6. The keyboard inserts the text with `textDocumentProxy.insertText`.

You never leave WhatsApp. Tap, speak, tap. That matches Apple's own dictation.

What it costs and why it may not work:

- The orange microphone dot is on your screen all day. Control Center will say
  Nivi is using the microphone. That is not a bug you can fix.
- Real battery drain from an always-open audio session.
- iOS can still kill the app under memory pressure. If it dies, the mic key
  silently does nothing until you reopen the app. You would need a fallback that
  opens the app when the notification gets no answer.
- Phone calls, Siri, and other recording apps take the microphone away. Your
  session gets interrupted and you have to handle resuming it.
- App Review would almost certainly reject this. That does not matter for you,
  since you are sideloading to your own phone.
- **Nobody has published a working example.** The July research already noted a
  September 2025 Apple forum thread from a developer trying exactly this
  architecture, and it is still unanswered.

The test to run first: build a throwaway app that keeps an audio session open,
background it, and see whether it survives an hour of normal phone use and still
responds to a Darwin notification from its own keyboard extension. That single
test decides whether Option S is real. If it works, you have the thing you
actually want. If it does not, you fall back to the one-switch design below.

---

## Apple's own speech APIs, and what the "better accuracy" claim really means

Two things ship in iOS 26 and both run fully on the device with no cloud:

- `SpeechAnalyzer` with `SpeechTranscriber`. Built for long-form speech.
- `DictationTranscriber`. Built for short spoken commands and dictation.

Facts worth knowing:

- **Hebrew is on the list.** `SpeechTranscriber.supportedLocales` includes
  `he_IL`. Two independent dumps of the 42-locale list agree. Apple does not
  publish the list, so check it on your own device before trusting it.
- **The model runs outside your app's memory.** From WWDC25 session 277, word
  for word: "It operates outside of your application's memory space, so you
  don't have to worry about exceeding the size limit." It is served by a system
  daemon. So the memory objection does not apply to Apple's API at all.
- **This still does not help a keyboard**, because the block is on the
  microphone, not on the model. Apple's own keyboard gets to use dictation
  because it is not an extension. Yours is.

Now the accuracy claim, which is the part that gets misread everywhere:

**Apple's "roughly 4x more accurate" number is measured against Apple's own old
recognizer, `SFSpeechRecognizer`. It is not measured against whisper large.**
On the same English test harness the new API scores 2.12 percent word error rate
where the old one scored 9.02 percent. That is a real and large improvement in
Apple's own product. It says nothing about how it compares to your model.

Where whisper large was actually tested against it, whisper won:

| Source | Result |
|---|---|
| 9to5Mac, 2025-07-03 | whisper `large-v3-turbo` 0.4 to 1.4 percent word error rate. Apple 8.2 to 10.3 percent. Apple was faster and clearly less accurate. |
| get-inscribe, 2026-07 | Apple 2.12 and 4.56 percent, beating whisper **Small** (3.74 and 7.95) and old `SFSpeechRecognizer` (9.02 and 16.25). Whisper large was never tested. |
| MacStories, 2025-06-18 | About 2.2x faster than MacWhisper large-v3-turbo, "no noticeable quality difference." |
| Argmax, 2025-06-20 | 14.0 percent word error rate on earnings calls. No speaker separation. Custom vocabulary support was dropped compared to the old API. |

The one that says Apple beats whisper is comparing against whisper Small, not
large. That is the sleight of hand. Your bar is `ivrit-ai/whisper-large-v3-turbo`.

**And every single one of these benchmarks is English. Nobody has published a
Hebrew number for Apple's new API.** Since Hebrew is the whole point for you,
that number does not exist and you have to produce it yourself.

Worth noting: the iOS 27 beta reportedly improves dictation again. If Apple's
Hebrew gets good enough, this whole project stops being necessary. That is the
cheapest possible outcome and it is worth checking before writing any code.

---

## Whisper on iPhone: it is fast enough, and that is settled

| Question | Answer |
|---|---|
| Does `large-v3-turbo` run on a modern iPhone? | Yes. iPhone 13 and later handle it. |
| How fast? | WhisperKit on iPhone 15 Pro: 10 minutes of audio in about 82 seconds. Over 7x real time. Under 200 ms to the first word when streaming. |
| Which runtime? | WhisperKit (`argmaxinc`) is the better choice on iOS. It is Swift-native and built for the Neural Engine by ex-Apple engineers. Argmax reports about 45 percent lower latency and about 75 percent less energy per decoder pass than the alternative. Battery matters more on a phone than on a Mac. |
| Can I use my own ivrit-ai weights? | Yes. `argmaxinc/whisperkittools` converts any PyTorch whisper fine-tune to WhisperKit CoreML format: `whisperkit-generate-model --model-version ivrit-ai/whisper-large-v3-turbo --output-dir ... --generate-quantized-variants`. It can also publish the result to Hugging Face. |
| Memory? | A normal foreground app on an 8 GB iPhone has plenty of room for a quantized turbo model. If you hit the ceiling there is an entitlement, `com.apple.developer.kernel.increased-memory-limit`, that raises the per-app limit on iOS 15 and later. You probably will not need it. |
| whisper.cpp instead? | It works, but its CoreML path needs `coremlcompiler`, which only ships inside Xcode. Since you need Xcode for iOS anyway this is not a blocker, just extra work compared to WhisperKit. |

So: on the phone, the model is not the problem. The trigger is the problem.

---

## Hebrew: what actually supports it

| Option | Hebrew? | Verdict |
|---|---|---|
| `ivrit-ai/whisper-large-v3-turbo` | Yes, this is the best known Hebrew model | Your bar. Converts to WhisperKit. Runs fast on the phone. |
| Stock whisper small / base / tiny | Technically yes, poorly | No Hebrew fine-tune exists at these sizes. Nobody has published a Hebrew word error rate for them. `ivrit.ai` exists precisely because stock whisper's Hebrew is mediocre. Do not plan on this. |
| Apple `SpeechTranscriber` (iOS 26) | `he_IL` is in the locale list | Quality unmeasured in Hebrew by anyone. Test it yourself. |
| Apple built-in dictation | Yes, Hebrew (Israel) is listed for on-device dictation | This is what you already find bad. Worth re-testing on iOS 26 or 27, since your impression may predate them. Note that Hebrew has no Siri support at all, which tells you roughly how much attention Hebrew gets. |
| NVIDIA Parakeet | **No.** Not v2, not v3. | Already researched in `docs/parakeet/2026-08-24-parakeet-integration-options.md`. v3 covers 25 European languages and Hebrew is not one of them. Useful as a fast English-only second engine, nothing more. |

For mixed Hebrew and English in one sentence, whisper handles code-switching
better than most, because it is one multilingual model. Apple's API makes you
pick a locale, though a workaround using multiple transcribers exists. This is
another reason to prefer whisper for your use.

Where to check current Hebrew numbers:
`https://huggingface.co/spaces/ivrit-ai/hebrew-transcription-leaderboard`.

---

## Apple Watch: it cannot transcribe, and that is final

- **watchOS has no Speech framework at all.** `SpeechAnalyzer` and
  `SpeechTranscriber` are available on iOS, iPadOS, macOS, visionOS and tvOS.
  watchOS is the one platform excluded. The old `SFSpeechRecognizer` is not there
  either.
- **Running whisper on the watch is not realistic.** Even the smallest useful
  Hebrew model is large-class. The watch does not have the memory or the thermal
  headroom, and nobody publishes watchOS whisper benchmarks because nobody does
  it.
- **The watch can record.** `AVAudioRecorder` works in the foreground on
  watchOS 4 and later. Background recording is not a supported path.
- **The watch can send the file to the phone.** `WCSession.transferFile` is the
  channel. App Groups do not work across devices, so WatchConnectivity is the
  only option.
- **Watch to phone can wake the phone app in the background. Phone to watch
  cannot wake the watch app.** Transfers are opportunistic, not instant.

So the only possible watch design is: record on the wrist, transfer the file,
transcribe on the phone, save the note. Latency is not interactive. Expect a few
seconds for the transfer plus the transcription, and sometimes much longer if the
system decides to queue the transfer. This is a "leave yourself a voice note"
feature, not dictation.

**Cheaper answer, zero code:** watchOS 26 ships the Notes app, and it creates
notes by dictation that sync to your iPhone through iCloud. That already does
what you asked for on the watch, at Apple's Hebrew quality. Only build a watch
app if you test that and the Hebrew is unusable.

---

## What it takes to get this onto your own phone

**You need Xcode. You do not have it.** I checked your machine:

```
xcode-select -p          -> /Library/Developer/CommandLineTools
ls /Library/Developer/CommandLineTools/SDKs -> only MacOSX SDKs, no iPhoneOS SDK
/Applications/Xcode*.app -> not found
```

Command Line Tools has no iOS SDK, no simulator, no code signing for iOS, and no
way to build an `.app` bundle with extensions. Nivi on macOS builds with pure
SwiftPM and a Makefile, which is why you have gotten away without Xcode. That
trick does not extend to iOS. Budget a full Xcode install, which is roughly 10 to
15 GB, plus the platform support downloads.

Account and signing:

| | Free Apple ID | Paid, 99 USD a year |
|---|---|---|
| How long an install lasts | 7 days, then it stops launching | 1 year |
| Apps installed at once | 3 | No practical limit |
| New App IDs | 10 per 7 days, and each extension eats one | Not a concern |

An app plus a keyboard extension is 2 App IDs every time you change the bundle
identifier. With a keyboard you use every day, a weekly re-sign is miserable.
**Pay the 99 USD.** Nothing in 2026 removes the 7-day expiry. Sideloading tools
only automate the re-sign. TrollStore is dead on modern iOS. LiveContainer does
not support app extensions, which rules it out for a keyboard. The EU
alternative-distribution rules require you to be physically in an eligible
country, so they do not help from Israel, and they need paid membership anyway.

TestFlight is not a shortcut here. It also requires the paid program, and builds
expire after 90 days.

---

## Recommendation

**Before writing any code, run two tests. They cost an evening and they might end
the project.**

1. **Test Apple's Hebrew by ear.** Speak the same 5 sentences into iOS built-in
   dictation and into your Mac app. Mix Hebrew and English in at least two of
   them. If Apple's Hebrew is now good enough for you, stop. You already have
   seamless dictation everywhere, for free, and nothing you build will beat that
   on convenience. Your "Apple Hebrew is bad" impression may be from before
   iOS 26.
2. **Test Option S.** Build a throwaway app that opens an audio session, goes to
   the background, and answers a Darwin notification from its own keyboard
   extension an hour later. This is the only thing standing between you and a
   real zero-switch dictation keyboard. It has never been publicly proven either
   way.

**If test 1 fails and test 2 succeeds:** build the keyboard plus always-running
app design. Tap the mic key, speak, tap again, text appears. No app switch. Your
own model. This is the best outcome available.

**If test 1 fails and test 2 fails:** build the one-switch design. Nivi
keyboard with a mic key, which opens the app, records, transcribes with
`ivrit-ai/whisper-large-v3-turbo` through WhisperKit, writes the text to a shared
App Group container, and posts back. You tap the back chip and the keyboard
inserts the text. Cost per dictation: tap mic, speak, tap back. One visible
screen switch. That is worse than Apple's dictation on convenience and much
better on Hebrew quality. It is also exactly what every commercial dictation
keyboard does, so you would not be behind anyone.

Also add the Action Button and a Back Tap shortcut as a second entrance, for when
you are not in a text field and just want a transcript.

**Watch:** use the built-in Notes app. Revisit only if its Hebrew fails your ear
test.

**Prerequisites either way:** install Xcode, join the paid Apple Developer
Program, and convert the ivrit-ai weights with `whisperkittools`.

---

## Open questions

1. Hebrew word error rate for Apple `SpeechTranscriber` versus
   `ivrit-ai/whisper-large-v3-turbo`. Not published anywhere. Only you can
   produce it.
2. Whether an app with an always-open audio session survives normal daily phone
   use without being killed. Option S depends entirely on this.
3. Whether the "back to app" chip appears after a keyboard extension calls
   `extensionContext.open(URL)`. If it does not, the return trip costs an app
   switcher gesture instead of one tap.
4. `he_IL` in `SpeechTranscriber.supportedLocales` comes from secondary sources
   only. Confirm on a device.
5. Whether iOS 27 improves Hebrew dictation specifically. The reported
   improvements were tested in English.
