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
let suite = UserDefaults(suiteName: "com.dvir.nivi.coretest")!
suite.removePersistentDomain(forName: "com.dvir.nivi.coretest")
let s = Settings(defaults: suite)
check(s.dictateBinding == .defaultDictate, "default dictate binding")
s.dictateBinding = .modifierTap(.leftCommand, count: 2)
let s2 = Settings(defaults: suite)
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
check(cat.models.count == 5, "seeded has 5 presets")
// A model is only offered for download if an engine here can actually run it.
check(cat.models.filter { $0.isRunnable }.count == 3, "three seeded models are runnable")
check(cat.model(id: "parakeet-tdt-0.6b-v3")?.engine == .parakeet, "parakeet v3 declares its engine")
check(cat.model(id: "parakeet-tdt-0.6b-v3")?.isRunnable == false, "parakeet is not runnable yet")
check(cat.model(id: "ivrit-large-v3-turbo")?.isRunnable == true, "whisper models stay runnable")

// A catalog saved before a preset existed must gain it, or models added in a later
// release would never appear for anyone who had already run the app.
let staleCatalog = ModelCatalog(
    models: [ManagedModel(id: "ivrit-large-v3-turbo", displayName: "stale name",
                          source: .huggingFace(repo: "r", file: "f"),
                          defaultLanguage: "he", minSizeBytes: 1),
             ManagedModel(id: "my-own", displayName: "User model",
                          source: .localFile(path: "/tmp/x.bin"),
                          defaultLanguage: "he", minSizeBytes: 1)],
    defaultModelID: "ivrit-large-v3-turbo")
let mergedCatalog = ModelCatalogStore.mergingPresets(into: staleCatalog)
check(mergedCatalog.model(id: "parakeet-tdt-0.6b-v3") != nil, "merge adds presets missing from a saved catalog")
check(mergedCatalog.model(id: "my-own") != nil, "merge keeps user-added models")
check(mergedCatalog.defaultModelID == "ivrit-large-v3-turbo", "merge keeps the saved default")
check(mergedCatalog.model(id: "ivrit-large-v3-turbo")?.displayName == "ivrit-ai Large v3 Turbo",
      "merge refreshes preset metadata")
check(ModelCatalogStore.mergingPresets(into: mergedCatalog) == mergedCatalog, "merging twice changes nothing")
// Catalogs written before engines existed decode as whisper.cpp rather than failing.
let legacyJSON = #"{"id":"legacy","displayName":"Legacy","source":{"huggingFace":{"repo":"r","file":"f"}},"defaultLanguage":"he","minSizeBytes":1}"#
if let legacy = try? JSONDecoder().decode(ManagedModel.self, from: Data(legacyJSON.utf8)) {
    check(legacy.engine == .whisperCpp, "model without an engine decodes as whisper.cpp")
} else {
    check(false, "legacy model JSON still decodes")
}
check(cat.defaultModel?.localFileName == "ivrit-large-v3-turbo.bin", "local file name")
check(cat.model(id: "whisper-small-en")?.defaultLanguage == "en", "english preset lang")
let catData = try! JSONEncoder().encode(cat)
check((try? JSONDecoder().decode(ModelCatalog.self, from: catData)) == cat, "catalog codable round-trip")

// --- ModelCatalogStore / ModelPaths / migration ---
let base = FileManager.default.temporaryDirectory
    .appendingPathComponent("nivi-2b-coretest", isDirectory: true)
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

