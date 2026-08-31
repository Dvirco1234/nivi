# Dictato 2c — Dictation Profiles

Date: 2026-07-22
Status: Approved (design)

## Goal

Replace the single-hotkey / single-default-model dictation flow with **profiles**. A
profile binds one hotkey to a `{model, language, insertion mode}` combination. The user
can hold several profiles at once (e.g. right-⌘ double-tap → Hebrew turbo; right-⌥
double-tap → English small) and one profile is marked **primary**.

Non-goals: streaming insertion (2d), new model backends (2e). Insertion mode is stored
per profile but only `batch` is selectable in this milestone.

## Product decisions

- **Profiles replace the single default model.** The "default model" concept collapses
  into "primary profile". The primary profile's model is the warmed model; its language
  drives the menu-bar glyph and the overlay logo when idle.
- **Insertion mode is stored per profile now** (front-loads the schema). UI only lets you
  pick `batch`; `overlayLive` / `inAppLive` are shown greyed "coming soon". 2d un-greys
  them with no schema change.
- **Mid-recording, other profiles' hotkeys are ignored.** While recording with profile A,
  only A's hotkey (single-tap → stop) and the global Cancel (Esc) respond. Pressing
  another profile's hotkey does nothing — no accidental model swap, no discarded audio.

## 1. Data model (DictatoCore)

New type:

```swift
public struct DictationProfile: Codable, Equatable, Identifiable {
    public var id: String            // stable slug
    public var name: String          // "Hebrew", "English notes"
    public var modelID: String       // references ManagedModel.id
    public var language: String      // override: "he" / "en" / "auto"
    public var mode: InsertionMode   // batch now; streaming slots ready for 2d
    public var hotkey: HotkeyBinding
}
```

Container:

```swift
public struct ProfileSet: Codable, Equatable {
    public var profiles: [DictationProfile]
    public var primaryID: String

    public func profile(id: String) -> DictationProfile?
    public var primary: DictationProfile? { profile(id: primaryID) }
}
```

Persisted to UserDefaults as JSON (own key, e.g. `profiles`), sitting alongside the
existing `ModelCatalog`. `ProfileSet` is pure/testable — no UIKit/AppKit — so it is
covered by `Tools/run-core-tests.sh` (migration, uniqueness validation, primary
fallback).

**Relationship to `ModelCatalog`.** The catalog still owns the list of installable models
and their metadata. `catalog.defaultModelID` is repurposed to *track the primary
profile's model* (kept in sync when primary changes) so the Models screen keeps a
sensible download target; runtime model/language selection comes from the active profile,
not the catalog.

**Migration (first launch with empty `ProfileSet`).** Seed exactly one profile:

- `id`: fresh slug
- `name`: derived from the model language (e.g. "Hebrew")
- `modelID`: `catalog.defaultModel?.id`
- `language`: that model's `defaultLanguage`
- `mode`: `.batch`
- `hotkey`: existing `settings.dictateBinding`

Mark it primary. Result: no re-download, identical behavior for existing users until they
add a second profile.

**Validation** (`ProfileSet` methods, pure):

- Every profile hotkey is unique across the set (exact `HotkeyBinding` equality).
- No profile hotkey equals the cancel binding.
- `primaryID` always resolves to an existing profile; deleting the primary promotes
  another; the last profile cannot be deleted.

## 2. Hotkey routing + runtime

Replace the single-detector `HotkeyMonitor` with **`HotkeyRouter`**:

- Owns the global + local `flagsChanged` / `keyDown` monitors (installed once).
- Builds, per profile:
  - `.modifierTap` → a dedicated `ModifierTapDetector` keyed by modifier keyCode.
  - `.keyCombo` → a direct keyDown match entry.
- `flagsChanged`: routed to the detector whose keyCode matches the event; every other
  detector receives `otherKeyDown` (so a combo aborts a pending tap, as today).
- A detector's `onActivate` fires `router.onActivate(profileID)`.
- **Cancel (Esc)** stays global via `keyDown`, enabled only while recording
  (`cancelEnabled`).
- **Record start for profile P:** set P's detector to `.singleTap` (single-tap → stop);
  mute all other profiles' activations (router drops non-P activations while recording).
  Restore all detector modes on stop / cancel.
- **Rebuild** the router (stop + rebuild + start) whenever the `ProfileSet` changes
  (add/edit/delete/reorder/primary) — same pattern as today's wake re-arm. No app
  restart required for profile edits (hotkey *recording* still notes "applies after
  reopen" only if we keep that limitation; target is live rebuild).

Constraint: two profiles sharing an identical modifier-tap binding is rejected at the UI
layer (see §3), so the router never sees a keyCode collision.

`DictationController` changes:

- Track `activeProfileID` — set at record start to the profile that fired.
- `warmDefaultModel()` → `warmPrimaryModel()`: warms `profileSet.primary`'s model.
- Transcribe uses the **active profile's** `modelID` + `language` (not
  `model.defaultLanguage`).
- Recognizer cache is already keyed by modelID; non-primary models load lazily on first
  use, LRU + idle-unload unchanged.
- Menu-bar glyph / overlay language: **active profile while recording, primary otherwise**
  (extends the existing `setPrimaryLanguage` / `overlayModel.languageCode` wiring).
- `.dictatoDefaultModelChanged` notification generalizes to a
  `.dictatoProfilesChanged` notification that triggers router rebuild + re-warm.

## 3. UI — Preferences

New sidebar section **Profiles** (takes over the dictate half of the current Hotkeys
section):

- **Profile cards** (reuse the ModelsSection card visual language): name, model display
  name, language label, mode label, hotkey chip. Actions: **Set primary** (radio /
  checkmark), **Edit**, **Delete** (disabled for the last profile; deleting primary
  promotes the next).
- **Add / Edit sheet** (mirrors `AddModelSheet` structure):
  - Name (text)
  - Model picker — installed models only (guidance text if none installed → link to
    Models screen)
  - Language picker — Hebrew / English / Multilingual, defaulting to the model's
    `defaultLanguage`
  - Mode picker — only `.batch` enabled; streaming entries greyed "coming soon"
  - Hotkey recorder (`HotkeyRecorderView`) with **live uniqueness validation** against the
    other profiles and the cancel binding; Save disabled while invalid.
- **Cancel hotkey** row remains (single global binding) — either kept in a slim "Hotkeys"
  section or as a footer row under Profiles. Decision: keep a **Hotkeys** section holding
  only Cancel, to avoid mixing per-profile and global bindings on one screen.

## Testing

- Core (`run-core-tests.sh`): `ProfileSet` migration seeds one primary profile from legacy
  settings; uniqueness validation rejects duplicate hotkeys and cancel collision; deleting
  primary promotes another; last-profile delete blocked; JSON round-trip.
- Manual: two profiles with distinct hotkeys transcribe with their own model+language;
  mid-record other hotkey ignored; primary change flips menu-bar glyph + overlay logo;
  router rebuilds live on profile edit; idle-unload + AirPods behavior unaffected.

## Out of scope / follow-ups

- Live streaming insertion (2d) — un-greys the mode picker, adds live transcription path.
- NVIDIA Parakeet backend (2e).
- Per-profile advanced options (custom prompts, temperature) — not requested.
