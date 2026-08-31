# On-device Hebrew Speech Recognition — Model Landscape (iPhone / Watch)

Research date: 2026-07-26. Bar for comparison: `ivrit-ai/whisper-large-v3-turbo-ggml` (~1.6GB) running via whisper.cpp on macOS today — Dvir's quality bar.

Labels: **verified** (confirmed on a primary source, e.g. the HF repo page itself), **partly verified** (secondary source / plausible, not cross-checked against a primary source), **unverified** (anecdotal, forum post, or inferred).

---

## 1. ivrit-ai model lineup on HuggingFace

**Key finding: no smaller/quantized Hebrew-tuned model exists in the ivrit-ai org today.** Every ASR repo in the org is a `large` or `large-v3(-turbo)`-class model. There is no `small`, `base`, `tiny`, or `distil` Whisper Hebrew fine-tune published by ivrit-ai.

Repos observed under `huggingface.co/ivrit-ai` (partly verified — via WebFetch of the org page + GitHub catalog cross-check, not a raw API listing):

| Repo | Notes |
|---|---|
| `ivrit-ai/whisper-large-v3` | Hebrew fine-tune of Whisper large-v3 (full ~1.5B param class) |
| `ivrit-ai/whisper-large-v3-ct2` | CTranslate2 format of the above |
| `ivrit-ai/whisper-large-v3-turbo` | Hebrew fine-tune of Whisper large-v3-turbo (~809M params, the "turbo" distilled-decoder variant) — this is what Dvir already uses |
| `ivrit-ai/whisper-large-v3-turbo-ct2` | CTranslate2 format |
| `ivrit-ai/whisper-large-v3-turbo-onnx` | ONNX format |
| `ivrit-ai/whisper-large-v3-turbo-ggml` | ggml format used by whisper.cpp — this is Dvir's current model (~1.6GB, verified by his own working app) |
| `ivrit-ai/whisper-large-v3-ggml` | ggml format of the non-turbo large-v3 fine-tune (larger, ~2.9GB class) |
| `ivrit-ai/whisper-v2-d4`, `faster-whisper-v2-d4` | Earlier-generation large-v2 fine-tune, still large-class |
| `ivrit-ai/yi-whisper-large-v3`, `yi-whisper-large-v3-turbo` (+ ct2/ggml variants) | These are **Yiddish**, not smaller Hebrew models — easy to misread the "yi-" prefix as something else |

Other Hebrew ASR models exist from *different* orgs (not ivrit-ai, not necessarily whisper-based, not necessarily as strong):
- `imvladikon/wav2vec2-xls-r-300m-hebrew` and `imvladikon/wav2vec2-large-xlsr-53-hebrew` — wav2vec2-based, 300M params, most-downloaded Hebrew STT models on HF, but a different architecture (not whisper.cpp-compatible) and no public evidence they beat ivrit-ai's whisper fine-tune.
- A `whisper-medium-he` and a `whisper-heb-ipa` exist from third parties (per the `danielrosehill/Hebrew-AI-Models` catalog) — **unverified**, not checked directly, not from ivrit-ai, quality unknown.

**Implication:** there's no "free lunch" mid-size Hebrew-tuned whisper drop-in. The only ivrit-ai-quality option is large-v3-turbo class (~1.6GB ggml, ~809M params) or bigger. Getting a smaller Hebrew-tuned model would require either (a) someone fine-tuning `whisper-small`/`base` on ivrit-ai's Hebrew corpus (their training data/recipe is public — `ivrit.ai/en/2025/02/13/training-whisper/` — so this is technically reproducible but not something that exists off-the-shelf), or (b) quantizing large-v3-turbo further (q5_1/q8_0 already used; going below that degrades quality/increases hallucination risk per whisper.cpp community reports).