// --- memory defaults ---
// One model, released after two minutes. Holding a second 1.6 GB model to make switching
// instant is not worth 1.6 GB on a machine that is already short of memory.
check(Settings(defaults: suite).recognizerCacheCapacity == 1, "one model kept in memory by default")
check(Settings(defaults: suite).idleUnloadSeconds == 120, "the model is released after two minutes idle")
check(Settings(defaults: suite).removeSoundDescriptions, "sound descriptions are dropped by default")
// The old defaults, written to disk by an older build, are cleared once so the new ones
// apply. A value the user actually picked is left alone.
let memorySuite = UserDefaults(suiteName: "com.dvir.nivi.memorytest")!
memorySuite.removePersistentDomain(forName: "com.dvir.nivi.memorytest")
memorySuite.set(2, forKey: "recognizerCacheCapacity")
memorySuite.set(300, forKey: "idleUnloadSeconds")
check(Settings(defaults: memorySuite).recognizerCacheCapacity == 1, "the old capacity of 2 is cleared")
check(Settings(defaults: memorySuite).idleUnloadSeconds == 120, "the old five minutes is cleared")
let keptSuite = UserDefaults(suiteName: "com.dvir.nivi.kepttest")!
keptSuite.removePersistentDomain(forName: "com.dvir.nivi.kepttest")
keptSuite.set(4, forKey: "recognizerCacheCapacity")
keptSuite.set(600, forKey: "idleUnloadSeconds")
check(Settings(defaults: keptSuite).recognizerCacheCapacity == 4, "a capacity the user picked is kept")
check(Settings(defaults: keptSuite).idleUnloadSeconds == 600, "an idle time the user picked is kept")
// Running again must not undo a later choice.
keptSuite.set(3, forKey: "recognizerCacheCapacity")
check(Settings(defaults: keptSuite).recognizerCacheCapacity == 3, "the move runs only once")
memorySuite.removePersistentDomain(forName: "com.dvir.nivi.memorytest")
keptSuite.removePersistentDomain(forName: "com.dvir.nivi.kepttest")

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
let ssuite = UserDefaults(suiteName: "com.dvir.nivi.coretest")!
let st = Settings(defaults: ssuite)
check(st.streamingIntervalMs == 500, "default streamingIntervalMs")
st.streamingIntervalMs = 700
let st2 = Settings(defaults: ssuite)
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

// --- StreamWindow ---
func seg(_ t: String, _ s: Int, _ e: Int) -> TranscriptSegment {
    TranscriptSegment(text: t, startMs: s, endMs: e)
}
let rate = 16_000
let tenSeconds = rate * 10

// Under the window length: nothing freezes, live text is just the window.
var w1 = StreamWindow()
let live1 = w1.advance(segments: [seg("hello world", 0, 2000)],
                       windowSampleCount: rate * 3, maxWindowSamples: tenSeconds, sampleRate: rate)
check(live1 == "hello world", "short window returns window text")
check(w1.frozenText.isEmpty, "nothing frozen under the cap")
check(w1.windowStartSample == 0, "window start unmoved under the cap")

// Over the cap: leading segments freeze and the window start advances to that segment's end.
var w2 = StreamWindow()
let live2 = w2.advance(segments: [seg("first part", 0, 3000), seg("second part", 3000, 12000)],
                       windowSampleCount: rate * 12, maxWindowSamples: tenSeconds, sampleRate: rate)
check(w2.frozenText == "first part", "leading segment frozen once past the cap")
check(w2.windowStartSample == rate * 3, "window start advanced to the frozen segment end")
check(live2 == "first part second part", "live text stitches frozen and window text")

// Several segments can freeze in one pass.
var w3 = StreamWindow()
_ = w3.advance(segments: [seg("a", 0, 2000), seg("b", 2000, 4000), seg("c", 4000, 14000)],
               windowSampleCount: rate * 14, maxWindowSamples: tenSeconds, sampleRate: rate)
check(w3.frozenText == "a b", "multiple segments freeze in one pass")
check(w3.windowStartSample == rate * 4, "window start advanced past the last frozen segment")

// The final segment never freezes, even if it alone exceeds the window: it is still
// being spoken and its text will keep changing.
var w4 = StreamWindow()
_ = w4.advance(segments: [seg("one long unbroken stretch", 0, 20000)],
               windowSampleCount: rate * 20, maxWindowSamples: tenSeconds, sampleRate: rate)
check(w4.frozenText.isEmpty, "sole segment never freezes")
check(w4.windowStartSample == 0, "window start unmoved when only one segment exists")

// A failed/empty pass must not freeze or move the window.
var w5 = StreamWindow()
_ = w5.advance(segments: [seg("kept", 0, 3000), seg("tail", 3000, 12000)],
               windowSampleCount: rate * 12, maxWindowSamples: tenSeconds, sampleRate: rate)
let frozenBefore = w5.frozenText
let startBefore = w5.windowStartSample
let live5 = w5.advance(segments: [], windowSampleCount: rate * 13,
                       maxWindowSamples: tenSeconds, sampleRate: rate)
