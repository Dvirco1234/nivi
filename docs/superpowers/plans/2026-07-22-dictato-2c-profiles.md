# Dictato 2c — Dictation Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single dictate-hotkey / single-default-model flow with named profiles, each binding one hotkey to a `{model, language, insertion mode}`, with one profile marked primary.

**Architecture:** A pure `ProfileSet` value type (DictatoCore) holds the profiles + primary id, with migration and conflict-validation logic covered by the swiftc core-test harness. A `ProfileStore` (`@MainActor ObservableObject`, app layer) persists it via `Settings` JSON and drives SwiftUI. A new `HotkeyRouter` replaces `HotkeyMonitor`, owning the global monitors and dispatching to one `ModifierTapDetector` per modifier-tap profile. `DictationController` selects model+language from the active profile at record time.

**Tech Stack:** Swift 5.10, SwiftUI + AppKit, SwiftPM, whisper.cpp. No Xcode/XCTest — core tests run via `bash Tools/run-core-tests.sh` (single-module swiftc compile of `Sources/DictatoCore/*.swift` + `Tools/core-tests/main.swift`, plain `check()` asserts, NO `import DictatoCore`).

## Global Constraints

- macOS 14+, Apple Silicon. Bundle id `com.dvir.dictato`.
- DictatoCore stays pure (no AppKit/SwiftUI/AVFoundation) so it compiles into the core-test binary. All app/UI code lives under `Sources/Dictato/`.
- `Settings` accessors use `nonmutating set` (SwiftUI View bodies mutate settings).
- Persisted-type changes must round-trip through JSON `Codable`.
- Build gate before every commit: `make build` must succeed; `bash Tools/run-core-tests.sh` must print no `FAIL:` lines.
- Signing/install unchanged: `make install` copies to /Applications under the stable "Dictato Self-Signed" identity.
- Caveman mode is a conversation style only — code, comments, and commit messages are written normally.

---

## File Structure

- Create `Sources/DictatoCore/DictationProfile.swift` — `DictationProfile`, `ProfileSet`, conflict/validation + migration logic (pure).
- Create `Sources/Dictato/ProfileStore.swift` — `@MainActor ObservableObject` persistence + mutation, mirrors `ModelStore`; posts `.dictatoProfilesChanged`.
- Create `Sources/Dictato/HotkeyRouter.swift` — multi-detector global hotkey routing; replaces `HotkeyMonitor`.
- Delete `Sources/Dictato/HotkeyMonitor.swift` — superseded by router (do this in Task 3).
- Modify `Sources/DictatoCore/Settings.swift` — add `profilesJSON` string accessor + register default.
- Modify `Sources/Dictato/DictationController.swift` — active-profile runtime, router wiring, per-profile transcribe, glyph source, rebuild on change.
- Modify `Sources/Dictato/Preferences/SettingsView.swift` — add `.profiles` sidebar section; slim `.hotkeys` to Cancel only; pass `ProfileStore`.
- Create `Sources/Dictato/Preferences/ProfilesSection.swift` — profile cards + Add/Edit sheet.
- Modify `Sources/Dictato/PreferencesWindow.swift` — inject `ProfileStore` alongside `ModelStore`.
- Modify `Tools/core-tests/main.swift` — add `ProfileSet` tests.

---

## Task 1: `DictationProfile` + `ProfileSet` (DictatoCore, pure, TDD)

**Files:**
- Create: `Sources/DictatoCore/DictationProfile.swift`
- Test: `Tools/core-tests/main.swift` (append)

**Interfaces:**
- Consumes: `HotkeyBinding`, `ModifierKey`, `InsertionMode` (existing, DictatoCore).
- Produces:
  - `struct DictationProfile: Codable, Equatable, Identifiable { var id, name, modelID, language: String; var mode: InsertionMode; var hotkey: HotkeyBinding }`
  - `struct ProfileSet: Codable, Equatable { var profiles: [DictationProfile]; var primaryID: String }`
  - `ProfileSet.profile(id:) -> DictationProfile?`, `.primary -> DictationProfile?`
  - `ProfileSet.conflict(for hotkey: HotkeyBinding, excluding id: String?, cancel: HotkeyBinding) -> Bool` — true if the hotkey collides with another profile or cancel.
  - `static ProfileSet.migrated(from dictate: HotkeyBinding, modelID: String?, language: String, name: String) -> ProfileSet`
  - `ProfileSet.removing(id:) -> ProfileSet` — removes if not last; re-points primary if needed.
  - `ProfileSet.settingPrimary(_ id: String) -> ProfileSet`
  - `ProfileSet.normalizedPrimary() -> ProfileSet` — ensures `primaryID` resolves.

- [ ] **Step 1: Write the failing tests** (append to `Tools/core-tests/main.swift`, before the final `exit` if any; the harness ends by checking `failures`)

