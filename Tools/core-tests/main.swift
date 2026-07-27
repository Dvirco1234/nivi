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

// --- StablePrefixTracker ---
var tracker = StablePrefixTracker(stabilityPasses: 2)
check(tracker.update("hello") == "", "first pass commits nothing")
check(tracker.update("hello world") == "hello", "word stable across two passes commits")
check(tracker.update("hello world") == "hello world", "all words stable commit")

// a correction before stabilization must not commit the wrong word
var t2 = StablePrefixTracker(stabilityPasses: 2)
_ = t2.update("hello word")
let afterCorrection = t2.update("hello world")
check(afterCorrection == "hello", "unstable trailing word not committed")
check(t2.update("hello world") == "hello world", "converges once stable")

// monotonic: a shorter later transcript never shrinks the committed prefix
var t3 = StablePrefixTracker(stabilityPasses: 2)
_ = t3.update("one two three")
_ = t3.update("one two three")
check(t3.update("one") == "one two three", "committed prefix never shrinks")

// instances are independent (fresh tracker per recording)
var t4 = StablePrefixTracker(stabilityPasses: 2)
check(t4.update("alpha") == "", "fresh instance starts empty")

// stabilityPasses 3 needs three identical passes
var t5 = StablePrefixTracker(stabilityPasses: 3)
_ = t5.update("a b")
_ = t5.update("a b")
check(t5.update("a b") == "a b", "three-pass stability commits on third")

// whitespace/newlines collapse to single-space joins
var t6 = StablePrefixTracker(stabilityPasses: 2)
_ = t6.update("  spaced   out \n text ")
check(t6.update("  spaced   out \n text ") == "spaced out text", "whitespace normalized")

// committed CONTENT is permanent, not just its length: once the passes that
// justified an early word evict from the history window, a contradicting-then-
// agreeing pair must not rewrite it (those words are already in the document).
var t7 = StablePrefixTracker(stabilityPasses: 2)
_ = t7.update("a b c")
_ = t7.update("a b c")           // commits "a b c"
_ = t7.update("x b c d")         // disagrees at position 0
let rewritten = t7.update("x b c d")   // history now agrees, but "a" is already committed
check(rewritten.hasPrefix("a b c"), "already-committed words are never rewritten")

// --- streaming settings ---
let ssuite = UserDefaults(suiteName: "com.dvir.dictato.coretest")!
let st = Settings(defaults: ssuite)
check(st.maxStreamingSeconds == 30, "default maxStreamingSeconds")
check(st.streamingIntervalMs == 500, "default streamingIntervalMs")
st.maxStreamingSeconds = 45
st.streamingIntervalMs = 700
let st2 = Settings(defaults: ssuite)
check(st2.maxStreamingSeconds == 45, "maxStreamingSeconds persists")
check(st2.streamingIntervalMs == 700, "streamingIntervalMs persists")

// --- appendOnlyTail: the seam between streamed typing and the final pass ---
// Insertion is append-only, so the tail must never contain text that is already in
// the document, and must never require deleting anything to be correct.

check(appendOnlyTail(alreadyTyped: "", fullText: "Hello world") == "Hello world",
      "nothing typed yet: emit the whole text, no leading space")

check(appendOnlyTail(alreadyTyped: "Hello world", fullText: "Hello world this is a test")
        == " this is a test",
      "exact prefix continuation appends only the new words")

// The headline case: the final pass re-punctuates and re-capitalizes what was
// already typed, so a character-offset seam would re-emit part of a typed word.
check(appendOnlyTail(alreadyTyped: "Hello world this is",
                     fullText: "Hello, world. This is a test.") == " a test.",
      "re-punctuated prefix does not duplicate words")

check(appendOnlyTail(alreadyTyped: "Hello world this is a test",
                     fullText: "Hello world this is") == "",
      "final text shorter than typed adds nothing")

check(appendOnlyTail(alreadyTyped: "Hello world", fullText: "") == "",
      "empty final text adds nothing")

check(appendOnlyTail(alreadyTyped: "", fullText: "") == "",
      "nothing typed and nothing final adds nothing")

// No common prefix at all: none of the final text is in the document, so appending
// all of it is the append-only choice. Dropping it would silently lose speech.
check(appendOnlyTail(alreadyTyped: "alpha beta", fullText: "gamma delta") == " gamma delta",
      "fully divergent final text is appended whole")

check(appendOnlyTail(alreadyTyped: "Hello world ", fullText: "Hello world again") == "again",
      "typed text already ending in a space is not double-spaced")

check(appendOnlyTail(alreadyTyped: "שלום עולם", fullText: "שלום עולם, מה נשמע") == " מה נשמע",
      "non-latin script matches on word boundaries too")

if failures == 0 { print("ALL CORE CHECKS PASSED") } else { print("\(failures) FAILURES"); exit(1) }