check(w5.frozenText == frozenBefore, "empty pass does not change frozen text")
check(w5.windowStartSample == startBefore, "empty pass does not move the window")
check(live5 == frozenBefore, "empty pass returns the frozen text alone")

// Window start advances monotonically across passes.
var w6 = StreamWindow()
_ = w6.advance(segments: [seg("x", 0, 2000), seg("y", 2000, 12000)],
               windowSampleCount: rate * 12, maxWindowSamples: tenSeconds, sampleRate: rate)
let afterFirst = w6.windowStartSample
_ = w6.advance(segments: [seg("y", 0, 1000), seg("z", 1000, 11000)],
               windowSampleCount: rate * 11, maxWindowSamples: tenSeconds, sampleRate: rate)
check(w6.windowStartSample >= afterFirst, "window start never goes backwards")

// Stitching produces single spaces, no doubling, and trims segment whitespace.
var w7 = StreamWindow()
let live7 = w7.advance(segments: [seg("  padded  ", 0, 3000), seg("  text  ", 3000, 12000)],
                       windowSampleCount: rate * 12, maxWindowSamples: tenSeconds, sampleRate: rate)
check(live7 == "padded text", "segment whitespace trimmed and joined with single spaces")

// --- audio context sizing ---
let audioRate = 16000
check(audioContext(forSampleCount: audioRate / 2, sampleRate: audioRate) == 256,
      "a very short slice clamps to the floor")
check(audioContext(forSampleCount: audioRate * 30, sampleRate: audioRate) == 1500,
      "a 30s slice asks for whisper's full context")
check(audioContext(forSampleCount: audioRate * 120, sampleRate: audioRate) == 1500,
      "an over-long slice clamps to whisper's full context")
check(audioContext(forSampleCount: audioRate * 10, sampleRate: audioRate) == 628,
      "a 10s slice is proportional plus slack")
check(audioContext(forSampleCount: audioRate * 12, sampleRate: audioRate) == 728,
      "an overrunning window gets more context than the nominal window would")
check(audioContext(forSampleCount: 0, sampleRate: audioRate) == 256,
      "an empty slice falls back to the floor")

// Alignment. Whisper's Metal backend aborts the whole process on an audio context that
// is not a multiple of 4, so every value this can ever return has to be one.
// See AudioContext.swift for the assertion it used to hit.
for testSeconds in stride(from: 0.5, through: 40.0, by: 0.1) {
    let value = audioContext(forSampleCount: Int(Double(audioRate) * testSeconds),
                             sampleRate: audioRate)
    check(isUsableAudioContext(value),
          "audio context for \(testSeconds)s is usable, got \(value)")
}
// The values that used to reach whisper unrounded. 628 and 728 were already aligned,
// which is why the crash only showed up on other slice lengths.
check(audioContext(forSampleCount: audioRate * 3, sampleRate: audioRate) == 280,
      "a 3s slice rounds 278 up to 280")
check(audioContext(forSampleCount: 41300, sampleRate: audioRate) == 260,
      "the slice that produced 257 now rounds up to 260")
check(audioContext(forSampleCount: 80000, sampleRate: audioRate) == 380,
      "a 5s slice rounds 378 up to 380")
check(!isUsableAudioContext(257), "257 is not a multiple of 4, so it is refused")
check(!isUsableAudioContext(371), "371 is not a multiple of 4, so it is refused")
check(!isUsableAudioContext(629), "629 is not a multiple of 4, so it is refused")
check(isUsableAudioContext(260) && isUsableAudioContext(628) && isUsableAudioContext(1500),
      "multiples of 4 inside the range are fine")
check(!isUsableAudioContext(0), "whisper's own 'use everything' value is not passed through here")
check(!isUsableAudioContext(1504), "past whisper's full context is refused")
check(!isUsableAudioContext(252), "below the floor is refused")

// --- settings ---
let wsuite = UserDefaults(suiteName: "com.dvir.nivi.coretest")!
let wset = Settings(defaults: wsuite)
check(wset.streamingWindowSeconds == 10, "default streamingWindowSeconds")
wset.streamingWindowSeconds = 15
check(Settings(defaults: wsuite).streamingWindowSeconds == 15, "streamingWindowSeconds persists")


