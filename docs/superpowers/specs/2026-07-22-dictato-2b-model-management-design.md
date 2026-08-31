# Dictato 2b — Model Management + Preferences App-Shell (Design Spec)

Date: 2026-07-22
Status: Approved
Predecessor: `2026-07-22-dictato-2a-packaging-preferences-design.md`.

## Roadmap context (resequenced during brainstorming)

Model management was reprioritized above streaming. Order:

- **2b (this spec)** — multiple Whisper models (HuggingFace / local), a Dictation Models manager, sidebar Preferences with logo + name, recognizer cache, per-call language. One hotkey uses the selected default model.
- **2c** — Profiles: each hotkey → {model + language + insertion mode}.
- **2d** — Streaming modes (`2026-07-22-dictato-2b-streaming-design.md`; its per-mode-hotkey section is superseded by 2c profiles).
- **2e** — NVIDIA Parakeet backend (CoreML/FluidAudio) behind `SpeechRecognizer`.

## Goal

Let the user run more than one Whisper model — the built-in Hebrew ivrit-turbo plus any other Whisper `ggml` model (English, multilingual, …) downloaded from HuggingFace or added from a local file — pick which is the default, and switch quickly. Redesign Preferences into a real app-shell (left sidebar + logo + name) with a dedicated Dictation Models section.

Scope stays on the **whisper.cpp** backend. NVIDIA/Parakeet is a later backend phase; the `SpeechRecognizer` protocol already isolates it.

## Decisions (from brainstorming)

| Decision | Choice |
|---|---|
| Backend | whisper.cpp only this phase; multiple Whisper `ggml` models. NVIDIA later. |
| Model sources | Built-in presets, HuggingFace (repo id + file, or direct URL), local `.bin` file. |
| Language | Per **call** (`transcribe(samples:language:)`), not per model — a multilingual model serves many languages without reload. |
| Residency | `RecognizerCache` LRU, default capacity 2 (Hebrew + English resident); configurable. |
| Preferences | Sidebar app-shell (NavigationSplitView) with logo + "Dictato". |
| Default model | User-selectable; the single hotkey uses it (profiles arrive in 2c). |

## Data model

```swift
// DictatoCore — pure, Codable, testable
public enum ModelSource: Codable, Equatable {
    case builtin(url: URL)                 // curated preset
    case huggingFace(repo: String, file: String)
    case directURL(URL)
    case localFile(path: String)           // referenced in place, not downloaded
}

public struct ManagedModel: Codable, Equatable, Identifiable {
    public var id: String                  // stable slug, e.g. "ivrit-large-v3-turbo"
    public var displayName: String         // "ivrit-ai Large v3 Turbo (Hebrew)"
    public var source: ModelSource
    public var defaultLanguage: String     // "he", "en", "auto"
    public var minSizeBytes: Int           // for validation (0 = skip size check)

    // Presentation (Spokenly-style card). Optional so user-added models can omit them.
    public var summary: String?            // one-line description
    public var sizeBytesApprox: Int?       // shown as "1.6 GB" / "488 MB" before download
    public var accuracy: Int?              // 1…5 dots (nil = unknown, dots hidden)
    public var speed: Int?                 // 1…5 dots
    public var badge: String?              // e.g. "Best for Hebrew"
}
```

Card fields render only when present. `sizeBytesApprox` is display-only (installed size shown from disk once downloaded); `minSizeBytes` is the validation floor. `defaultLanguage` maps to a human label ("Hebrew", "English", "Multilingual" for `auto`). Every model shows a "Local" badge (all whisper.cpp models run on-device this phase).

public struct ModelCatalog: Codable, Equatable {
    public var models: [ManagedModel]
    public var defaultModelID: String
}
```

- `ModelSource.downloadURL` computed: HF → `https://huggingface.co/<repo>/resolve/main/<file>`; directURL → itself; builtin → its url; localFile → nil (already on disk).
- `ManagedModel.localFileName` = `"\(id).bin"`; installed path = Application Support/Dictato/models/`<id>.bin` (localFile uses its own path directly).

### Curated presets (seeded on first launch)

| id | name | source | lang | size | acc | speed | badge |
|---|---|---|---|---|---|---|---|
| `ivrit-large-v3-turbo` | ivrit-ai Large v3 Turbo | HF `ivrit-ai/whisper-large-v3-turbo-ggml` / `ggml-model.bin` | he | ~1.6 GB | 5 | 4 | Best for Hebrew |
| `whisper-large-v3-turbo` | Whisper Large v3 Turbo | HF `ggerganov/whisper.cpp` / `ggml-large-v3-turbo.bin` | auto | ~1.6 GB | 4 | 4 | Multilingual |
| `whisper-small-en` | Whisper Small (English) | HF `ggerganov/whisper.cpp` / `ggml-small.en.bin` | en | ~488 MB | 3 | 5 | Fast · English |

Each preset carries a one-line `summary`. Only models the user installs are downloaded; presets are catalog entries, not auto-downloads. Default = `ivrit-large-v3-turbo`. (Ratings are our editorial estimates; user-added models show only the facts we have — size after download, language as entered.)

### Migration

On first 2b launch: if the legacy file `ggml-ivrit-large-v3-turbo.bin` exists in the models dir, register `ivrit-large-v3-turbo` as installed pointing at it (rename to `ivrit-large-v3-turbo.bin` if needed) — no re-download. Seed the catalog with the presets and set it default.

## Components

