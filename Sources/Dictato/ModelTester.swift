import Foundation
import DictatoCore

/// Records a short clip and transcribes it with one specific model, so a model can be
/// tried from Preferences without dictating into whatever app happens to be in front.
///
/// It shares the app's `RecognizerCache`, so testing a model the user already dictates
/// with costs nothing — loading a second copy of a 1.6 GB model just to preview it would
/// be absurd. Its own recorder keeps this entirely separate from the dictation state
/// machine, which must not think a real recording is in progress.
@MainActor
final class ModelTester: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var transcript = ""
    @Published private(set) var errorMessage: String?

    private let recorder = AudioRecorder()
    private let cache: RecognizerCache
    private let modelStore: ModelStore
    /// Set by the controller while a real dictation is running, so a test can never
    /// grab the microphone out from under it.
    var isDictationBusy: () -> Bool = { false }

    init(cache: RecognizerCache, modelStore: ModelStore) {
        self.cache = cache
        self.modelStore = modelStore
    }

    func start() {
        guard !isRecording, !isTranscribing else { return }
        guard !isDictationBusy() else {
            errorMessage = "Finish the current dictation first"
            return
        }
        errorMessage = nil
        transcript = ""
        Task {
            guard await PermissionManager.microphoneGranted() else {
                errorMessage = "Microphone access denied"
                return
            }
            do {
                try recorder.start()
                isRecording = true
            } catch {
                errorMessage = "Could not start recording"
            }
        }
    }

    func stopAndTranscribe(model: ManagedModel, language: String) {
        guard isRecording else { return }
        let samples = recorder.stop()
        isRecording = false
        isTranscribing = true
        Task {
            defer { isTranscribing = false }
            do {
                let recognizer = try await cache.recognizer(
                    id: model.id, modelPath: modelStore.installedURL(for: model))
                let raw = try await recognizer.transcribe(samples: samples, language: language)
                // Drop the [BLANK_AUDIO] style notes, so a test on a quiet room shows
                // "No speech detected" rather than the model's note about it.
                let text = TranscriptCleaning.clean(raw)
                transcript = text
                if text.isEmpty { errorMessage = "No speech detected" }
            } catch {
                Log.error("Model test failed: \(error.localizedDescription)")
                errorMessage = "Could not transcribe with this model"
            }
        }
    }

    /// Drops any in-flight recording. Called when the sheet closes so a forgotten test
    /// cannot leave the microphone open.
    func cancel() {
        if isRecording {
            recorder.cancel()
            isRecording = false
        }
        transcript = ""
        errorMessage = nil
    }
}