// --- new settings frozen for the Preferences redesign ---
let prefSuite = UserDefaults(suiteName: "com.dvir.nivi.coretest.prefs")!
prefSuite.removePersistentDomain(forName: "com.dvir.nivi.coretest.prefs")
let prefs = Settings(defaults: prefSuite)
check(prefs.appearance == .system, "default appearance follows the system")
check(prefs.showInDock, "Dock icon is on by default")
check(prefs.showInStatusBar, "menu bar icon is on by default")
check(prefs.escapeToCancelEnabled, "Esc to cancel is on by default")
check(!prefs.muteWhileRecording, "mute while recording is off by default")
check(!prefs.trackpadFeedback, "trackpad feedback is off by default")
check(prefs.textInputMethod == .paste, "text is pasted by default")
check(prefs.microphonePriority.isEmpty, "no microphone order by default")
check(prefs.wordReplacementsJSON.isEmpty, "no word replacements by default")
check(prefs.historyEnabled, "history is on by default")
check(prefs.historyRetentionDays == 30, "history is kept 30 days by default")
check(prefs.fileChunkMinutes == 5, "file chunks are 5 minutes by default")
prefs.appearance = .dark
prefs.historyRetentionDays = 0
prefs.fileChunkMinutes = 99
let prefsAgain = Settings(defaults: prefSuite)
check(prefsAgain.appearance == .dark, "appearance persists")
check(prefsAgain.historyRetentionDays == 0, "keep forever persists as 0")
check(prefsAgain.fileChunkMinutes == 15, "chunk minutes clamp to 15")

// --- DurationFormatting ---
check(DurationFormatting.short(0) == "0 seconds", "zero length")
check(DurationFormatting.short(-4) == "0 seconds", "negative length is treated as zero")
check(DurationFormatting.short(1) == "1 second", "one second is singular")
check(DurationFormatting.short(10) == "10 seconds", "ten seconds")
check(DurationFormatting.short(72) == "1 min 12 s", "a minute and a bit")
check(DurationFormatting.short(300) == "5 min", "a whole number of minutes drops the seconds")
check(DurationFormatting.short(3840) == "1 h 04 m", "over an hour")
check(DurationFormatting.short(milliseconds: 1500) == "2 seconds", "milliseconds round to seconds")

// --- HistoryRecord round trip ---
let sampleRecord = HistoryRecord(id: "abc",
                                 createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                                 text: "hello there",
                                 durationMs: 4200,
                                 source: .dictation,
                                 modelID: "large-v3-turbo",
                                 language: "en",
                                 profileID: "p1",
                                 sourceName: "Notes")
let recordLine = HistoryFile.line(for: sampleRecord)!
check(!recordLine.contains("\n"), "a record is one single line")
check(recordLine.contains("1700000000"), "the date is stored as epoch seconds")
let readBack = HistoryFile.records(fromFileText: recordLine + "\n")
check(readBack == [sampleRecord], "a record survives the file round trip")
let withRubbish = HistoryFile.records(fromFileText: recordLine + "\n{ broken\n" + recordLine + "\n")
check(withRubbish.count == 2, "a half-written line is skipped, the rest still reads")

// --- HistoryRetention ---
func aged(_ daysOld: Double, _ id: String) -> HistoryRecord {
    HistoryRecord(id: id,
                  createdAt: Date(timeIntervalSince1970: 1_000_000 - daysOld * 86_400),
                  text: id, durationMs: 1000, source: .dictation,
                  modelID: "m", language: "en")
}
let rightNow = Date(timeIntervalSince1970: 1_000_000)
let ageMix = [aged(1, "fresh"), aged(10, "week"), aged(100, "old")]
check(HistoryRetention.keeping(ageMix, retentionDays: 0, now: rightNow).count == 3,
      "zero days keeps everything")
check(HistoryRetention.keeping(ageMix, retentionDays: -5, now: rightNow).count == 3,
      "a bad negative value never deletes anything")
check(HistoryRetention.keeping(ageMix, retentionDays: 7, now: rightNow).map(\.id) == ["fresh"],
      "seven days drops the older two")
check(HistoryRetention.keeping(ageMix, retentionDays: 30, now: rightNow).map(\.id) == ["fresh", "week"],
      "thirty days keeps the middle one")
