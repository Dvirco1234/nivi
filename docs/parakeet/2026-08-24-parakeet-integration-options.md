# Parakeet TDT 0.6B in Nivi — options review

Date: 2026-08-24. Status: complete.

**Short answer: Parakeet has no Hebrew. See section 1.**

Every claim below is labelled **verified**, **partly verified**, or **unverified**,
with a source link.

## 1. Hebrew verdict (read this first)

**Parakeet does not support Hebrew. Not v3, not v2. verified.**

- `nvidia/parakeet-tdt-0.6b-v3` is multilingual, but the list is 25 European
  languages only: bg, hr, cs, da, nl, en, et, fi, fr, de, el, hu, it, lv, lt, mt,
  pl, pt, ro, sk, sl, es, sv, ru, uk. Hebrew is not in it.
  **verified** — model card, https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3 (read 2026-08-24).
- `nvidia/parakeet-tdt-0.6b-v2` is English only. **verified** — same family, card says English.
- The v3 training data is the Granary corpus (~670k hours), which is a European
  languages corpus. So this is not an accident of the card text, it is what the
  model was trained on. **partly verified** — card states Granary + 25 languages;
  I did not audit the Granary language list itself.

### What this means for Nivi

Dvir's main use is Hebrew dictation with `ivrit-ai/whisper-large-v3-turbo`.
Parakeet cannot replace that. There is no fine-tune, no adapter, no "auto detect"
path that gets Hebrew out of this model. A Hebrew fine-tune would mean training
FastConformer from a Hebrew corpus, which is a research project, not an
integration project.

So the honest framing is:

- **As a replacement for the Hebrew model: dead. Do not start.**
- **As a second engine for English dictation: real, and quite attractive.**
  If Dvir dictates English often (code comments, PR descriptions, Slack,
  tickets), Parakeet v2/v3 on the Apple Neural Engine is much faster and lighter
  than whisper large-v3-turbo, and would let the app ship a "fast English" mode.
- **A third option worth naming:** the same runtime work (a CoreML/ANE backend
  behind `SpeechRecognizer`) is reusable. If a Hebrew CoreML Whisper or a future
  multilingual Parakeet appears, the seam is already built.

Everything below assumes the *English second engine* framing. If Dvir does not
dictate much English, the correct answer is to close this and keep whisper.cpp.


## 2. Runtime options comparison

Four ways to run FastConformer/TDT from a Swift macOS app.

| | **FluidAudio** | **sherpa-onnx** | **parakeet-mlx (Python)** | **Roll your own CoreML** |
|---|---|---|---|---|
| What it is | Swift package, CoreML models, runs on the Neural Engine | C++ library on ONNX Runtime, has a C API | Python + MLX | You convert the NeMo checkpoint yourself with coremltools and write the TDT decoder |
| Maturity | High. 2,685 stars, 46 commits in the last month, release v0.15.6 on 2026-08-19. **verified** (GitHub API, 2026-08-24) | Very high. 14,359 stars, pushed 2026-08-24. **verified** (GitHub API) | Moderate. 975 stars, last push 2026-06-05. **verified** (GitHub API) | n/a |
| License | Apache-2.0 **verified** | Apache-2.0 **verified** | Apache-2.0 **verified** | n/a |
| Language from Swift | Native Swift. `import FluidAudio` | C API through a `systemLibrary` shim, exactly like the current `CWhisper` | Embed a Python runtime in the .app | Native Swift + CoreML |
| Install | SwiftPM: `.package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.6")` **verified** (Package.swift + releases) | `make vendor`-style: clone, cmake, static libs. Same shape as whisper.cpp today. **partly verified** — sherpa-onnx documents cmake static builds; I did not build it here | pip + a bundled Python. | coremltools is Python, but only at build time |
| macOS floor | macOS 14.0, iOS 17.0 **verified** (its Package.swift). Nivi is already macOS 14+, so this fits exactly | macOS 10.x-ish, no problem | n/a | macOS 14 fine |
| Needs Xcode? | **No.** Pure SwiftPM, no build phases. Models ship as pre-compiled `.mlmodelc` bundles, so no `coremlc` step at build time. **partly verified** — Package.swift has no custom build phases and the HF repo ships `.mlmodelc` directories, which is the compiled form | No | No | **Yes, in effect.** Compiling an `.mlpackage` to `.mlmodelc` normally uses `coremlcompiler`, which ships inside Xcode. You would have to pre-compile on another machine |
| Swift version | Requires Swift 6.0 tools **verified**. Nivi is on Swift 5.10 — **this is a real friction point, see risks** | none | none | none |
| Binary added to the app | Small. Swift source + one binary target (`NemoTextProcessing`, a Rust FST engine). Models are downloaded, not bundled | ONNX Runtime static libs. Typically tens of MB per arch. **unverified** — I did not measure | 100s of MB of Python runtime | Tiny |
| Segment / word timestamps | **Yes, and better than whisper.** `ASRResult.tokenTimings: [TokenTiming]?` with `token, tokenId, startTime, endTime, confidence` (TimeInterval = seconds), plus a `WordTiming` aggregator that groups SentencePiece sub-words into words. **verified** — `Sources/FluidAudio/ASR/Parakeet/AsrTypes.swift` on main, read 2026-08-24 | Transducer decoding gives per-token frame indices; sherpa exposes token timestamps. **partly verified** | yes | you would write it |
| Native streaming | Yes, several: `SlidingWindowAsrManager`, `StreamingAsrManager`, `StreamingUnifiedAsrManager`, plus dedicated streaming checkpoints (`parakeet-realtime-eou-120m`, `nemotron-speech-streaming`). **verified** — file tree on main | Yes, streaming zipformer/transducer | no | no |
| Verdict | **Recommended** | Workable fallback | **Non-starter** | Last resort |

