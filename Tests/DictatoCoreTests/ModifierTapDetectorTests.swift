import XCTest
@testable import DictatoCore

final class ModifierTapDetectorTests: XCTestCase {
    private var clock: TimeInterval = 0
    private var detector: ModifierTapDetector!
    private var activations = 0

    override func setUp() {
        super.setUp()
        clock = 0
        activations = 0
        detector = ModifierTapDetector(doubleTapWindow: 0.4) { [unowned self] in clock }
        detector.onActivate = { [unowned self] in activations += 1 }
    }

    private func tap(at time: TimeInterval) {
        clock = time
        detector.modifierChanged(down: true)
        detector.modifierChanged(down: false)
    }

    func testDoubleTapWithinWindowActivates() {
        detector.mode = .doubleTap
        tap(at: 0)
        tap(at: 0.3)
        XCTAssertEqual(activations, 1)
    }

    func testDoubleTapOutsideWindowDoesNotActivate() {
        detector.mode = .doubleTap
        tap(at: 0)
        tap(at: 0.5)
        XCTAssertEqual(activations, 0)
    }

    func testThirdTapAfterActivationStartsFresh() {
        detector.mode = .doubleTap
        tap(at: 0)
        tap(at: 0.2)   // activates
        tap(at: 0.3)   // must NOT pair with tap 2
        XCTAssertEqual(activations, 1)
        tap(at: 0.5)   // pairs with tap 3
        XCTAssertEqual(activations, 2)
    }

    func testSingleTapModeActivatesImmediately() {
        detector.mode = .singleTap
        tap(at: 0)
        XCTAssertEqual(activations, 1)
    }

    func testComboKeyDuringHoldIsNotATap() {
        detector.mode = .singleTap
        detector.modifierChanged(down: true)
        detector.otherKeyDown()          // e.g. user pressed ⌘C
        detector.modifierChanged(down: false)
        XCTAssertEqual(activations, 0)
    }

    func testOtherModifierDuringHoldIsNotATap() {
        detector.mode = .doubleTap
        tap(at: 0)
        detector.modifierChanged(down: true)
        detector.otherKeyDown()          // e.g. shift joined
        clock = 0.2
        detector.modifierChanged(down: false)
        XCTAssertEqual(activations, 0)
    }

    func testTypingBetweenTapsResetsPending() {
        detector.mode = .doubleTap
        tap(at: 0)
        detector.otherKeyDown()          // typing while cmd is up
        tap(at: 0.2)
        XCTAssertEqual(activations, 0)
    }

    func testReleaseWithoutPressIsIgnored() {
        detector.mode = .singleTap
        detector.modifierChanged(down: false)
        XCTAssertEqual(activations, 0)
    }
}