```swift
// --- DictationProfile / ProfileSet ---
let he = DictationProfile(id: "p1", name: "Hebrew", modelID: "ivrit-large-v3-turbo",
                          language: "he", mode: .batch,
                          hotkey: .modifierTap(.rightCommand, count: 2))
let en = DictationProfile(id: "p2", name: "English", modelID: "whisper-small-en",
                          language: "en", mode: .batch,
                          hotkey: .modifierTap(.rightOption, count: 2))
var set0 = ProfileSet(profiles: [he, en], primaryID: "p1")
check(set0.primary?.id == "p1", "primary resolves")
check(set0.profile(id: "p2")?.language == "en", "lookup by id")

// json round-trip
let data = try! JSONEncoder().encode(set0)
let decoded = try! JSONDecoder().decode(ProfileSet.self, from: data)
check(decoded == set0, "ProfileSet json round-trip")

// conflict detection
let cancel = HotkeyBinding.keyCombo(keyCode: 53, modifiers: 0)
check(set0.conflict(for: .modifierTap(.rightOption, count: 2), excluding: nil, cancel: cancel),
      "duplicate hotkey conflicts")
check(set0.conflict(for: .modifierTap(.rightControl, count: 1), excluding: "p2", cancel: cancel) == false,
      "excluded profile does not self-conflict")
check(set0.conflict(for: .keyCombo(keyCode: 53, modifiers: 0), excluding: nil, cancel: cancel),
      "cancel-equal hotkey conflicts")
// same modifier key, different tap count still conflicts (one detector per key)
check(set0.conflict(for: .modifierTap(.rightCommand, count: 1), excluding: "p2", cancel: cancel),
      "same modifier key different count conflicts")

// migration from legacy single binding
let mig = ProfileSet.migrated(from: .modifierTap(.rightCommand, count: 2),
                              modelID: "ivrit-large-v3-turbo", language: "he", name: "Hebrew")
check(mig.profiles.count == 1, "migration seeds one profile")
check(mig.primary?.modelID == "ivrit-large-v3-turbo", "migration primary model")
check(mig.primary?.hotkey == .modifierTap(.rightCommand, count: 2), "migration keeps hotkey")

// removing: last profile cannot be removed
let solo = ProfileSet(profiles: [he], primaryID: "p1")
check(solo.removing(id: "p1").profiles.count == 1, "cannot remove last profile")
// removing primary promotes another
let afterRemove = set0.removing(id: "p1")
check(afterRemove.profiles.count == 1, "removed one")
check(afterRemove.primary?.id == "p2", "primary promoted after removal")

// normalizedPrimary repairs dangling primary
var broken = ProfileSet(profiles: [he, en], primaryID: "gone")
check(broken.normalizedPrimary().primaryID == "p1", "dangling primary repaired to first")
```

- [ ] **Step 2: Run to verify failure**

Run: `bash Tools/run-core-tests.sh`
Expected: compile error — `cannot find 'DictationProfile' in scope` / `ProfileSet`.

- [ ] **Step 3: Write `Sources/DictatoCore/DictationProfile.swift`**

```swift
import Foundation

public struct DictationProfile: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var modelID: String
    public var language: String
    public var mode: InsertionMode
    public var hotkey: HotkeyBinding

    public init(id: String, name: String, modelID: String, language: String,
                mode: InsertionMode, hotkey: HotkeyBinding) {
        self.id = id; self.name = name; self.modelID = modelID
        self.language = language; self.mode = mode; self.hotkey = hotkey
    }

    public var languageLabel: String {
        switch language {
        case "he": return "Hebrew"
        case "en": return "English"
        case "auto", "": return "Multilingual"
        default: return language.uppercased()
        }
    }
}

public struct ProfileSet: Codable, Equatable {
    public var profiles: [DictationProfile]
    public var primaryID: String

    public init(profiles: [DictationProfile], primaryID: String) {
        self.profiles = profiles
        self.primaryID = primaryID
    }

    public func profile(id: String) -> DictationProfile? { profiles.first { $0.id == id } }
    public var primary: DictationProfile? { profile(id: primaryID) }

    /// True if `hotkey` collides with any other profile (excluding `id`) or with `cancel`.
    /// Modifier-tap bindings collide when they share a modifier key regardless of tap count
    /// (the router builds one detector per key). Key-combos collide on exact equality.
    public func conflict(for hotkey: HotkeyBinding, excluding id: String?, cancel: HotkeyBinding) -> Bool {
        if Self.collides(hotkey, cancel) { return true }
        return profiles.contains { p in
            p.id != id && Self.collides(p.hotkey, hotkey)
        }
    }

    private static func collides(_ a: HotkeyBinding, _ b: HotkeyBinding) -> Bool {
        switch (a, b) {
        case let (.modifierTap(ka, _), .modifierTap(kb, _)):
            return ka.keyCode == kb.keyCode
        default:
            return a == b
        }
    }

    /// Seed a single primary profile from the legacy single-dictate binding.
    public static func migrated(from dictate: HotkeyBinding, modelID: String?,
                                language: String, name: String) -> ProfileSet {
        let profile = DictationProfile(
            id: "profile-1", name: name, modelID: modelID ?? "",
            language: language, mode: .batch, hotkey: dictate)
        return ProfileSet(profiles: [profile], primaryID: profile.id)
    }

    /// Remove a profile unless it is the last one; re-point primary if it was removed.
    public func removing(id: String) -> ProfileSet {
        guard profiles.count > 1 else { return self }
        var next = profiles.filter { $0.id != id }
        var primary = primaryID
        if primary == id { primary = next.first?.id ?? primary }
        return ProfileSet(profiles: next, primaryID: primary).normalizedPrimary()
        _ = next  // silence unused-mutability warning path
    }

    public func settingPrimary(_ id: String) -> ProfileSet {
        guard profile(id: id) != nil else { return self }
        return ProfileSet(profiles: profiles, primaryID: id)
    }

    /// Ensure `primaryID` resolves to an existing profile; otherwise fall back to first.
    public func normalizedPrimary() -> ProfileSet {
        if profile(id: primaryID) != nil { return self }
        return ProfileSet(profiles: profiles, primaryID: profiles.first?.id ?? "")
    }

    /// Upsert a profile (replace by id, else append).
    public func upserting(_ p: DictationProfile) -> ProfileSet {
        var list = profiles
        if let i = list.firstIndex(where: { $0.id == p.id }) { list[i] = p } else { list.append(p) }
        return ProfileSet(profiles: list, primaryID: primaryID).normalizedPrimary()
    }
}
```