### Why parakeet-mlx is a non-starter

Nivi is a signed, notarised, distributable `.app`. Shipping Python means
bundling a Python framework, all of MLX and numpy, and then getting every one of
those dylibs signed and notarised. It bloats the app by hundreds of megabytes,
it breaks the "one static binary" model the app has today, and MLX runs on the
GPU rather than the Neural Engine, so it costs more battery than the CoreML path.
It is fine as a *research tool on the command line*, and that is actually useful
for the first milestone (see section 7), but it must not ship inside the app.
**partly verified** — repo is real and Apache-2.0; the packaging judgement is mine.

### Why sherpa-onnx is second, not first

It maps onto Nivi's existing habits almost perfectly: clone in `make vendor`,
cmake to static libs, expose a C API through a `systemLibrary` target, same as
`CWhisper`. Nothing new to learn. But you would then hand-write the Swift
wrapper, the timestamp plumbing, and the streaming loop, and you would pay for
ONNX Runtime CPU inference rather than the Neural Engine. FluidAudio gives you
the ANE and the decoder for free. Keep sherpa-onnx in your pocket for the case
where FluidAudio's Swift 6 requirement turns out to be a blocker.


## 3. Recommended approach

**Use FluidAudio, as a second engine for English only. Do not touch the Hebrew path.**

Reasons, in order:

1. It is the only option that is native Swift, SwiftPM-installable, and needs no
   Xcode. Nivi has no `.xcodeproj` and no Xcode installed. Every other route
   either needs `coremlcompiler` (which lives inside Xcode) or a whole new
   vendored C++ toolchain. **verified** for the Xcode-free claim on FluidAudio's
   side; see risks for the one thing I could not test.
2. Its macOS floor is 14.0 and iOS 17.0. Nivi is already `.macOS(.v14)`.
   Exact match, no bump needed. **verified** (both Package.swift files).
3. It runs on the Apple Neural Engine, not the GPU. That matters for a dictation
   app that runs in the background: the ANE is far cheaper on battery than Metal,
   and it leaves the GPU alone.
4. Its timestamps are *better* than what whisper.cpp gives you today. Whisper
   returns coarse segments; FluidAudio returns per-token start/end plus a word
   aggregator. `StreamingTranscriber` freezes committed text on segment
   boundaries, and word-level boundaries are strictly more precise than
   whisper's. **verified** — `AsrTypes.swift`.
5. It is actively maintained at a serious pace: 46 commits in the last 30 days,
   v0.15.6 shipped 2026-08-19. **verified** (GitHub API, 2026-08-24).

### Speed and accuracy, on Apple Silicon specifically

Ignore the 3,332x RTFx number on the NVIDIA model card. That is a data-centre GPU
running large batches. **verified** — several independent write-ups make this
point; e.g. https://embertype.com/blog/parakeet-v3-mac/ (read 2026-08-24).