```
DictatoCore
├── ModelSource / ManagedModel / ModelCatalog   NEW  Codable data model
├── ModelCatalogStore                            NEW  load/save catalog JSON, seed presets, migrate
├── ModelValidation (from ModelSpec)             reused: ggml magic + size check, generalized to a path
└── Settings                                      +recognizerCacheCapacity (default 2)

Dictato
├── ModelManager                                 generalized: download any ModelSource → path, progress, resume, validate
├── ModelInstaller                               NEW  orchestrates install/delete + catalog updates + progress state
├── RecognizerCache                              NEW  LRU of loaded WhisperCppRecognizer by modelId (cap from Settings)
├── SpeechRecognizer                             transcribe(samples:language:) — language moves to the call
├── WhisperCppRecognizer                         language per call; init(modelPath:)
├── DictationController                          resolves default model → cache → transcribe(language:)
└── Preferences/                                 app-shell rebuild (below)
```

### SpeechRecognizer protocol change

```swift
protocol SpeechRecognizer: AnyObject {
    var isLoaded: Bool { get }
    func load() async throws
    func transcribe(samples: [Float], language: String) async throws -> String
    func unload()
}
```

- `WhisperCppRecognizer` drops the init `language` param; passes `language` into `whisper_full` per call. `"auto"` → let whisper detect (`params.language = nil`).
- Streaming spec (2d) inherits this signature.

### RecognizerCache

```swift
final class RecognizerCache {
    init(capacity: Int)
    /// Returns a loaded recognizer for the model path, loading + evicting LRU as needed.
    func recognizer(id: String, modelPath: URL) async throws -> SpeechRecognizer
    func evictAll()
}
```

- LRU keyed by model id. On miss, construct `WhisperCppRecognizer(modelPath:)`, `load()`, insert; if over capacity, `unload()` + drop the least-recently-used. Capacity from `Settings.recognizerCacheCapacity`.
- Switching the default model or profile just requests a different id — resident models answer instantly; others load (~1 s) with the menu/overlay showing "Loading model…".

### ModelManager / ModelInstaller

- `ModelManager` generalizes v1's downloader: given a `ModelSource` + destination, download with progress + resume, validate ggml magic + size, atomic move into place. `localFile` skips download (validate in place).
- `ModelInstaller` (main-actor) tracks per-model install state (`notInstalled / downloading(fraction) / installed / failed`) for the UI, updates the catalog on success, handles delete (removes file, refuses to delete the last remaining installed model or the current default without reassignment).

### DictationController changes

- Resolve the current model = `ModelCatalogStore.default`; obtain recognizer via `RecognizerCache`; call `transcribe(samples:, language: model.defaultLanguage)`.
- On startup: ensure the default model is installed (download if missing, as today) then warm it into the cache. "Reload Model" re-warms the default.
- Changing the default in Preferences posts a notification; the controller warms the new default.

## Preferences app-shell

- Host a single `NSWindow` containing a SwiftUI `NavigationSplitView`.
- **Sidebar:** header = Dictato logo (DictatoLogo.png) + "Dictato" wordmark; list items: **General**, **Dictation Models**, **Speech**, **Debug**. (Profiles/Hotkeys section added in 2c; the existing Hotkeys tab content moves under a "Hotkeys" item now to keep parity.)
- **Detail pane** renders the selected section. Dark, padded, section headers — matching the app's look.

### Sidebar sections (2b)

- **General** — Auto-paste, Copy only, Keep out of clipboard history, Show overlay, Play sounds, Insertion mode (batch functional; live "coming soon"), Launch at login. (Same controls as 2a, re-hosted.)
- **Dictation Models** — the new manager, rendered as **Spokenly-style cards**:
  - Each card: name + optional badge ("Best for Hebrew"), one-line summary, then a metadata row — **Accuracy ●●●●○**, **Speed ●●●●●**, **size** (e.g. 1.6 GB), **language** (Hebrew / Multilingual / English), **Local**. Fields absent for user-added models are hidden.
  - Status/action on the card: Installed ✓ / Download / Downloading NN% (progress bar) / Failed + Retry; a "Default" radio; Delete; edit language.
  - **Add model:** preset picker (the curated list minus already-added), **HuggingFace** (repo id + file fields), **Direct URL**, **Local file…** (open panel → `.bin`). Adding asks for the model's language (`he`/`en`/`auto`/…).
  - Per-row actions: Download / Delete / Set default / edit language. Progress bar while downloading. Delete disabled for the last installed / current default (must reassign first).
- **Hotkeys** — the 2a recorder(s) (Dictate, Cancel) re-hosted. (Becomes Profiles in 2c.)
- **Speech** — sample rate (read-only), recognizer cache capacity stepper. (Language is per-model, edited in Dictation Models.)
- **Debug** — inference time, audio duration, verbose logging, Open Logs.

## Error handling

- HF/URL 404 or wrong file → install fails with a clear row error; catalog unchanged.
- Corrupt/short download → validation fails → file removed, row shows Failed + Retry.
- Local file not a ggml model (bad magic) → rejected with a message.
- Deleting the default or last model → blocked with guidance to set another default first.
- Cache load failure (bad model) → surfaced as an error; falls back to the previous resident model if any.
- Disk full mid-download → Failed + Retry; other models untouched.

## Testing

- Unit (no-Xcode runner): `ModelSource.downloadURL` for each case; `ManagedModel.localFileName`/installed path; `ModelCatalog` Codable round-trip; `ModelCatalogStore` seeding + migration (legacy file → installed) + default reassignment on delete; `Settings.recognizerCacheCapacity` default/persist.
- Manual: add a preset (Whisper English) → download progress → set default → dictate English; add via HF repo+file; add a local `.bin`; delete a model; switch default and confirm fast switch when cached; Preferences sidebar layout + logo.

## Out of scope (later phases)

Profiles + per-hotkey model (2c), streaming (2d), NVIDIA Parakeet backend (2e), per-model quantization download choices, automatic model recommendations, microphone-priority list, Dock/Status-bar visibility toggles.