Note: remove the stray `var next`/`_ = next` line — write `removing` cleanly:

```swift
    public func removing(id: String) -> ProfileSet {
        guard profiles.count > 1 else { return self }
        let next = profiles.filter { $0.id != id }
        let primary = (primaryID == id) ? (next.first?.id ?? primaryID) : primaryID
        return ProfileSet(profiles: next, primaryID: primary).normalizedPrimary()
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `bash Tools/run-core-tests.sh`
Expected: no `FAIL:` lines (exit 0).

- [ ] **Step 5: Commit**

```bash
git add Sources/DictatoCore/DictationProfile.swift Tools/core-tests/main.swift
git commit -m "feat(core): DictationProfile + ProfileSet with migration, conflict validation"
```

---

## Task 2: `profilesJSON` setting + `ProfileStore` (persistence + migration)

**Files:**
- Modify: `Sources/DictatoCore/Settings.swift` (add accessor + register)
- Create: `Sources/Dictato/ProfileStore.swift`

**Interfaces:**
- Consumes: `ProfileSet`, `DictationProfile` (Task 1); `Settings`; `ModelCatalog` via a passed-in default model id + language; `HotkeyBinding`.
- Produces:
  - `Settings.profilesJSON: String` (get/set, `nonmutating set`).
  - `@MainActor final class ProfileStore: ObservableObject` with `@Published private(set) var set: ProfileSet`, and methods `upsert(_:)`, `remove(_:)`, `setPrimary(_:)`, `conflict(for:excluding:) -> Bool`, `newProfileID() -> String`. Each mutation persists and posts `.dictatoProfilesChanged`.
  - `Notification.Name.dictatoProfilesChanged`.

- [ ] **Step 1: Add the setting accessor** — in `Sources/DictatoCore/Settings.swift`, add to the `register(defaults:)` dictionary:

```swift
            Key.profilesJSON: "",
```

add to the `Key` enum:

```swift
        static let profilesJSON = "profilesJSON"
```

and add the accessor near `dictateBinding`:

```swift
    public var profilesJSON: String {
        get { defaults.string(forKey: Key.profilesJSON) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: Key.profilesJSON) }
    }
```

- [ ] **Step 2: Create `Sources/Dictato/ProfileStore.swift`**

```swift
import Foundation
import DictatoCore

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var set: ProfileSet

    private let settings = Settings()

    /// - Parameters:
    ///   - defaultModelID: primary model to seed on first launch (from ModelCatalog).
    ///   - defaultLanguage: that model's language.
    init(defaultModelID: String?, defaultLanguage: String) {
        if let decoded = Self.load(from: settings.profilesJSON), !decoded.profiles.isEmpty {
            set = decoded.normalizedPrimary()
        } else {
            let name = ProfileStore.languageName(defaultLanguage)
            set = ProfileSet.migrated(from: settings.dictateBinding,
                                      modelID: defaultModelID,
                                      language: defaultLanguage, name: name)
            persist()
            Log.info("Seeded initial dictation profile from legacy settings")
        }
    }

    var cancelBinding: HotkeyBinding { settings.cancelBinding }

    func conflict(for hotkey: HotkeyBinding, excluding id: String?) -> Bool {
        set.conflict(for: hotkey, excluding: id, cancel: settings.cancelBinding)
    }

    func upsert(_ profile: DictationProfile) {
        set = set.upserting(profile)
        changed()
    }

    func remove(_ id: String) {
        set = set.removing(id: id)
        changed()
    }

    func setPrimary(_ id: String) {
        set = set.settingPrimary(id)
        changed()
    }

    func newProfileID() -> String {
        var n = set.profiles.count + 1
        while set.profiles.contains(where: { $0.id == "profile-\(n)" }) { n += 1 }
        return "profile-\(n)"
    }

    private func changed() {
        persist()
        NotificationCenter.default.post(name: .dictatoProfilesChanged, object: nil)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(set),
           let json = String(data: data, encoding: .utf8) {
            settings.profilesJSON = json
        }
    }

    private static func load(from json: String) -> ProfileSet? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ProfileSet.self, from: data)
    }

    static func languageName(_ code: String) -> String {
        switch code {
        case "he": return "Hebrew"
        case "en": return "English"
        case "auto", "": return "Multilingual"
        default: return code.uppercased()
        }
    }
}