check(HistoryRetention.optionLabel(days: 0) == "Keep forever", "keep forever label")
check(HistoryRetention.optionLabel(days: 365) == "1 year", "one year label")

// --- HistoryFiltering ---
func made(_ id: String, _ text: String, _ source: HistorySource, secondsAgo: Double, name: String? = nil) -> HistoryRecord {
    HistoryRecord(id: id, createdAt: Date(timeIntervalSince1970: 1_000_000 - secondsAgo),
                  text: text, durationMs: 1000, source: source,
                  modelID: "m", language: "en", sourceName: name)
}
let historyList = [
    made("a", "Buy milk today", .dictation, secondsAgo: 30),
    made("b", "Meeting notes", .file, secondsAgo: 10, name: "standup.m4a"),
    made("c", "test one two", .modelTest, secondsAgo: 60),
]
check(HistoryFiltering.apply(HistoryQuery(), to: historyList).map(\.id) == ["b", "a", "c"],
      "newest first by default")
check(HistoryFiltering.apply(HistoryQuery(newestFirst: false), to: historyList).map(\.id) == ["c", "a", "b"],
      "oldest first when asked")
check(HistoryFiltering.apply(HistoryQuery(sources: [.file]), to: historyList).map(\.id) == ["b"],
      "filtering by source")
check(HistoryFiltering.apply(HistoryQuery(searchText: "MILK"), to: historyList).map(\.id) == ["a"],
      "search ignores case")
check(HistoryFiltering.apply(HistoryQuery(searchText: "standup"), to: historyList).map(\.id) == ["b"],
      "search also looks at the file name")
check(HistoryFiltering.apply(HistoryQuery(searchText: "   "), to: historyList).count == 3,
      "an all-spaces search is no search")

// --- WordReplacement ---
let replacements = [
    WordReplacement(id: "1", find: "cat", replaceWith: "dog"),
    WordReplacement(id: "2", find: "hello", replaceWith: "Hi", matchWholeWord: false),
    WordReplacement(id: "3", find: "never", replaceWith: "always", isEnabled: false),
]
check(WordReplacing.apply(replacements, to: "the cat sat") == "the dog sat", "whole word replaced")
check(WordReplacing.apply(replacements, to: "a category") == "a category", "whole word does not match inside a word")
check(WordReplacing.apply(replacements, to: "CAT scan") == "dog scan", "matching ignores case")
check(WordReplacing.apply(replacements, to: "say hellothere") == "say Hithere", "partial match when whole word is off")
check(WordReplacing.apply(replacements, to: "never mind") == "never mind", "a disabled rule does nothing")
check(WordReplacing.apply([WordReplacement(id: "4", find: "x", replaceWith: "$1")], to: "x")
      == "$1", "a dollar sign in the replacement is written as typed")
let encodedRules = WordReplacing.encode(replacements)
check(WordReplacing.decode(json: encodedRules) == replacements, "rules survive the json round trip")
check(WordReplacing.decode(json: "not json").isEmpty, "bad json gives no rules")

// --- TranscribableFormat ---
check(TranscribableFormat.isSupported(fileExtension: "mp3"), "mp3 is supported")
check(TranscribableFormat.isSupported(fileExtension: ".M4A"), "a leading dot and capitals still match")
check(!TranscribableFormat.isSupported(fileExtension: "ogg"), "ogg is not supported")
check(TranscribableFormat.isKnownUnsupported(fileExtension: "webm"), "webm is a known miss")
check(!TranscribableFormat.isKnownUnsupported(fileExtension: "wav"), "wav is not a known miss")

// --- AudioChunkPlanner ---
let chunkRate = 16000
check(AudioChunkPlanner.cutPoints(sampleCount: chunkRate * 60, sampleRate: chunkRate, chunkSeconds: 300).isEmpty,
      "a file shorter than one chunk is not cut")
check(AudioChunkPlanner.cutPoints(sampleCount: chunkRate * 650, sampleRate: chunkRate, chunkSeconds: 300)
      == [chunkRate * 300], "a short last piece is folded into the piece before it")
check(AudioChunkPlanner.cutPoints(sampleCount: chunkRate * 800, sampleRate: chunkRate, chunkSeconds: 300)
      == [chunkRate * 300, chunkRate * 600], "a longer file is cut twice")