FluidAudio publishes its own Apple Silicon numbers, which is what matters:

| Model | Hardware | Dataset | WER | RTFx |
|---|---|---|---|---|
| parakeet-tdt-0.6b-v3 | M4 Pro, 48 GB | FLEURS, 24 langs, 14,085 files | 14.7% | 209.8x |
| parakeet-tdt-0.6b-v3 | M4 Pro | LibriSpeech test-clean | 2.6% | 155.6x |
| parakeet-tdt-0.6b-v2 | M4 Pro | LibriSpeech test-clean | 2.1% | 145.8x |
| nemotron streaming 0.6B (2240 ms chunk) | Apple Silicon | LibriSpeech test-clean | 2.64% | 87.4x |

**verified** — https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md (read 2026-08-24).

Whisper large-v3-turbo on an M-series chip is commonly reported around 20-30x
real time. **partly verified** — this is a secondary source
(https://embertype.com/blog/parakeet-v3-mac/, and consistent with community
reports), not a measurement I made. FluidAudio's own docs contain no direct
Whisper comparison. **verified** (I checked Benchmarks.md).

So the honest speed claim is roughly **5x faster than whisper large-v3-turbo on
the same Mac**, not 100x. On English accuracy the two are close; Parakeet v2 at
2.1% WER on LibriSpeech test-clean is at least as good as Whisper.

For a dictation app the more interesting number is not throughput but **latency
per window**. A 10-second window at 150x is about 65 ms of compute. Today's
whisper pass on the same window is roughly 300-500 ms. That is the difference
between a preview that keeps up with the speaker and one that trails. This is
the actual reason to do this work.

## 4. Model artifact shape

This is where the current design breaks. `ManagedModel.localFileName` returns
`"<id>.bin"`, one file, and the catalog entry points at a single `.nemo` file
that FluidAudio cannot read anyway. **verified** — read `ManagedModel.swift`
and `ModelCatalogStore.swift` in this repo.

The real artifact is **a folder of compiled CoreML bundles**, and each bundle is
itself a directory, not a file.

HuggingFace repo: `FluidInference/parakeet-tdt-0.6b-v3-coreml`
(and `...-v2-coreml` for English-only). **verified** — `Repo` enum in
`Sources/FluidAudio/ModelRegistry.swift`.

The whole v3 repo is **3.59 GB**, but you do not download all of it. FluidAudio
picks a required subset. For v3 at the default int8 precision that is
`Preprocessor.mlmodelc`, `Encoder_v2.mlmodelc`, `Decoder.mlmodelc`,
`JointDecisionv3.mlmodelc`, plus `parakeet_vocab.json`.
**verified** — `ModelNames.ASR.requiredModelsV3(precision:)`, and
`AsrModels.load` picks `JointDecisionv3.mlmodelc` for v3.

Directory sizes, measured from the HuggingFace API on 2026-08-24 (**verified**):

| Bundle | v3 size | Needed for v3 int8? |
|---|---|---|
| `Preprocessor.mlmodelc` | 0.5 MB | yes |
| `Encoder_v2.mlmodelc` (int8) | 595 MB | yes (default) |
| `EncoderInt4.mlmodelc` | 299 MB | alternative, smaller |
| `Encoder.mlmodelc` | 446 MB | no (older) |
| `Decoder.mlmodelc` | 24 MB | yes |
| `JointDecisionv3.mlmodelc` | 12.7 MB | yes |
| `parakeet_vocab.json` | 0.2 MB | yes |
| everything else (`MelEncoder`, `mlpackages`, `ParakeetEncoder_15s`, ...) | ~2.2 GB | no |

**Practical download: about 632 MB for v3 at int8, or about 336 MB at int4.**
Compare with 1.62 GB for the current Hebrew whisper model. So Parakeet is
roughly a third of the size and several times faster — for English.

Two things to be honest about:

- I have not verified which precision `ParakeetEncoderPrecision` defaults to at
  runtime; the signature default is `.int8`, but a caller may override it.
  **partly verified.**
- FluidAudio downloads models itself, into its own cache directory
  (`AsrModels.defaultCacheDirectory(for:)`, built from
  `MLModelConfigurationUtils.defaultModelsDirectory`). **verified** (source), but
  I did not confirm the exact path on disk. **partly verified.**
  That matters a lot for section 5.