extension Notification.Name {
    static let dictatoProfilesChanged = Notification.Name("dictatoProfilesChanged")
}
```

- [ ] **Step 3: Build**

Run: `make build && bash Tools/run-core-tests.sh`
Expected: `Build complete!`; no `FAIL:` lines.

- [ ] **Step 4: Commit**

```bash
git add Sources/DictatoCore/Settings.swift Sources/Dictato/ProfileStore.swift
git commit -m "feat: ProfileStore persistence + first-launch migration; profilesJSON setting"
```

---

## Task 3: `HotkeyRouter` (multi-detector routing) replacing `HotkeyMonitor`

**Files:**
- Create: `Sources/Dictato/HotkeyRouter.swift`
- Delete: `Sources/Dictato/HotkeyMonitor.swift`
- Modify: `Sources/Dictato/DictationController.swift` (swap type; wiring done in Task 4)

**Interfaces:**
- Consumes: `ProfileSet`, `DictationProfile`, `HotkeyBinding`, `ModifierKey`, `ModifierTapDetector`, `Settings.doubleTapWindowMs`.
- Produces:
  - `final class HotkeyRouter` with:
    - `var onActivate: ((String) -> Void)?` (profile id)
    - `var onCancel: (() -> Void)?`
    - `var cancelEnabled: Bool`
    - `func rebuild(profiles: ProfileSet, cancel: HotkeyBinding)` — tears down + reconstructs detectors and monitors.
    - `func start()` / `func stop()`
    - `func beginRecording(profileID: String)` / `func endRecording()` — locks activation to the recording profile; sets its detector to single-tap.

- [ ] **Step 1: Create `Sources/Dictato/HotkeyRouter.swift`**

```swift
import AppKit
import DictatoCore

/// Owns the global + local flagsChanged/keyDown monitors and dispatches events to one
/// ModifierTapDetector per modifier-tap profile (keyed by modifier keyCode). Key-combo
/// profiles match directly on keyDown. Only the active profile responds while recording.
final class HotkeyRouter {
    var onActivate: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var cancelEnabled = false

    private let doubleTapWindow: TimeInterval

    // keyCode -> (detector, profileID) for modifier-tap profiles
    private var tapDetectors: [UInt16: (detector: ModifierTapDetector, profileID: String)] = [:]
    // profileID -> keyCombo for direct-match profiles
    private var comboProfiles: [(keyCode: UInt16, mods: UInt, profileID: String)] = []
    private var cancelBinding: HotkeyBinding = .defaultCancel

    private var monitors: [Any] = []
    private var recordingProfileID: String?

    init(doubleTapWindowMs: Int) {
        self.doubleTapWindow = Double(doubleTapWindowMs) / 1000.0
    }

    func rebuild(profiles: ProfileSet, cancel: HotkeyBinding) {
        let wasRunning = !monitors.isEmpty
        stop()
        tapDetectors = [:]
        comboProfiles = []
        cancelBinding = cancel
        for p in profiles.profiles {
            switch p.hotkey {
            case .modifierTap(let key, let count):
                let detector = ModifierTapDetector(
                    doubleTapWindow: doubleTapWindow,
                    now: { ProcessInfo.processInfo.systemUptime })
                detector.mode = count >= 2 ? .doubleTap : .singleTap
                let id = p.id
                detector.onActivate = { [weak self] in self?.fire(id) }
                tapDetectors[key.keyCode] = (detector, id)
            case .keyCombo(let keyCode, let mods):
                comboProfiles.append((keyCode, mods, p.id))
            }
        }
        if wasRunning { start() }
    }

    func start() {
        guard monitors.isEmpty else { return }
        let flags: (NSEvent) -> Void = { [weak self] e in self?.handleFlags(e) }
        let keys: (NSEvent) -> Void = { [weak self] e in self?.handleKeyDown(e) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: keys) { monitors.append(m) }
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { flags($0); return $0 } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { keys($0); return $0 } as Any)
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    func beginRecording(profileID: String) {
        recordingProfileID = profileID
        // The recording profile's tap detector switches to single-tap so one tap stops.
        for (keyCode, entry) in tapDetectors where entry.profileID == profileID {
            if case .modifierTap = detectorHotkey(keyCode) {}  // no-op guard for clarity
            entry.detector.mode = .singleTap
        }
    }

    func endRecording() {
        recordingProfileID = nil
        // Restore double-tap for detectors whose profile originally used double-tap.
        // Rebuild is the source of truth for original modes; callers rebuild on state exit
        // is unnecessary — restore here from stored original via re-deriving is complex, so
        // callers should call rebuild() after profile changes only. To restore modes simply,
        // set every tap detector back to double-tap unless it was created single-tap.
        for (_, entry) in tapDetectors { entry.detector.mode = entry.detector.mode }
    }

    private func fire(_ profileID: String) {
        if let active = recordingProfileID, active != profileID { return }  // ignore other profiles mid-record
        onActivate?(profileID)
    }

