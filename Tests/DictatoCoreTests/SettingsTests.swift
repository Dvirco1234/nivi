import XCTest
@testable import DictatoCore

final class SettingsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "com.dvir.dictato.tests")!
        defaults.removePersistentDomain(forName: "com.dvir.dictato.tests")
    }

    func testDefaults() {
        let settings = Settings(defaults: defaults)
        XCTAssertTrue(settings.autoPaste)
        XCTAssertTrue(settings.showOverlay)
        XCTAssertEqual(settings.doubleTapWindowMs, 400)
        XCTAssertEqual(settings.maxRecordingSeconds, 600)
        XCTAssertFalse(settings.verboseLogging)
        XCTAssertNil(settings.modelPathOverride)
    }

    func testWritesPersist() {
        var settings = Settings(defaults: defaults)
        settings.autoPaste = false
        settings.doubleTapWindowMs = 300
        settings.modelPathOverride = "/tmp/model.bin"
        let reread = Settings(defaults: defaults)
        XCTAssertFalse(reread.autoPaste)
        XCTAssertEqual(reread.doubleTapWindowMs, 300)
        XCTAssertEqual(reread.modelPathOverride, "/tmp/model.bin")
    }

    func testNewKeyDefaults() {
        let s = Settings(defaults: defaults)
        XCTAssertEqual(s.insertionMode, .batch)
        XCTAssertFalse(s.playSounds)
        XCTAssertEqual(s.dictateBinding, .defaultDictate)
        XCTAssertEqual(s.cancelBinding, .defaultCancel)
    }

    func testBindingPersists() {
        var s = Settings(defaults: defaults)
        s.dictateBinding = .modifierTap(.leftCommand, count: 2)
        XCTAssertEqual(Settings(defaults: defaults).dictateBinding, .modifierTap(.leftCommand, count: 2))
    }
}
