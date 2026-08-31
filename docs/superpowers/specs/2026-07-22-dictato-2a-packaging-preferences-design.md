# Dictato 2a — Packaging, Icon, Preferences, Overlay, Sharing (Design Spec)

Date: 2026-07-22
Status: Approved
Predecessor: `2026-07-21-dictato-design.md` (v1 shipped: batch dictation, menu bar, whisper.cpp + ivrit turbo).
Successor: 2b — Streaming dictation (separate spec).

## Goal

Turn the working v1 menu-bar utility into a real, shareable macOS app: Dock presence with a custom icon, a full Preferences window, a Spokenly-style dictation overlay, menu shortcut hints, and a `.dmg` friends can install. No streaming yet — insertion-mode settings are present and selectable but only Batch is wired (Overlay-live / In-app-live land in 2b).

## Decisions (resolved during brainstorming)

| Decision | Choice |
|---|---|
| Dock presence | Regular app (drop `LSUIElement`), activation policy `.regular`; also keeps menu bar. Dock/reopen click with no window → opens Preferences. |
| Icon | Generated placeholder (mic + Hebrew **א** motif), 1024px → full `.icns`. Reused as the overlay logo. |
| Preferences | Full SwiftUI `Settings` window: General / Hotkeys / Speech / Debug tabs. |
| Insertion modes | Three, all selectable in the picker now. Only **Batch** is functional in 2a, so 2a's default setting stays **Batch** (app must work). 2b implements the live modes and flips the default to **Overlay-live**. Selecting an unimplemented mode in 2a shows a "coming soon" note and falls back to Batch behavior. |
| Overlay | Spokenly-style: target app icon+name left, Dictato logo+name right, dot waveform bottom. |
| Sharing | Ad-hoc signed `.dmg` + documented Gatekeeper unlock (`xattr -dr com.apple.quarantine`). No paid Apple account. |
| Menu hints | Each action shows its binding as trailing text. |

## Components

### 1. Dock app + reopen

- Remove `LSUIElement` from Info.plist; add `CFBundleIconFile`.
- `AppDelegate.applicationDidFinishLaunching`: `NSApp.setActivationPolicy(.regular)`.
- `applicationShouldHandleReopen(_:hasVisibleWindows:)` and Dock-icon click → open Preferences window.
- Menu bar item stays (icon + menu unchanged from v1 aside from hints).

### 2. Icon generation

- `Tools/make-icon.swift` (run once, offline): draws a 1024×1024 icon — rounded-rect background, microphone glyph, Hebrew **א** accent — to PNG using Core Graphics.
- `Tools/make-iconset.sh`: PNG → `Dictato.iconset` (all required sizes via `sips`) → `iconutil -c icns` → `Resources/Dictato.icns`.
- `make icon` target runs both. Committed `Dictato.icns` so a normal build needs no regen.
- Same 1024 PNG downscaled to a small overlay logo asset used by the overlay view.

### 3. Preferences window

SwiftUI `Settings` scene hosted from the app. Backed by the existing `Settings` (UserDefaults) type in `DictatoCore`, extended with new keys. Tabs:

- **General** — Launch at Login (SMAppService), Auto-paste, Show overlay, Play sounds, **Insertion mode** picker (Batch / Overlay-live / In-app-live; live modes tagged "coming soon" in 2a, fall back to Batch), Copy-only.
- **Hotkeys** — a `HotkeyRecorderView` per action: *Dictate* (start/stop toggle), *Cancel*. (Live-dictate action added in 2b.) Supports two binding kinds: a **modifier-tap preset** dropdown (Right-⌘ double-tap / Left-⌘ double-tap / Right-⌥ double-tap) and a **standard key-combo** captured by the recorder. Default Dictate = Right-⌘ modifier-tap (double-tap start / single-tap stop), Cancel = Esc.
- **Speech** — Model (turbo, shown; more in 2b), Language (default `he`), Sample rate (16 kHz, read-only for now).
- **Debug** — Show inference time, Show audio duration, Verbose logging, button "Open Logs".

### 4. Hotkey binding model (generalization)

Move binding definition into `DictatoCore` so it is unit-testable:

```swift
public enum HotkeyBinding: Equatable, Codable {
    case modifierTap(ModifierKey, count: Int)   // e.g. .rightCommand, 2
    case keyCombo(keyCode: UInt16, modifiers: UInt)
}

public enum ModifierKey: String, Codable { case rightCommand, leftCommand, rightOption, rightControl }
```

- `HotkeyBinding` has a `displayString` (e.g. "⌘⌘ (right)", "⌥⌥ (right)", "⌃⌥␣") used by both the menu hints and the recorder UI.
- `Settings` stores bindings as JSON strings for Dictate and Cancel.
- The existing `RightCmdTapDetector` is generalized to `ModifierTapDetector` (parameterized by `ModifierKey` + count) with identical tap semantics; `HotkeyMonitor` maps NSEvents through the active binding. Standard key-combo bindings are matched on `.keyDown`.
- 2a wires only what v1 already did (right-⌘ tap + Esc) through the new model; alternative bindings become selectable but the mechanism is the same.

### 5. Overlay redesign (Spokenly-style)

Layout (dark rounded card, ~300×64; red border while recording):

```
[app icon] AppName            ┆ dots waveform ┆            [Dictato logo] Dictato
```

- **Target app** captured at record start: `NSWorkspace.shared.frontmostApplication` → `localizedName`, `icon`. Passed into `OverlayModel` as `targetAppName: String?`, `targetAppIcon: NSImage?`. Because the overlay is a non-activating panel, the frontmost app does not change when it appears; still, capture at start to be safe.
- **Dictato logo + name** on the right from the generated icon asset.
- **Waveform** rendered as a row of dots that rise with level (matches screenshot), driven by existing `OverlayModel.levels`.
- Processing / success / error states keep the same card chrome.

### 6. Menu shortcut hints

- `MenuBarController` sets each relevant `NSMenuItem`'s trailing hint. Standard `keyEquivalent` used where possible (Quit ⌘Q). Modifier-tap bindings can't be real key-equivalents, so shown as right-aligned attributed gray text via the item's view or an appended tab + string in the title.
- Start/Stop Recording shows the Dictate binding's `displayString`; Cancel (contextual) shows Esc.

### 7. Sharing / distribution

- `make dmg`: builds the app, stages it + an "Applications" symlink into a folder, `hdiutil create` → `build/Dictato.dmg`. Ad-hoc signed.
- README "Install (shared build)" section: drag to Applications, then first-run unlock — `xattr -dr com.apple.quarantine /Applications/Dictato.app` **or** right-click → Open once. Explains why (no paid Developer ID). Notes the ~1.6 GB model download on first launch.

## Architecture delta

```
DictatoCore (+ HotkeyBinding, ModifierKey, ModifierTapDetector, Settings keys)
Dictato
├── AppDelegate            (+ regular policy, reopen→Preferences)
├── Preferences/           NEW  SettingsView + tab views + HotkeyRecorderView
├── MenuBarController      (+ shortcut hints)
├── HotkeyMonitor          (+ binding-driven dispatch)
├── Overlay/               (redesigned view + target-app fields)
└── (unchanged v1 modules)
Tools/                     NEW  make-icon.swift, make-iconset.sh
Resources/                 (+ Dictato.icns, overlay logo)
```

## Error handling

- Icon/asset missing at runtime → fall back to SF Symbol (no crash).
- `frontmostApplication` nil → overlay shows Dictato side only.
- Invalid/legacy binding JSON in defaults → fall back to default binding + log.
- `make dmg` on a machine without the model → app still ships; model downloads on the recipient's first launch.

## Testing

- Unit (via `swiftc` runner, no Xcode): `HotkeyBinding` round-trip Codable + `displayString`; `ModifierTapDetector` tap semantics (port of existing RightCmd tests, parameterized); `Settings` new keys defaults + persistence.
- Build/artifact: `make icon` produces `Dictato.icns`; `make app` bundles icon + regular policy; `make dmg` produces a mountable image.
- Manual: Dock icon appears with artwork; clicking Dock/reopen opens Preferences; Preferences tabs persist; overlay shows correct frontmost app icon+name while dictating in TextEdit vs Safari; menu hints render; friend-install flow on a second Mac / fresh user.

## Out of scope (2b and later)

Streaming transcription, dual-model, Overlay-live / In-app-live wiring, per-mode hotkeys, VAD, sounds playback engine (setting present, playback deferred), Developer ID notarization.