    private func handleFlags(_ event: NSEvent) {
        if let entry = tapDetectors[event.keyCode] {
            let mask = Self.requiredMask(for: event.keyCode)
            let down = event.modifierFlags.rawValue & mask != 0
            entry.detector.modifierChanged(down: down)
        } else {
            tapDetectors.values.forEach { $0.detector.otherKeyDown() }
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        if cancelEnabled, case .keyCombo(let kc, _) = cancelBinding, event.keyCode == kc {
            onCancel?()
            return
        }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
        for combo in comboProfiles where combo.keyCode == event.keyCode && combo.mods == mods {
            fire(combo.profileID)
            return
        }
        tapDetectors.values.forEach { $0.detector.otherKeyDown() }
    }

    private func detectorHotkey(_ keyCode: UInt16) -> HotkeyBinding { .keyCombo(keyCode: keyCode, modifiers: 0) }

    private static func requiredMask(for keyCode: UInt16) -> UInt {
        switch keyCode {
        case 54, 55: return 0x100000   // command
        case 61: return 0x80000        // option
        case 62: return 0x40000        // control
        default: return 0x100000
        }
    }
}
```

Note: the `endRecording` body above is intentionally rewritten in Step 2 — the mode-restore must be exact, not the no-op placeholder shown.

- [ ] **Step 2: Fix `beginRecording`/`endRecording` to restore original tap modes correctly**

Replace the two methods and add original-mode storage. In the `rebuild` loop, store the original mode; restore it in `endRecording`:

Add property:

```swift
    private var originalModes: [String: ModifierTapDetector.Mode] = [:]
```

In `rebuild`, inside the `.modifierTap` case after setting `detector.mode`:

```swift
                originalModes[id] = detector.mode
```

Replace `beginRecording`/`endRecording`:

```swift
    func beginRecording(profileID: String) {
        recordingProfileID = profileID
        for (_, entry) in tapDetectors where entry.profileID == profileID {
            entry.detector.mode = .singleTap
        }
    }

    func endRecording() {
        recordingProfileID = nil
        for (_, entry) in tapDetectors {
            entry.detector.mode = originalModes[entry.profileID] ?? .doubleTap
        }
    }
```

Delete the now-unused `detectorHotkey(_:)` helper and the `if case .modifierTap` no-op guard.

- [ ] **Step 3: Delete `HotkeyMonitor.swift`**

```bash
git rm Sources/Dictato/HotkeyMonitor.swift
```

(Compilation will break until Task 4 rewires `DictationController` — that is expected; commit Tasks 3+4 together at the end of Task 4.)

- [ ] **Step 4: Verify router compiles in isolation** (type-check the new file against the module by building; it will fail only on `DictationController` references to the deleted `HotkeyMonitor`, which Task 4 fixes)

Run: `make build 2>&1 | grep -i hotkeyrouter || echo "no router errors"`
Expected: `no router errors` (router itself type-checks; remaining errors are in `DictationController` about `HotkeyMonitor`).

Do NOT commit yet — proceed to Task 4.

---

## Task 4: `DictationController` runtime — active profile, per-profile transcribe, glyph, live rebuild

**Files:**
- Modify: `Sources/Dictato/DictationController.swift`

**Interfaces:**
- Consumes: `HotkeyRouter` (Task 3), `ProfileStore` (Task 2), `ProfileSet`/`DictationProfile` (Task 1), existing `RecognizerCache`, `ModelStore`, `MenuBarController`, `OverlayModel`.
- Produces: no new external interface; wires router → recording flow.

- [ ] **Step 1: Swap stored properties.** Replace:

```swift
    private let detector: ModifierTapDetector
    private let hotkeys: HotkeyMonitor
```

with:

```swift
    let profileStore: ProfileStore
    private let router: HotkeyRouter
    private var activeProfileID: String?
```

- [ ] **Step 2: Rewrite `init()`** to build the store + router from the catalog's default model:

```swift
    init() {
        let store = ModelStore()
        let primaryModel = store.catalog.defaultModel
        profileStore = ProfileStore(defaultModelID: primaryModel?.id,
                                    defaultLanguage: primaryModel?.defaultLanguage ?? "he")
        router = HotkeyRouter(doubleTapWindowMs: settings.doubleTapWindowMs)
        modelStore = store
    }
```

Change the `modelStore` declaration from `let modelStore = ModelStore()` to `let modelStore: ModelStore` (assigned in init).

- [ ] **Step 3: Rewrite `start()`** — replace the detector/hotkeys wiring block and the `.dictatoDefaultModelChanged` observer:

```swift
    func start() {
        router.onActivate = { [weak self] pid in
            Task { @MainActor in self?.hotkeyActivated(profileID: pid) }
        }
        router.onCancel = { [weak self] in
            Task { @MainActor in self?.cancelRecording() }
        }
        router.rebuild(profiles: profileStore.set, cancel: profileStore.cancelBinding)
        router.start()

        recorder.onLevel = { [weak self] level in self?.overlayModel.pushLevel(level) }
        overlayModel.onCancel = { [weak self] in
            Task { @MainActor in self?.cancelRecording() }
        }

        if !PermissionManager.accessibilityGranted { PermissionManager.promptForAccessibility() }
        if !PermissionManager.inputMonitoringGranted { PermissionManager.requestInputMonitoring() }

        NotificationCenter.default.addObserver(forName: .dictatoProfilesChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.router.rebuild(profiles: self.profileStore.set, cancel: self.profileStore.cancelBinding)
                await self.warmPrimaryModel()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Log.info("System woke — re-arming hotkey monitors")
            self.router.stop()
            self.router.start()
        }
        loadModel()
    }
```

- [ ] **Step 4: Update `wireMenu()`** — the dictate hint now comes from the primary profile:

```swift
        menuBar.setDictateHint(profileStore.set.primary?.hotkey.displayString ?? "")
```

(Remove the old `settings.dictateBinding.displayString` line.)

- [ ] **Step 5: Update `toggleFromMenu()`** and `hotkeyActivated` to carry a profile id.** Menu start/stop uses the primary profile:

```swift
    func toggleFromMenu() {
        hotkeyActivated(profileID: profileStore.set.primaryID)
    }

