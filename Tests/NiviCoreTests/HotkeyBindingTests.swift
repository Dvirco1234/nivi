import XCTest
@testable import NiviCore

final class HotkeyBindingTests: XCTestCase {
    func testKeyCodes() {
        XCTAssertEqual(ModifierKey.rightCommand.keyCode, 54)
        XCTAssertEqual(ModifierKey.leftCommand.keyCode, 55)
    }
    func testDisplayStrings() {
        XCTAssertEqual(HotkeyBinding.modifierTap(.rightCommand, count: 2).displayString, "⌘⌘ (right)")
        XCTAssertEqual(HotkeyBinding.keyCombo(keyCode: 53, modifiers: 0).displayString, "esc")
    }
    func testJSONRoundTrip() {
        let b = HotkeyBinding.defaultDictate
        XCTAssertEqual(HotkeyBinding.from(json: b.encodedJSON()), b)
    }
}