## 5. Changes needed in this codebase

### 5.1 The single-file download assumption

Today, everything about installing a model assumes one file:

- `ManagedModel.localFileName` → `"<id>.bin"` (`Sources/NiviCore/ManagedModel.swift`)
- `ModelPaths.installedURL(for:base:)` → `models/<id>.bin` (`Sources/NiviCore/ModelCatalogStore.swift`)
- `ModelCatalogStore.isInstalled` → one `ModelSpec` validated against one file's size
- `ModelStore.install` → `downloader.download(model, to: installedURL(...))`, one URL in, one file out (`Sources/Nivi/ModelStore.swift`, `Sources/Nivi/ModelManager.swift`)
- `ModelStore.delete` → `removeItem(at:)` on one path
- `ModelSource.huggingFace(repo:file:)` → one `file`

**The smallest honest change: make the install unit a *directory*, not a file.**

Concretely:

1. Replace `var localFileName: String` with something like
   `var localPath: String` plus a flag for whether it is a file or a directory,
   or better, let `ModelEngine` decide: whisper → `"<id>.bin"`,
   parakeet → `"<id>/"`. Keep `localFileName` as a deprecated shim so old
   catalogs decode.
2. Add a `ModelSource` case for a multi-file HuggingFace repo, e.g.
   `.huggingFaceRepo(repo: String, files: [String])`. The existing
   `.huggingFace(repo:file:)` stays for whisper.
3. `isInstalled` becomes: for a directory model, every required entry exists and
   the total is above `minSizeBytes`. Today it validates one file's size, which
   is a reasonable check to generalise rather than replace.
4. `delete` already uses `removeItem(at:)`, which removes directories too. Likely
   no change, but worth a test.
5. Progress reporting: `install` reports one `Double`. With 4 files you need
   aggregate progress, so `ModelDownloader.download` needs a byte-weighted total
   across files rather than per-file fraction.

**There is a shortcut worth considering.** FluidAudio already downloads and
caches models itself (`AsrModels.downloadAndLoad(version:)`), with progress,
offline mode, and validation. Nivi could simply *not* download Parakeet, and
let FluidAudio do it, with `ModelStore` only asking "does the cache exist?".
That removes almost all of the work above. The cost is that Nivi loses
control of where the bytes land and how progress is shown, and the model would
live outside `~/Library/Application Support/Nivi/models/`. **Decide this
early — it is the single biggest fork in the design.**

### 5.2 Engine dispatch

`Sources/Nivi/RecognizerCache.swift` hardcodes
`WhisperCppRecognizer(modelPath: modelPath)`. It also takes `id` and `modelPath`
only, so it cannot see the engine. Change `recognizer(id:modelPath:)` to
`recognizer(for: ManagedModel, modelPath: URL)` and switch on `model.engine`.
Everything else in that actor (LRU, `unload()` on evict) works unchanged, since
both backends conform to `SpeechRecognizer`.

### 5.3 A new recognizer

New file `Sources/Nivi/ParakeetRecognizer.swift`, conforming to
`SpeechRecognizer`. Mapping notes:

- `load()` → `AsrModels.load(...)` + `AsrManager.configure(models:)`.
- `transcribe(samples:language:)` → `asrManager.transcribe(samples, source:)`,
  return `result.text`. Samples are already 16 kHz mono Float32 in this app,
  which is exactly what FluidAudio wants. **verified** (its README states the
  16 kHz mono Float32 [-1,1] requirement).
- `transcribeSegments(samples:language:audioCtx:) -> [TranscriptSegment]` →
  build from `result.tokenTimings` via the `WordTiming` aggregator, then group
  words into segments. `TokenTiming.startTime/endTime` are `TimeInterval`
  (seconds); `TranscriptSegment` wants `Int` milliseconds, so multiply by 1000.
- **`audioCtx` is meaningless for Parakeet.** It exists because whisper's encoder
  always runs a 30-second context. FastConformer's encoder is proportional to the
  input, so a 10-second window genuinely costs 10 seconds of work. The parameter
  should simply be ignored by this backend. Worth a comment saying so, because
  the next reader will assume it was forgotten.
- `unload()` → drop the `AsrManager` and models. Whether FluidAudio needs an
  explicit teardown is **unverified**; `WhisperCppRecognizer`'s serial-queue
  discipline exists because `whisper_free` racing an in-flight call is a
  use-after-free. `AsrManager` is an `async` Swift type, so an actor is probably
  enough, but confirm before trusting it.