    private func hotkeyActivated(profileID: String) {
        Log.info("Hotkey activated for profile \(profileID) (state: \(machine.state))")
        switch machine.state {
        case .idle:
            activeProfileID = profileID
            startRecording()
        case .recording:
            stopAndTranscribe()
        default:
            break
        }
    }
```

- [ ] **Step 6: Update `warmDefaultModel()` → `warmPrimaryModel()`** and its `loadModel()` caller. Model + language come from the primary profile:

```swift
    private func loadModel() {
        machine = DictationStateMachine()
        menuBar.update(state: machine.state)
        Task { await warmPrimaryModel() }
    }

    private func warmPrimaryModel() async {
        guard let profile = profileStore.set.primary,
              let model = modelStore.catalog.model(id: profile.modelID) else {
            transition(.modelFailed("No primary profile model configured"))
            return
        }
        do {
            if !modelStore.isInstalled(model.id) {
                menuBar.setStatusText("Downloading \(model.displayName)…")
                await modelStore.install(model)
                guard modelStore.isInstalled(model.id) else {
                    transition(.modelFailed("Model download failed"))
                    scheduleErrorDismiss(after: 3); return
                }
            }
            _ = try await recognizerCache.recognizer(
                id: model.id, modelPath: modelStore.installedURL(for: model))
            menuBar.setPrimaryLanguage(profile.language)
            transition(.modelLoaded)
        } catch {
            Log.error("Model warm failed: \(error.localizedDescription)")
            transition(.modelFailed(error.localizedDescription))
            scheduleErrorDismiss(after: 3)
        }
    }