check(AudioChunkPlanner.cutPoints(sampleCount: 0, sampleRate: chunkRate, chunkSeconds: 5).isEmpty,
      "no samples, no cuts")
check(AudioChunkPlanner.cutPoints(sampleCount: 1000, sampleRate: chunkRate, chunkSeconds: 0).isEmpty,
      "a zero chunk length is refused instead of looping forever")

// A loud tone with one silent second sitting 2 seconds before the even cut. The planner
// should move the cut into that silence.
var toneSamples = [Float](repeating: 0.5, count: chunkRate * 20)
let silenceStart = chunkRate * 8
for index in silenceStart..<(silenceStart + chunkRate) { toneSamples[index] = 0 }
let quietCuts = AudioChunkPlanner.cutPoints(samples: toneSamples,
                                            sampleRate: chunkRate,
                                            chunkSeconds: 10,
                                            searchSeconds: 3)
check(quietCuts.count == 1, "one cut for a twenty second clip in ten second chunks")
check(quietCuts[0] >= silenceStart && quietCuts[0] <= silenceStart + chunkRate,
      "the cut lands inside the silent second")
let evenCuts = AudioChunkPlanner.cutPoints(samples: [Float](repeating: 0.5, count: chunkRate * 20),
                                           sampleRate: chunkRate,
                                           chunkSeconds: 10,
                                           searchSeconds: 3)
check(evenCuts.count == 1, "steady sound still gets its cut")

// --- TranscriptCleaning ---
// The rule is about shape, not a list of known phrases: anything fully wrapped in
// brackets, parentheses, asterisks or musical notes is a note about a sound, not speech.
check(TranscriptCleaning.clean("[BLANK_AUDIO]") == "", "a lone blank audio note leaves nothing")
check(TranscriptCleaning.isOnlyNoise("[ Silence ]"), "spacing and capitals still count as a note")
check(TranscriptCleaning.isOnlyNoise("(speaking in foreign language)"), "the foreign language note")
check(TranscriptCleaning.isOnlyNoise("*clears throat*"), "asterisks around a note")
check(TranscriptCleaning.isOnlyNoise("♪♪♪"), "musical notes on their own")
check(TranscriptCleaning.isOnlyNoise("(gentle music)"), "a short description ending in music")

// The case the user actually hit. It was on no list, which is why the list had to go.
check(TranscriptCleaning.clean("(people chattering)") == "",
      "the real failing case: (people chattering) is dropped")

// Invented but entirely plausible notes. None of these were ever enumerated anywhere.
check(TranscriptCleaning.isOnlyNoise("(wind blowing through the trees)"), "an unlisted wind note")
check(TranscriptCleaning.isOnlyNoise("(door creaks)"), "an unlisted door note")
check(TranscriptCleaning.isOnlyNoise("(a dog barking somewhere far away)"), "an unlisted dog note")
check(TranscriptCleaning.isOnlyNoise("(upbeat electronic dance music playing)"), "a long music note")
check(TranscriptCleaning.isOnlyNoise("[ambient hum]"), "an unlisted note in brackets")
check(TranscriptCleaning.isOnlyNoise("*sighs heavily*"), "an unlisted note in asterisks")
check(TranscriptCleaning.isOnlyNoise("(רעש רקע)"), "a note the model wrote in Hebrew")

// Mixed transcripts keep every real word.
check(TranscriptCleaning.clean("Send the deck. [BLANK_AUDIO]") == "Send the deck.",
      "real words survive a trailing note")
check(TranscriptCleaning.clean("[MUSIC] Ship it on Friday [BLANK_AUDIO]") == "Ship it on Friday",
      "notes at both ends are removed")
check(TranscriptCleaning.clean("Ask him [INAUDIBLE] about the price [NOISE] today")
      == "Ask him about the price today", "several notes in one line are all removed")
check(TranscriptCleaning.clean("(people chattering) Can you send me the report tomorrow?")
      == "Can you send me the report tomorrow?", "a leading note does not eat the sentence")
check(TranscriptCleaning.clean("Let us ship on Monday.\n(gentle music)\nAnd tell the team.")
      == "Let us ship on Monday.\nAnd tell the team.", "a note on its own line takes the line with it")

