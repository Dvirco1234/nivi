import Foundation

public enum DictationState: Equatable {
    case loadingModel
    case idle
    case recording
    case transcribing
    case inserting
    case error(String)
}

public enum DictationEvent: Equatable {
    case modelLoaded
    case modelFailed(String)
    case startRequested
    case stopRequested
    case cancelRequested
    case transcriptionSucceeded
    case transcriptionFailed(String)
    case insertionCompleted
    case errorDismissed
}

public struct DictationStateMachine {
    public private(set) var state: DictationState = .loadingModel

    public init() {}

    /// Applies the event if valid for the current state. Returns whether a transition occurred.
    @discardableResult
    public mutating func handle(_ event: DictationEvent) -> Bool {
        switch (state, event) {
        case (.loadingModel, .modelLoaded):
            state = .idle
        case (_, .modelFailed(let message)):
            state = .error(message)
        case (.idle, .startRequested):
            state = .recording
        case (.recording, .stopRequested):
            state = .transcribing
        case (.recording, .cancelRequested):
            state = .idle
        case (.transcribing, .transcriptionSucceeded):
            state = .inserting
        case (.transcribing, .transcriptionFailed(let message)):
            state = .error(message)
        case (.inserting, .insertionCompleted):
            state = .idle
        case (.error, .errorDismissed):
            state = .idle
        default:
            return false
        }
        return true
    }
}