### 5.4 `Package.swift`

Add `.package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.6")`
and `"FluidAudio"` to the `Nivi` target's dependencies. No linker flags, no
frameworks, no `make vendor` step. FluidAudio pulls one binary target
(`NemoTextProcessing`, a Rust FST engine) — **that binary will need to be
code-signed as part of the .app**, see risks.

`Package.swift` declares `swift-tools-version: 5.10` and FluidAudio declares
`6.0`. A 5.10 root package may depend on a 6.0 package as long as the installed
toolchain is Swift 6+. This machine has **Swift 6.3.3**, so it works.
**partly verified** — the toolchain version is verified (`swift --version`); I
did not actually resolve the dependency.

### 5.5 Catalog entries

The two existing Parakeet entries in `ModelCatalog.seeded()` are wrong on three
counts and must be rewritten: the source points at a `.nemo` file that no Swift
runtime can read; v3's `defaultLanguage` is `"auto"` and its summary implies
general multilingual use, which will read to a Hebrew user as "this covers me";
and `sizeBytesApprox` of 496 MB is the NeMo checkpoint, not the ~632 MB of
CoreML bundles. `isRunnable` correctly returns `false` today, which is why none
of this has bitten yet.

### 5.6 Makefile

`make vendor` stays exactly as is. Parakeet adds nothing to it — this is a
SwiftPM dependency, not a vendored C library. That is a genuine advantage over
sherpa-onnx, which would need a second vendor block.

## 6. Risks and open questions

Ordered by how badly each one could hurt.

1. **Hebrew, again.** This whole project does nothing for the app's main use.
   If Dvir does not dictate English regularly, the correct decision is to stop
   here. Everything below only matters if the answer is "yes, I dictate English
   a lot". **This is the biggest risk: building the right thing correctly for a
   use case that turns out to be rare.**
2. **Code signing the FluidAudio binary target.** `NemoTextProcessing` is a
   prebuilt binary (`.artifactbundle`) pulled from a GitHub release. Nivi
   signs with a stable "Nivi Self-Signed" identity, and macOS keys TCC grants
   (Microphone, Accessibility, Input Monitoring) to that identity. An unsigned
   or wrongly-signed nested binary can make `codesign` fail, or worse, succeed
   and then silently break permissions. **unverified** — I did not attempt a
   build or a signing pass. Treat this as the first thing to test.
3. **Where the models live.** If Nivi lets FluidAudio manage downloads, the
   model bytes land outside `~/Library/Application Support/Nivi/models/`.
   The Preferences UI, the "installed" badge, and delete-to-free-space all
   assume Nivi owns those files. Pick one owner and stick with it.
4. **Two model sets on disk.** Keeping whisper for Hebrew *and* adding Parakeet
   for English means ~1.62 GB + ~632 MB. `RecognizerCache` already evicts by
   LRU, but disk is not evicted. Worth a note in the UI.
5. **Swift 6 concurrency.** FluidAudio's types are `Sendable` and it targets
   Swift 6 strict concurrency. Nivi is on 5.10 language mode with
   `@MainActor` classes and an actor cache. It should interoperate, but expect
   some `Sendable` friction at the boundary. **unverified.**
6. **The `audioCtx` seam is whisper-shaped.** `SpeechRecognizer` has whisper's
   encoder quirk baked into its signature. It works fine for Parakeet by
   ignoring it, but a third backend would make this smell. Not urgent.
7. **Streaming: two designs, and the second is better.** The app re-transcribes
   a sliding ~10s window. FluidAudio supports exactly that
   (`SlidingWindowAsrManager`), so a like-for-like port is straightforward. But
   it also ships *true* streaming transducers with encoder caching
   (`StreamingAsrManager`, `parakeet-realtime-eou-120m`,
   `nemotron-speech-streaming-en-0.6b` at 560/1120/2240 ms chunks) which never
   re-do work. That would be a real architectural improvement over re-transcribing
   — but it is a different shape from `SpeechRecognizer`, which is a
   stateless "samples in, text out" call. **Do not attempt this in v1.** Port the
   window first, keep the protocol, and revisit streaming later.