Source: [ivrit-ai org page](https://huggingface.co/ivrit-ai), [Hebrew-AI-Models catalog](https://github.com/danielrosehill/Hebrew-AI-Models), [ivrit.ai training blog post](https://www.ivrit.ai/en/2025/02/13/training-whisper/).

---

## 2. whisper.cpp / WhisperKit on iPhone

**Model size → runtime RAM (multilingual whisper.cpp ggml, partly verified — general whisper.cpp community figures, not iPhone-specific benchmarks):**

| Model | File size (~) | Runtime RAM (~) |
|---|---|---|
| tiny (q5_1) | 77 MB | ~270–300 MB |
| base | 142 MB | ~500 MB |
| small | 466 MB | ~1.0 GB |
| large-v3-turbo (fp16) | ~1.6 GB | ~2.5–3 GB+ (unverified exact figure for turbo specifically) |
| large (full, fp16) | ~2.9 GB | ~3.9 GB |

Runtime RAM is consistently reported as noticeably higher than file size (roughly 1.7–3x), which matters a lot for an iOS keyboard extension's memory ceiling (that constraint is being researched separately, per instructions — flagging only the raw number here).

**Quantization in practice:** whisper.cpp production/iOS deployments commonly use `q5_1` (≈5.5 bits/weight effective) as the default balance point, or `q8_0` (≈8.5 bits/weight) when more headroom is available — q8_0 is described as "the sweet spot" for large-v3-turbo specifically, cutting memory nearly in half vs fp16 with no perceptible accuracy loss (partly verified, single source: fazm.ai blog).

**WhisperKit (Argmax) vs whisper.cpp:** WhisperKit is a Swift-native, CoreML/ANE-first implementation built by ex-Apple ANE engineers; whisper.cpp is more broadly cross-platform (Metal/CoreML/CPU) but not as deeply ANE-tuned. On Apple silicon specifically, WhisperKit is reported to edge ahead on latency and especially energy efficiency (Argmax cites ~75% lower energy per decoder forward-pass with their "stateful models" optimization, and 45% latency reduction, for large-v3-turbo) (partly verified — vendor's own benchmark, arXiv paper 2507.10860, not independently reproduced). WhisperKit also publishes an actual benchmark suite (`argmaxinc/argmax-oss-swift` discussions) with per-device numbers, but I did not extract per-model-size RAM figures for A16/A17/A18 specifically — that would need a direct read of their benchmark dashboard, which wasn't feasible in the search budget for this pass.

**Verdict:** WhisperKit is worth using over raw whisper.cpp on iOS if going the whisper route — same underlying weights (including custom ones like ivrit-ai's, which can be converted to CoreML), but better battery/thermal behavior on Apple Neural Engine. It's not a different model — it doesn't change the memory-footprint-vs-quality tradeoff, only the efficiency of running a given model.

Sources: [whisper.cpp models README](https://github.com/ggml-org/whisper.cpp/blob/master/models/README.md), [fazm.ai large-v3-turbo guide](https://fazm.ai/blog/ggml-large-v3-turbo-bin), [Cactus: Argmax WhisperKit vs whisper.cpp](https://cactuscompute.com/compare/argmax-vs-whisper-cpp), [Argmax WhisperKit blog](https://www.argmaxinc.com/blog/whisperkit), [arXiv 2507.10860](https://arxiv.org/abs/2507.10860).

---

## 3. Hebrew quality by model size

**Directly on point — ivrit.ai's own benchmark (Daniel Dorman, Medium, partly verified — single source, methodology not independently checked), all at "large" size, beam sizes 5 and 15:**

| Model | WER @ beam 5 | WER @ beam 15 |
|---|---|---|
| Whisper v2 (stock, large) | 16.53% | 15.03% |
| Whisper v3 (stock, large) | 14.19% | 13.86% |
| ivrit.ai v2-d3-e3 (fine-tune) | 14.02% | 15.19% |
| ivrit.ai v2-d4 (fine-tune) | **10.35%** | **11.52%** |
| Amazon Transcribe (cloud, reference) | 9.85% | 9.85% |

This shows the ivrit.ai Hebrew fine-tune closes most of the gap to a commercial cloud ASR, and stock (non-Hebrew-tuned) Whisper large is ~4-6 points worse. This benchmark predates the current `large-v3-turbo` ivrit-ai release, so exact numbers for Dvir's current model weren't found, but it's described as "state of the art" for Hebrew by ivrit-ai's own materials (unverified precise number for large-v3-turbo).

**No data found for smaller Whisper sizes (tiny/base/small) on Hebrew specifically**, from either stock OpenAI Whisper or a hypothetical Hebrew fine-tune — because, per finding #1, no Hebrew-tuned small model exists to benchmark. General (non-Hebrew) Whisper literature shows small/base/tiny have substantially higher WER than large across all languages, more so for lower-resource languages — Hebrew, not being English, would very plausibly fall on the "more degraded" side of that gap (**unverified inference**, not a cited Hebrew-specific number). This is the single biggest unresolved unknown in this research: shrinking to small/base would likely cost significant accuracy on Hebrew and nobody has published a number for it.

Source: [Comparing Whisper, Whisper-FT and Amazon Transcribe for Hebrew (Medium)](https://medium.com/@DormanDaniel/comparing-whisper-whisper-ft-and-amazon-transcribe-for-hebrew-e297846bdd24).

---

## 4. Apple SpeechAnalyzer / SpeechTranscriber (iOS 26)

**Hebrew is supported.** `SpeechTranscriber.supportedLocales` includes `he_IL` (partly verified — pulled from a search-engine-summarized third-party source describing the API's locale list, not a direct read of Apple's live doc page, which returned no body text on fetch; worth a manual spot-check in Xcode before relying on it, but two independent sources agree Hebrew is in the 56-language iOS 26 speech list).

**On-device: yes, verified concept.** `SpeechAnalyzer`/`SpeechTranscriber` (introduced WWDC 2025, shipped iOS 26) is described consistently across multiple sources as strictly on-device, system-managed models (no cloud fallback), replacing/augmenting the older `SFSpeechRecognizer`.

**Quality vs old dictation: meaningfully better, but only benchmarked in English so far.** One cited third-party benchmark (GIGAZINE, July 2026) reports SpeechAnalyzer beating `SFSpeechRecognizer` head-to-head: 2.12% vs 9.02% WER on clear speech, 4.56% vs 16.25% on harder speech — roughly a 4x error reduction (partly verified, single source, LibriSpeech/English only). Separately, that same source claims SpeechAnalyzer surpasses **Whisper Small** on English benchmarks (unverified how "surpasses" is defined, and this is Whisper *Small*, not large-v3-turbo, so it doesn't imply parity with Dvir's ivrit-ai bar).

**No Hebrew-specific quality benchmark for SpeechAnalyzer was found.** This is the critical unknown for question 4: Apple's old Hebrew dictation is (per Dvir) bad, but nothing found here confirms whether SpeechAnalyzer's Hebrew model is a from-scratch improvement or the old acoustic model with a nicer decoding/punctuation layer bolted on. Given Apple historically under-invests in Hebrew (small-market, RTL, morphologically rich language) relative to English, **do not assume** the 4x English improvement transfers to Hebrew — this needs an actual on-device test (record real Hebrew speech, run SpeechTranscriber, compare to ivrit-ai output) before being trusted as "maybe we don't need whisper on iOS."

**Practical implication:** it's cheap to test — `SpeechTranscriber` is a system framework, no model download, no memory budget fight. Worth a first-class spike: if Hebrew quality is close to ivrit-ai's, it eliminates the entire memory-budget problem for iPhone (and possibly Watch, see below) instead of trying to squeeze whisper into constrained environments.

Sources: [SpeechTranscriber – Apple Developer Documentation](https://developer.apple.com/documentation/speech/speechtranscriber) (locale list not confirmed directly — see caveat above), [GIGAZINE: Apple's on-device speech recognition API surpasses Whisper Small](https://gigazine.net/gsc_news/en/20260714-apple-speech-analyzer-benchmark/), [Michael Tsai blog roundup](https://mjtsai.com/blog/2026/07/22/whisper-and-speechanalyzer/), [Argmax: Apple SpeechAnalyzer and WhisperKit](https://www.argmaxinc.com/blog/apple-and-argmax).

---

## 5. watchOS feasibility

**Recording audio on-watch:** Yes, verified as technically supported. A watchOS app can access the microphone and record; background recording requires the `audio` value in `UIBackgroundModes` in Info.plist (partly verified via Kodeco tutorial + Apple dev forum thread, standard/expected pattern, not surprising). Duration caps for a foreground recording session were not pinned down to a specific number in this pass — Apple's docs likely specify session limits for `WKAudioRecorder` but that page wasn't directly fetched; treat "how long can I record uninterrupted" as **unverified/needs direct API doc check**, not zero-risk.

**On-watch inference:** Not researched in depth because it's clearly not viable at these model sizes — even the smallest Hebrew-quality option here (large-v3-turbo, ~1.6GB+ RAM) is far beyond what's sane to run on watchOS hardware (S9/S10 SiP, shared with WatchOS's own tight memory ceiling, no meaningful ANE headroom documented for third-party ML at this scale). No source was found claiming on-watch Whisper inference at any practical size; treating this as **unverified but very likely infeasible** rather than confirmed-impossible, since nobody publishes watchOS Whisper benchmarks (an absence-of-evidence signal, not a citation).

**Conclusion: audio must be transferred to iPhone for inference.** This makes WatchConnectivity the load-bearing piece.

**WatchConnectivity file transfer:** `transferFile` is the standard mechanism for moving a recorded audio file (or any file) from Watch to iPhone. Confirmed characteristics (partly verified, no hard numeric size cap found in this pass):
- Transfer happens over Bluetooth/WiFi between the paired devices; no hard documented byte-size ceiling was found, but larger files take longer and cost more battery — practical guidance is "keep it small," which for a few minutes of compressed speech audio (tens of KB to a few MB) is a non-issue.
- Transfers queue and complete opportunistically; they do **not** require the phone to be in constant BT range at the moment `transferFile` is called — WatchConnectivity is designed to complete transfers when connectivity is available (background-capable), though "out of range" behavior specifics (exact retry/timeout policy) weren't independently verified here — **unverified**, worth checking Apple's `WCSessionDelegate` docs directly (`session(_:didFinish:error:)`) before relying on it for a "record on watch away from phone, syncs later" UX.

**Writing to Notes / triggering a Shortcut from the watch:**
- **Apple Notes now has a native watchOS app (watchOS 26+)** — a user can create/dictate notes directly from the watch UI (support.apple.com confirms this, verified). But that's Apple's own dictation (the "really bad" Hebrew one) writing directly — it doesn't help route ivrit-ai-quality text into Notes.
- **Shortcuts/App Intents from a standalone watch app are limited**: shortcuts cannot be *created* on-watch (only synced from iPhone-authored ones), and critically, **App Intents defined by a standalone watchOS app do not reliably surface in the Watch's Shortcuts app** (per an Apple Developer Forums thread) — this is a real constraint, not a nice-to-have gap.
- **Practical architecture implication:** the watch side should only be responsible for record + transfer; all "smart" work (whisper/ivrit-ai transcription, writing into Notes, any Shortcuts automation) should happen iPhone-side after the file lands via WatchConnectivity. Do not plan on the watch app writing to Notes or invoking a Shortcut directly — route everything through the phone.

**One-line verdict:** watchOS can record and hand off audio reliably, but must not attempt inference — transfer the audio file to iPhone via `WCSession.transferFile` and do all transcription + Notes-writing there.

Sources: [Audio Recording in watchOS Tutorial (Kodeco)](https://www.kodeco.com/345-audio-recording-in-watchos-tutorial/page/2), [watchOS: Resume recording from AudioInterruption in background mode (Apple Dev Forums)](https://developer.apple.com/forums/thread/750432), [Using transferFile and sendMessage in WatchConnectivity SwiftUI (Medium)](https://medium.com/@bryan.vernanda/using-transferfile-and-sendmessage-in-watch-connectivity-swiftui-edee23c69286), [Create and view notes on Apple Watch (Apple Support)](https://support.apple.com/guide/watch/create-and-view-notes-apdc6fb0a03f/watchos), [App Intents does not work with standalone watchOS (Apple Dev Forums)](https://developer.apple.com/forums/thread/718355), [Intents not showing up in WatchOS Shortcuts (Apple Dev Forums)](https://developer.apple.com/forums/thread/770259).

---

## Summary table

| Model | File size | Est. runtime RAM | Hebrew quality | Verdict iPhone | Verdict Watch |
|---|---|---|---|---|---|
| `ivrit-ai/whisper-large-v3-turbo-ggml` (current mac model) | ~1.6 GB | ~2.5–3 GB+ (unverified exact) | Best known — SOTA-ish Hebrew fine-tune, ~10-12% WER class (on predecessor v2-d4; turbo not separately benchmarked) | Likely too heavy for a memory-constrained context (e.g. keyboard extension — see separate research); fine for a standalone full app | Infeasible on-watch; would need transfer to iPhone anyway |
| `ivrit-ai/whisper-large-v3-ggml` (non-turbo) | ~2.9 GB | ~3.9 GB | Same fine-tune family, slightly different base — no smaller | Too heavy for most iOS contexts | Infeasible |
| Stock `whisper-small`/`base`/`tiny` (no Hebrew tune) | 466/142/77 MB | ~1.0GB/500MB/~300MB | Meaningfully worse than large — no Hebrew-specific WER found, but general pattern + non-English penalty suggests a real quality cliff (unverified magnitude) | Fits memory budgets easily, but quality drop is the real question — untested for Hebrew | Still too heavy/no on-watch runtime story regardless of size — not why it matters here |
| No Hebrew-tuned small/base/distil model exists (ivrit-ai or otherwise, verified) | — | — | N/A | N/A — this option doesn't currently exist; would require training one | N/A |
| Apple `SpeechAnalyzer`/`SpeechTranscriber` (iOS 26+) | 0 (system framework, no app-bundled model) | Negligible app-side | Unknown for Hebrew specifically — 4x WER improvement over old SFSpeechRecognizer shown only in English; Hebrew untested here | **Worth a first spike before committing to whisper on iOS** — could remove the memory problem entirely if Hebrew quality holds up | Not directly usable on-watch (no evidence of watch-side SpeechAnalyzer); still requires phone-side processing, but same "maybe no model needed at all" logic applies once audio reaches the phone |

## Open questions / follow-ups

1. **Untested, decisive question:** actually record Hebrew speech and run it through iOS 26 `SpeechTranscriber` vs ivrit-ai large-v3-turbo, side by side. This single test resolves questions 3 and 4 simultaneously and could obviate most of the memory-budget problem.
2. Exact WhisperKit RAM numbers per iPhone chip generation (A16/A17/A18) — the `argmaxinc/argmax-oss-swift` benchmark discussion (#243) exists but wasn't read in depth; worth a direct fetch if the whisper.cpp/WhisperKit path is still pursued after the SpeechAnalyzer spike.
3. `WKAudioRecorder` exact duration caps and `WCSession.transferFile` size ceiling — not found with a hard number in this pass, only qualitative guidance. Worth checking Apple's own API reference directly.
4. Whether ivrit-ai's public training recipe (`ivrit.ai/en/2025/02/13/training-whisper/`) could realistically be applied to fine-tune `whisper-small` or `-base` for a mid-size Hebrew model — this is a build-it-yourself option, not something available off the shelf today.
