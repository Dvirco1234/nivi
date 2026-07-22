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

if failures == 0 { print("ALL CORE CHECKS PASSED") } else { print("\(failures) FAILURES"); exit(1) }
