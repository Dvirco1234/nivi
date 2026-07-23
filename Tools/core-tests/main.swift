import Foundation

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if !cond { print("FAIL: \(msg)"); failures += 1 }
}

// --- HotkeyBinding ---
check(ModifierKey.rightCommand.keyCode == 54, "rightCommand keyCode")
check(ModifierKey.leftCommand.keyCode == 55, "leftCommand keyCode")
check(HotkeyBinding.modifierTap(.rightCommand, count: 2).displayString == "⌘⌘ (right)",
      "double right cmd display")
check(HotkeyBinding.keyCombo(keyCode: 53, modifiers: 0).displayString == "esc",
      "esc display")
let bnd = HotkeyBinding.defaultDictate
check(HotkeyBinding.from(json: bnd.encodedJSON()) == bnd, "binding json round-trip")

// --- Settings new keys ---
let suite = UserDefaults(suiteName: "com.dvir.dictato.coretest")!
suite.removePersistentDomain(forName: "com.dvir.dictato.coretest")
var s = Settings(defaults: suite)
check(s.insertionMode == .batch, "default insertion mode batch")
check(InsertionMode.overlayLive.isImplemented == false, "overlayLive not impl in 2a")
check(s.dictateBinding == .defaultDictate, "default dictate binding")
s.insertionMode = .overlayLive
s.dictateBinding = .modifierTap(.leftCommand, count: 2)
let s2 = Settings(defaults: suite)
check(s2.insertionMode == .overlayLive, "insertion mode persists")
check(s2.dictateBinding == .modifierTap(.leftCommand, count: 2), "dictate binding persists")

// --- ModifierTapDetector ---
var clock: TimeInterval = 0
let det = ModifierTapDetector(doubleTapWindow: 0.4, now: { clock })
var acts = 0
det.onActivate = { acts += 1 }
func tapMod(_ t: TimeInterval) { clock = t; det.modifierChanged(down: true); det.modifierChanged(down: false) }
det.mode = .doubleTap
tapMod(0); tapMod(0.3); check(acts == 1, "double tap activates")
det.mode = .singleTap
acts = 0
det.modifierChanged(down: true); det.otherKeyDown(); det.modifierChanged(down: false)
check(acts == 0, "combo not a tap")
tapMod(1.0); check(acts == 1, "single tap activates")

// --- ManagedModel / ModelSource / ModelCatalog ---
check(ModelSource.huggingFace(repo: "ivrit-ai/whisper-large-v3-turbo-ggml", file: "ggml-model.bin").downloadURL?.absoluteString
      == "https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml/resolve/main/ggml-model.bin",
      "hf download url")
check(ModelSource.directURL(URL(string: "https://x.com/m.bin")!).downloadURL?.absoluteString == "https://x.com/m.bin",
      "direct url")
check(ModelSource.localFile(path: "/tmp/m.bin").downloadURL == nil, "local has no download url")

let cat = ModelCatalog.seeded()
check(cat.defaultModelID == "ivrit-large-v3-turbo", "seeded default")
check(cat.models.count == 3, "seeded has 3 presets")
check(cat.defaultModel?.localFileName == "ivrit-large-v3-turbo.bin", "local file name")
check(cat.model(id: "whisper-small-en")?.defaultLanguage == "en", "english preset lang")
let catData = try! JSONEncoder().encode(cat)
check((try? JSONDecoder().decode(ModelCatalog.self, from: catData)) == cat, "catalog codable round-trip")

// --- ModelCatalogStore / ModelPaths / migration ---
let base = FileManager.default.temporaryDirectory
    .appendingPathComponent("dictato-2b-coretest", isDirectory: true)
try? FileManager.default.removeItem(at: base)
let mdir = ModelPaths.modelsDir(base: base)
try! FileManager.default.createDirectory(at: mdir, withIntermediateDirectories: true)

let mm = ManagedModel(id: "ivrit-large-v3-turbo", displayName: "x",
    source: .huggingFace(repo: "r", file: "f"), defaultLanguage: "he", minSizeBytes: 8)
check(ModelPaths.installedURL(for: mm, base: base).lastPathComponent == "ivrit-large-v3-turbo.bin",
      "installed url filename")

let legacy = mdir.appendingPathComponent("ggml-ivrit-large-v3-turbo.bin")
try! Data([0x6C,0x6D,0x67,0x67,0,0,0,0]).write(to: legacy)
ModelCatalogStore.migrateLegacy(modelsDir: mdir)
check(FileManager.default.fileExists(atPath: mdir.appendingPathComponent("ivrit-large-v3-turbo.bin").path),
      "legacy migrated")
check(!FileManager.default.fileExists(atPath: legacy.path), "legacy removed")

let catURL = base.appendingPathComponent("models.json")
let boot = ModelCatalogStore.bootstrap(catalogURL: catURL, modelsDir: mdir)
check(boot.defaultModelID == "ivrit-large-v3-turbo", "bootstrap seeded default")
check(ModelCatalogStore.load(from: catURL) != nil, "catalog persisted")
check(ModelCatalogStore.canDelete("whisper-small-en", from: boot, installedIDs: ["ivrit-large-v3-turbo"]) == false,
      "cannot delete not-installed")
check(ModelCatalogStore.canDelete("ivrit-large-v3-turbo", from: boot, installedIDs: ["ivrit-large-v3-turbo"]) == false,
      "cannot delete default")
check(ModelCatalogStore.canDelete("whisper-small-en", from: boot,
      installedIDs: ["ivrit-large-v3-turbo","whisper-small-en"]) == true, "can delete extra installed")
try? FileManager.default.removeItem(at: base)

// --- recognizerCacheCapacity ---
check(Settings(defaults: suite).recognizerCacheCapacity == 2, "default cache capacity 2")

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

if failures == 0 { print("ALL CORE CHECKS PASSED") } else { print("\(failures) FAILURES"); exit(1) }