// A parenthetical inside a real sentence goes too. Deliberate: to get brackets on
// purpose you say the punctuation out loud, and the model writes those as words. So a
// bracket in the output came from the model, not from the speaker.
check(TranscriptCleaning.clean("Call it (the new one) tomorrow") == "Call it tomorrow",
      "a parenthetical inside a sentence is dropped with the rest")
check(TranscriptCleaning.clean("Put it in brackets like [this]") == "Put it in brackets like",
      "brackets mid-sentence are dropped too, and the setting is the way out")
check(TranscriptCleaning.clean("(see the music section of the quarterly report)") == "",
      "even a long aside goes, because the model wrote the brackets")

// Musical notes go wherever they are, paired or not.
check(TranscriptCleaning.clean("♪ La la la ♪") == "",
      "a lyric between musical notes goes with them: it is music, not dictation")
check(TranscriptCleaning.clean("♪") == "", "one bare musical note leaves nothing")
check(TranscriptCleaning.clean("Ship it ♪ today") == "Ship it today",
      "a stray musical note mid-sentence goes without eating the words")
check(TranscriptCleaning.clean("♫ Ship it ♬") == "", "the other musical note shapes count too")
check(TranscriptCleaning.clean("Ship it♪today") == "Ship it today",
      "a note with no spaces around it does not glue the words together")

// Spacing and leftover punctuation are tidied up.
check(TranscriptCleaning.clean("Send it [BLANK_AUDIO], please") == "Send it, please",
      "no space is left in front of a comma")
check(TranscriptCleaning.clean("   already clean   ") == "already clean",
      "nothing to remove, just trimmed")
check(TranscriptCleaning.clean("Ship it.\n(gentle music).") == "Ship it.",
      "a line left holding only punctuation is dropped")

// A transcript that was only notes ends up empty, which the app treats as silence.
check(TranscriptCleaning.clean("[BLANK_AUDIO]\n(people chattering)\n♪♪") == "",
      "several notes and nothing else leave nothing at all")

// With the setting off, nothing is removed at all.
check(TranscriptCleaning.clean("(people chattering) hello", removeSoundDescriptions: false)
      == "(people chattering) hello", "the setting turns the whole rule off")

// Unbalanced brackets are left alone: a greedy match would swallow real words.
check(TranscriptCleaning.clean("The cost is (about ten") == "The cost is (about ten",
      "an unclosed bracket is not a note")

// --- ChunkedTranscription ---
check(ChunkedTranscription.join(["one", "two"]) == "one two", "pieces join with one space")
check(ChunkedTranscription.join(["one", "  ", "two"]) == "one two", "an empty piece is skipped")
check(ChunkedTranscription.join([" padded ", "next"]) == "padded next", "pieces are trimmed first")
check(ChunkedTranscription.join([]) == "", "no pieces, no text")
check(ChunkedTranscription.secondsLeft(chunksDone: 0, chunkCount: 4, elapsedSeconds: 3) == nil,
      "no guess before the first piece is done")
check(ChunkedTranscription.secondsLeft(chunksDone: 2, chunkCount: 4, elapsedSeconds: 10) == 10,
      "half done in ten seconds means about ten seconds left")
check(ChunkedTranscription.secondsLeft(chunksDone: 4, chunkCount: 4, elapsedSeconds: 10) == nil,
      "nothing left when every piece is done")
check(ChunkedTranscription.progressLine(chunksDone: 0, chunkCount: 3, elapsedSeconds: 0)
      == "Part 1 of 3", "the first line has no estimate yet")
check(ChunkedTranscription.progressLine(chunksDone: 1, chunkCount: 3, elapsedSeconds: 20)
      == "Part 2 of 3, about 40 seconds left", "the estimate comes from the pieces done")

// --- TranscriptFinishing: cleaning runs before the user's word rules ---
let finishingRules = [
    WordReplacement(id: "f1", find: "nivi", replaceWith: "Nivi"),
    WordReplacement(id: "f2", find: "blank", replaceWith: "empty"),
]
check(TranscriptFinishing.finish("nivi ships on Friday", rules: finishingRules)
      == "Nivi ships on Friday", "a word rule is applied to the finished text")
check(TranscriptFinishing.finish("[BLANK_AUDIO] nivi ships", rules: finishingRules)
      == "Nivi ships", "the model's note is gone before any rule can touch it")
