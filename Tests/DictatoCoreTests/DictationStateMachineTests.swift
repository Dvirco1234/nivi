import XCTest
@testable import DictatoCore

final class DictationStateMachineTests: XCTestCase {
    func testHappyPath() {
        var machine = DictationStateMachine()
        XCTAssertEqual(machine.state, .loadingModel)
        XCTAssertTrue(machine.handle(.modelLoaded))
        XCTAssertEqual(machine.state, .idle)
        XCTAssertTrue(machine.handle(.startRequested))
        XCTAssertEqual(machine.state, .recording)
        XCTAssertTrue(machine.handle(.stopRequested))
        XCTAssertEqual(machine.state, .transcribing)
        XCTAssertTrue(machine.handle(.transcriptionSucceeded))
        XCTAssertEqual(machine.state, .inserting)
        XCTAssertTrue(machine.handle(.insertionCompleted))
        XCTAssertEqual(machine.state, .idle)
    }

    func testCancelWhileRecordingReturnsToIdle() {
        var machine = DictationStateMachine()
        machine.handle(.modelLoaded)
        machine.handle(.startRequested)
        XCTAssertTrue(machine.handle(.cancelRequested))
        XCTAssertEqual(machine.state, .idle)
    }

    func testFailuresLandInErrorThenIdle() {
        var machine = DictationStateMachine()
        machine.handle(.modelLoaded)
        machine.handle(.startRequested)
        machine.handle(.stopRequested)
        XCTAssertTrue(machine.handle(.transcriptionFailed("boom")))
        XCTAssertEqual(machine.state, .error("boom"))
        XCTAssertTrue(machine.handle(.errorDismissed))
        XCTAssertEqual(machine.state, .idle)
    }

    func testModelFailureIsError() {
        var machine = DictationStateMachine()
        XCTAssertTrue(machine.handle(.modelFailed("no disk")))
        XCTAssertEqual(machine.state, .error("no disk"))
    }

    func testInvalidTransitionsAreRejected() {
        var machine = DictationStateMachine()
        XCTAssertFalse(machine.handle(.startRequested))      // still loading
        XCTAssertEqual(machine.state, .loadingModel)
        machine.handle(.modelLoaded)
        XCTAssertFalse(machine.handle(.stopRequested))       // not recording
        XCTAssertFalse(machine.handle(.transcriptionSucceeded))
        XCTAssertEqual(machine.state, .idle)
        machine.handle(.startRequested)
        XCTAssertFalse(machine.handle(.startRequested))      // already recording
        XCTAssertEqual(machine.state, .recording)
    }
}