    private func reloadModel() {
        Task { await recognizerCache.evictAll(); await warmPrimaryModel() }
    }
```

- [ ] **Step 7: Route recording start through the active profile.** In `startRecording()`, replace the overlay language line and add router lock:

```swift
            let profile = profileStore.set.profile(id: activeProfileID ?? profileStore.set.primaryID)
            overlayModel.languageCode = profile?.language ?? "he"
            router.beginRecording(profileID: profile?.id ?? profileStore.set.primaryID)
            transition(.startRequested)
```

(Keep the existing `setTarget`, `preferredScreen`, sound, timer lines around it.)

- [ ] **Step 8: Use the active profile in `stopAndTranscribe()`.** Replace the `guard let model = modelStore.catalog.defaultModel` block and the `transcribe` call:

```swift
        Task {
            guard let profile = profileStore.set.profile(id: activeProfileID ?? profileStore.set.primaryID),
                  let model = modelStore.catalog.model(id: profile.modelID) else {
                finishWithError("No model"); return
            }
            do {
                let recognizer = try await recognizerCache.recognizer(
                    id: model.id, modelPath: modelStore.installedURL(for: model))
                let inferenceStart = Date()
                let text = try await recognizer.transcribe(samples: samples, language: profile.language)
                Log.info("Inference completed in \(String(format: "%.2f", -inferenceStart.timeIntervalSinceNow))s")
                guard !text.isEmpty else { finishWithError("No speech detected"); return }
                transition(.transcriptionSucceeded)
                inserter.insert(text, autoPaste: settings.autoPaste,
                                excludeFromHistory: settings.excludeFromClipboardHistory)
                transition(.insertionCompleted)
            } catch {
                Log.error("Inference failed: \(error.localizedDescription)")
                finishWithError("Could not transcribe")
            }
        }
```

- [ ] **Step 9: Release the router lock and reset active profile in `transition(...)`.** Replace the detector-mode block inside `transition(_:)`:

```swift
    private func transition(_ event: DictationEvent) {
        machine.handle(event)
        menuBar.update(state: machine.state)
        router.cancelEnabled = machine.state == .recording
        if machine.state != .recording {
            router.endRecording()
            activeProfileID = nil
        }
        if machine.state == .idle { scheduleIdleUnload() }
        updateOverlay()
    }
```

- [ ] **Step 10: Build**

Run: `make build && bash Tools/run-core-tests.sh`
Expected: `Build complete!`; no `FAIL:` lines.

- [ ] **Step 11: Commit Tasks 3 + 4 together**

```bash
git add Sources/Dictato/HotkeyRouter.swift Sources/Dictato/DictationController.swift
git rm --cached Sources/Dictato/HotkeyMonitor.swift 2>/dev/null; true
git commit -m "feat: HotkeyRouter multi-profile routing; per-profile model+language at record time"
```

---

## Task 5: Preferences UI — Profiles section, slim Hotkeys, wiring

**Files:**
- Create: `Sources/Dictato/Preferences/ProfilesSection.swift`
- Modify: `Sources/Dictato/Preferences/SettingsView.swift`
- Modify: `Sources/Dictato/PreferencesWindow.swift`

**Interfaces:**
- Consumes: `ProfileStore` (Task 2), `ModelStore`, `DictationProfile`, `HotkeyRecorderView`, `InsertionMode`.
- Produces: `ProfilesSection(profileStore:modelStore:)` view; `PrefSection.profiles` case.

- [ ] **Step 1: Inspect `PreferencesWindow.swift`** to match the existing store-injection pattern.

Run: `cat Sources/Dictato/PreferencesWindow.swift`
Expected: shows a `configure(store:)` that builds `SettingsView(store:)`.

- [ ] **Step 2: Add `.profiles` case to `PrefSection`** in `SettingsView.swift`:

```swift
    case general = "General"
    case models = "Dictation Models"
    case profiles = "Profiles"
    case hotkeys = "Hotkeys"
    case speech = "Speech"
    case debug = "Debug"
```

and in `icon`:

```swift
        case .profiles: return "person.crop.rectangle.stack"
```

- [ ] **Step 3: Thread `ProfileStore` into `SettingsView`.** Change its stored properties + detail switch:

```swift
struct SettingsView: View {
    @ObservedObject var store: ModelStore
    @ObservedObject var profileStore: ProfileStore
    @State private var section: PrefSection = .general
    // ... body unchanged ...
```

detail:

```swift
        case .profiles: ProfilesSection(profileStore: profileStore, modelStore: store)
```

- [ ] **Step 4: Replace the `HotkeysSection` body** so it holds only Cancel (dictate is now per-profile):

```swift
private struct HotkeysSection: View {
    private var settings = Settings()
    var body: some View {
        Form {
            Section {
                HotkeyRecorderView(title: "Cancel", binding: settings.cancelBinding) {
                    settings.cancelBinding = $0
                }
            } footer: {
                Text("Global cancel key while recording. Dictate hotkeys are set per profile.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Hotkeys")
    }
}
```

- [ ] **Step 5: Create `Sources/Dictato/Preferences/ProfilesSection.swift`**

```swift
import SwiftUI
import AppKit
import DictatoCore

struct ProfilesSection: View {
    @ObservedObject var profileStore: ProfileStore
    @ObservedObject var modelStore: ModelStore
    @State private var editing: DictationProfile?
    @State private var showingSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Profiles").font(.title2.weight(.semibold))
                    Spacer()
                    Button { startAdd() } label: { Label("Add profile", systemImage: "plus") }
                        .disabled(installedModels.isEmpty)
                }
                if installedModels.isEmpty {
                    Text("Install a model in Dictation Models first.")
                        .foregroundStyle(.secondary)
                }
                ForEach(profileStore.set.profiles) { profile in
                    ProfileCard(
                        profile: profile,
                        modelName: modelStore.catalog.model(id: profile.modelID)?.displayName ?? profile.modelID,
                        isPrimary: profile.id == profileStore.set.primaryID,
                        canDelete: profileStore.set.profiles.count > 1,
                        onPrimary: { profileStore.setPrimary(profile.id) },
                        onEdit: { startEdit(profile) },
                        onDelete: { profileStore.remove(profile.id) })
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Profiles")
        .sheet(isPresented: $showingSheet) {
            ProfileEditSheet(
                draft: editing ?? blankDraft(),
                isNew: editing == nil,
                models: installedModels,
                conflict: { hotkey, id in profileStore.conflict(for: hotkey, excluding: id) },
                onSave: { profileStore.upsert($0); showingSheet = false },
                onCancel: { showingSheet = false })
        }
    }

    private var installedModels: [ManagedModel] {
        modelStore.catalog.models.filter { modelStore.isInstalled($0.id) }
    }

    private func startAdd() { editing = nil; showingSheet = true }
    private func startEdit(_ p: DictationProfile) { editing = p; showingSheet = true }

    private func blankDraft() -> DictationProfile {
        let model = installedModels.first
        return DictationProfile(id: profileStore.newProfileID(),
                                name: "", modelID: model?.id ?? "",
                                language: model?.defaultLanguage ?? "he",
                                mode: .batch,
                                hotkey: .modifierTap(.rightCommand, count: 2))
    }
}

private struct ProfileCard: View {
    let profile: DictationProfile
    let modelName: String
    let isPrimary: Bool
    let canDelete: Bool
    let onPrimary: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(profile.name.isEmpty ? "Untitled" : profile.name).font(.headline)
                if isPrimary {
                    Text("Primary").font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.blue.opacity(0.25), in: Capsule())
                }
                Spacer()
                Text(profile.hotkey.displayString)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(0.08), in: Capsule())
            }
            HStack(spacing: 16) {
                Label(modelName, systemImage: "cpu")
                Label(profile.languageLabel, systemImage: "globe")
                Label(modeLabel, systemImage: "text.cursor")
            }
            .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if !isPrimary { Button("Set primary", action: onPrimary) }
                Button("Edit", action: onEdit)
                Spacer()
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .disabled(!canDelete)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
            isPrimary ? Color.blue.opacity(0.6) : .white.opacity(0.08), lineWidth: isPrimary ? 1.5 : 1))
    }

    private var modeLabel: String {
        profile.mode.isImplemented ? "Batch" : profile.mode.displayName
    }
}