check(TranscriptFinishing.finish("send it [BLANK_AUDIO] now", rules: [
          WordReplacement(id: "f3", find: "it now", replaceWith: "it today", matchWholeWord: false)])
      == "send it today", "a rule matches across the gap a removed note left")
check(TranscriptFinishing.finish("[BLANK_AUDIO]", rules: finishingRules) == "",
      "a transcript that was only a note still ends up empty")
check(TranscriptFinishing.finish("keep this", rules: []) == "keep this", "no rules, just cleaning")
check(TranscriptFinishing.finish("(people chattering) nivi ships", rules: finishingRules,
                                 removeSoundDescriptions: false)
      == "(people chattering) Nivi ships", "finishing passes the setting straight through")

// --- MicrophonePriority ---
check(MicrophonePriority.firstAvailable(order: ["airpods", "builtin"],
                                        available: ["builtin"]) == "builtin",
      "the first choice is skipped when it is not plugged in")
check(MicrophonePriority.firstAvailable(order: ["airpods", "builtin"],
                                        available: ["builtin", "airpods"]) == "airpods",
      "the first choice wins when it is there")
check(MicrophonePriority.firstAvailable(order: [], available: ["builtin"]) == nil,
      "an empty list means use the system default")
check(MicrophonePriority.firstAvailable(order: ["gone"], available: ["builtin"]) == nil,
      "nothing on the list is connected, so use the system default")
check(MicrophonePriority.listing(order: ["airpods"], available: ["builtin", "airpods"])
      == ["airpods", "builtin"], "a new device shows up under the saved order")
check(MicrophonePriority.listing(order: ["airpods", "airpods"], available: [])
      == ["airpods"], "a duplicate saved id is only listed once")
check(MicrophonePriority.decode(json: MicrophonePriority.encode(["a", "b"])) == ["a", "b"],
      "the saved order survives a round trip")
check(MicrophonePriority.decode(json: "") == [], "nothing saved yet reads as an empty list")

// --- DurationFormatting.clock, the counter on the recording panel ---
check(DurationFormatting.clock(0) == "0:00", "a recording starts at zero")
check(DurationFormatting.clock(-3) == "0:00", "a clock that has not started reads zero")
check(DurationFormatting.clock(0.9) == "0:00", "part of a second is not counted yet")
check(DurationFormatting.clock(7) == "0:07", "seconds keep a leading zero")
check(DurationFormatting.clock(59) == "0:59", "the last second before a minute")
check(DurationFormatting.clock(60) == "1:00", "one minute")
check(DurationFormatting.clock(83) == "1:23", "a minute and some seconds")
check(DurationFormatting.clock(599) == "9:59", "the last second before ten minutes")
check(DurationFormatting.clock(600) == "10:00", "ten minutes")
check(DurationFormatting.clock(725) == "12:05", "minutes past ten stay two digits")
check(DurationFormatting.clock(3599) == "59:59", "the last second before an hour has no hours part")
check(DurationFormatting.clock(3600) == "1:00:00", "an hour is where hours appear")
check(DurationFormatting.clock(3849) == "1:04:09", "an hour and change")
check(DurationFormatting.clock(36000) == "10:00:00", "ten hours")

// --- TypedNumber, the number boxes in Preferences ---
check(TypedNumber.read("7", in: 1...30) == 7, "a plain number is taken as it is")
check(TypedNumber.read("  12 ", in: 1...30) == 12, "spaces around the number are ignored")
check(TypedNumber.read("999", in: 1...30) == 30, "too high is pulled down to the top of the range")
check(TypedNumber.read("0", in: 1...30) == 1, "too low is pulled up to the bottom of the range")
check(TypedNumber.read("-5", in: 0...30) == 0, "a negative number is pulled up too")
check(TypedNumber.read("abc", in: 1...30) == nil, "letters are refused")
check(TypedNumber.read("", in: 1...30) == nil, "an empty box is refused")
check(TypedNumber.read("   ", in: 1...30) == nil, "spaces alone are refused")
check(TypedNumber.read("3.7", in: 1...30) == nil, "a decimal point is refused")
check(TypedNumber.read("12ms", in: 1...30) == nil, "a number with a unit stuck to it is refused")

if failures == 0 { print("ALL CORE CHECKS PASSED") } else { print("\(failures) FAILURES"); exit(1) }