8. **v3 language claims disagree slightly.** NVIDIA's card says 25 languages;
   FluidAudio's README says "25 European languages + Japanese" and the repo has a
   separate `parakeet-0.6b-ja-coreml`. Doesn't change the Hebrew answer, but it
   means the language list should be read from the runtime, not hardcoded.
   **partly verified.**
9. **Not measured by me:** actual `.app` size increase, actual first-launch
   download time, actual memory during inference, and whether the ANE is
   available and used on Dvir's specific Mac. All **unverified**.

## 7. First milestone (cheap proof)

The point of milestone one is to kill the project quickly if it is going to die.
It should touch nothing under `Sources/`.

**Step 0 — the only question that matters (5 minutes, no code).**
Does Dvir dictate English often enough to want a second engine? If no, stop.

**Step 1 — does it even transcribe, outside the app (30 minutes).**
Clone FluidAudio into a scratch directory and run its own CLI:

    swift run fluidaudiocli transcribe some-english-recording.wav

This proves, with zero commitment: the package builds on this machine with Swift
6.3.3, the models download, the ANE path works, and the English quality is
acceptable on *Dvir's own voice and vocabulary* rather than on LibriSpeech.
It also tells you the real download size and the real cache path, which
section 4 and risk 3 both depend on.

**Step 2 — the two risks that actually block (half a day).**
In a throwaway SwiftPM executable, not in Nivi:

- a. Add FluidAudio as a dependency of a 5.10-tools-version package. Confirm
     resolution works. (Risk 5.)
- b. Build it into a minimal `.app` bundle and sign it with the
     `Nivi Self-Signed` identity. Confirm `codesign --verify --deep` passes
     with the nested `NemoTextProcessing` binary. **This is the real gate.**
     (Risk 2.)
- c. Print `result.tokenTimings` for a 10-second clip and confirm the times are
     sane and in seconds. (Confirms the `transcribeSegments` mapping.)

If (b) fails, stop and reconsider sherpa-onnx, which produces plain static libs
with no nested binaries to sign.

**Step 3 — only then, the real work.** In order: `ParakeetRecognizer`, then
engine dispatch in `RecognizerCache`, then the multi-file model install. Note
that the recognizer comes *first* — you can hard-code a model path while
proving inference, and defer the whole `localFileName` redesign until you know
the integration works.

**Explicitly out of scope for v1:** native streaming transducers (risk 7),
Hebrew (section 1), and replacing whisper.cpp. Parakeet is an addition, not a
replacement.

## Sources

All read on 2026-08-24.

- [nvidia/parakeet-tdt-0.6b-v3 model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) — language list, license, architecture
- [FluidInference/FluidAudio](https://github.com/FluidInference/FluidAudio) — repo, releases, activity
- [FluidAudio Package.swift](https://github.com/FluidInference/FluidAudio/blob/main/Package.swift) — platforms, tools version, dependencies
- [FluidAudio AsrTypes.swift](https://github.com/FluidInference/FluidAudio/blob/main/Sources/FluidAudio/ASR/Parakeet/AsrTypes.swift) — `ASRResult`, `TokenTiming`, `WordTiming`
- [FluidAudio AsrModels.swift](https://github.com/FluidInference/FluidAudio/blob/main/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/TDT/AsrModels.swift) — load, download, cache
- [FluidAudio ModelNames.swift](https://github.com/FluidInference/FluidAudio/blob/main/Sources/FluidAudio/ModelNames.swift) — required model files
- [FluidAudio ModelRegistry.swift](https://github.com/FluidInference/FluidAudio/blob/main/Sources/FluidAudio/ModelRegistry.swift) — HF repo slugs
- [FluidAudio Benchmarks.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md) — Apple Silicon WER / RTFx
- [FluidAudio ASR GettingStarted.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/GettingStarted.md) — API usage, v2 vs v3
- [FluidInference/parakeet-tdt-0.6b-v3-coreml](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml) — CoreML artifacts and sizes
- [k2-fsa/sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) — alternative runtime
- [csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8](https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8) — ONNX exports (~670 MB int8)
- [senstella/parakeet-mlx](https://github.com/senstella/parakeet-mlx) — Python/MLX path
- [Parakeet v3 on Mac, honestly judged](https://embertype.com/blog/parakeet-v3-mac/) — secondary source for the "3,332 RTFx is a GPU number" caveat and M-series whisper speeds