private struct ProfileEditSheet: View {
    @State var draft: DictationProfile
    let isNew: Bool
    let models: [ManagedModel]
    let conflict: (HotkeyBinding, String?) -> Bool
    let onSave: (DictationProfile) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "Add profile" : "Edit profile").font(.headline)
            TextField("Name", text: $draft.name)
            Picker("Model", selection: $draft.modelID) {
                ForEach(models) { Text($0.displayName).tag($0.id) }
            }
            Picker("Language", selection: $draft.language) {
                Text("Hebrew").tag("he"); Text("English").tag("en"); Text("Multilingual").tag("auto")
            }
            Picker("Insertion mode", selection: $draft.mode) {
                ForEach(InsertionMode.allCases, id: \.self) { m in
                    Text(m.isImplemented ? m.displayName : "\(m.displayName) — coming soon").tag(m)
                }
            }
            .onChange(of: draft.mode) { if !$0.isImplemented { draft.mode = .batch } }
            HotkeyRecorderView(title: "Hotkey", binding: draft.hotkey) { draft.hotkey = $0 }
            if hotkeyConflict {
                Label("This hotkey is already used by another profile or Cancel.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") { onSave(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(20).frame(width: 460)
    }

    private var hotkeyConflict: Bool { conflict(draft.hotkey, isNew ? nil : draft.id) }
    private var isValid: Bool {
        !draft.name.isEmpty && !draft.modelID.isEmpty && !hotkeyConflict
    }
}
```

- [ ] **Step 6: Wire `ProfileStore` through `PreferencesWindow`.** Update `configure` to accept and pass the profile store. In `PreferencesWindow.swift`, change the `configure(store:)` signature to `configure(store: ModelStore, profileStore: ProfileStore)` and pass both into `SettingsView(store:profileStore:)`. Then in `DictationController.wireMenu()` update the call:

```swift
        PreferencesWindow.configure(store: modelStore, profileStore: profileStore)
```

(Match the exact stored-property/rootView construction already in `PreferencesWindow.swift` from Step 1's output — only add the second store.)

- [ ] **Step 7: Build + core tests**

Run: `make build && bash Tools/run-core-tests.sh`
Expected: `Build complete!`; no `FAIL:` lines.

- [ ] **Step 8: Install + launch smoke test**

Run: `make install && open -a Dictato`
Manual checks:
- Preferences → Profiles shows one migrated primary profile (Hebrew, right-⌘⌘).
- Add a second profile (e.g. English small model, right-⌥⌥); duplicate right-⌘ hotkey shows the conflict warning and disables Save.
- Right-⌘⌘ dictates with Hebrew model; right-⌥⌥ dictates with the English model.
- Mid-recording, pressing the other profile's hotkey does nothing.
- Set the English profile primary → menu-bar glyph flips to Latin A; overlay logo flips when idle.
- Editing a profile's hotkey takes effect without reopening the app (router rebuild).

- [ ] **Step 9: Commit**

```bash
git add Sources/Dictato/Preferences/ProfilesSection.swift Sources/Dictato/Preferences/SettingsView.swift Sources/Dictato/PreferencesWindow.swift
git commit -m "feat: Profiles preferences section; Hotkeys section trimmed to Cancel"
```

---

## Self-Review

**Spec coverage:**
- §1 data model → Task 1 (`DictationProfile`, `ProfileSet`, migration, conflict). ✓
- §1 persistence + migration on launch → Task 2 (`ProfileStore`, `profilesJSON`). ✓
- §1 `catalog.defaultModelID` repurpose → primary model read from `catalog.defaultModel` at init seeding (Task 4 Step 2); primary profile drives runtime. Note: catalog default is not re-synced when primary changes (runtime uses profile, so no functional gap); Models screen keeps its own default — acceptable, documented as non-functional in spec. ✓
- §2 routing, cancel, mid-record ignore, live rebuild → Tasks 3 + 4. ✓
- §2 controller active-profile transcribe + glyph → Task 4 Steps 6–9. ✓
- §3 UI Profiles section, Add/Edit sheet, uniqueness validation, greyed streaming modes, Cancel-only Hotkeys → Task 5. ✓
- Testing (core) → Task 1 Step 1; manual → Task 5 Step 8. ✓

**Placeholder scan:** Task 3 Step 1 contains an intentionally-wrong `endRecording` explicitly replaced in Step 2 (called out in-line). No other placeholders.

**Type consistency:** `ProfileSet.conflict(for:excluding:cancel:)`, `.upserting`, `.removing`, `.settingPrimary`, `.normalizedPrimary`, `.migrated` used consistently across Tasks 1/2/5. `router.rebuild(profiles:cancel:)`, `beginRecording(profileID:)`, `endRecording()`, `onActivate:(String)->Void` consistent across Tasks 3/4. `warmPrimaryModel()` replaces `warmDefaultModel()` everywhere it was called (loadModel, reloadModel, profilesChanged observer).

**Note for implementer:** `ModifierTapDetector.Mode` is `public` already (used cross-module). `ProfileStore` reads `settings.dictateBinding` only during migration; after migration the legacy key is ignored (left in place, harmless).
