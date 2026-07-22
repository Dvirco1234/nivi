import AppKit
import DictatoCore

@MainActor
final class DictationController {
    private var machine = DictationStateMachine()
    private var settings = Settings()

    private let menuBar = MenuBarController()
    private let overlayModel = OverlayModel()
    private lazy var overlayPanel = OverlayPanel(model: overlayModel)
    private let recorder = AudioRecorder()
    private let inserter = TextInserter()
    private let modelManager = ModelManager()
    private var recognizer: SpeechRecognizer?

    private let detector: ModifierTapDetector
    private let hotkeys: HotkeyMonitor

    private var recordingStarted: Date?
    private var recordingTimer: Timer?

    init() {
        let binding = settings.dictateBinding
        let count: Int = { if case .modifierTap(_, let c) = binding { return c }; return 2 }()
        detector = ModifierTapDetector(
            doubleTapWindow: Double(settings.doubleTapWindowMs) / 1000.0,
            now: { ProcessInfo.processInfo.systemUptime }
        )
        detector.mode = count >= 2 ? .doubleTap : .singleTap
        hotkeys = HotkeyMonitor(detector: detector,
                                dictateBinding: binding,
                                cancelBinding: settings.cancelBinding)
    }

    func start() {
        detector.onActivate = { [weak self] in
            Task { @MainActor in self?.hotkeyActivated() }
        }
        hotkeys.onCancel = { [weak self] in
            Task { @MainActor in self?.cancelRecording() }
        }
        hotkeys.start()
        recorder.onLevel = { [weak self] level in self?.overlayModel.pushLevel(level) }
        overlayModel.onCancel = { [weak self] in
            Task { @MainActor in self?.cancelRecording() }
        }

        if !PermissionManager.accessibilityGranted {
            PermissionManager.promptForAccessibility()
        }
        if !PermissionManager.inputMonitoringGranted {
            PermissionManager.requestInputMonitoring()   // needed for Esc-to-cancel
        }
        loadModel()
    }

    func wireMenu() {
        menuBar.onStartStop = { [weak self] in
            Task { @MainActor in self?.toggleFromMenu() }
        }
        menuBar.onReloadModel = { [weak self] in
            Task { @MainActor in self?.reloadModel() }
        }
        menuBar.setDictateHint(settings.dictateBinding.displayString)
    }

    func toggleFromMenu() {
        hotkeyActivated()
    }

    // MARK: - Model

    private func loadModel() {
        machine = DictationStateMachine()
        menuBar.update(state: machine.state)
        Task {
            do {
                let modelPath = try await modelManager.ensureModel { [weak self] fraction in
                    self?.menuBar.setStatusText(
                        "Downloading model… \(Int(fraction * 100))%")
                }
                let recognizer = WhisperCppRecognizer(modelPath: modelPath)
                try await recognizer.load()
                self.recognizer = recognizer
                transition(.modelLoaded)
            } catch {
                Log.error("Model load failed: \(error.localizedDescription)")
                transition(.modelFailed(error.localizedDescription))
                scheduleErrorDismiss(after: 3)
            }
        }
    }

    private func reloadModel() {
        recognizer?.unload()
        recognizer = nil
        loadModel()
    }

    // MARK: - Recording flow

    private func hotkeyActivated() {
        switch machine.state {
        case .idle:
            startRecording()
        case .recording:
            stopAndTranscribe()
        default:
            break
        }
    }

    private func startRecording() {
        Task {
            guard await PermissionManager.microphoneGranted() else {
                Log.error("Microphone permission denied")
                PermissionManager.openMicrophoneSettings()
                showTransientError("Microphone access denied")
                return
            }
            do {
                try recorder.start()
            } catch {
                Log.error("Recorder start failed: \(error.localizedDescription)")
                showTransientError("Could not start recording")
                return
            }
            let front = NSWorkspace.shared.frontmostApplication
            overlayModel.setTarget(name: front?.localizedName, icon: front?.icon)
            let mouse = NSEvent.mouseLocation
            overlayPanel.preferredScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            transition(.startRequested)
            Log.info("Recording started")
            recordingStarted = Date()
            overlayModel.reset()
            updateOverlay()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.recordingTick() }
            }
        }
    }

    private func recordingTick() {
        guard case .recording = machine.state, let started = recordingStarted else { return }
        let elapsed = Date().timeIntervalSince(started)
        overlayModel.phase = .recording(elapsed: elapsed)
        if Int(elapsed) >= settings.maxRecordingSeconds {
            Log.info("Max recording duration reached, auto-stopping")
            stopAndTranscribe()
        }
    }

    private func stopAndTranscribe() {
        stopTimer()
        let samples = recorder.stop()
        transition(.stopRequested)
        Log.info("Recording stopped (\(String(format: "%.1f", Double(samples.count) / AudioRecorder.sampleRate))s)")
        updateOverlay()
        Task {
            guard let recognizer else {
                finishWithError("Model not loaded")
                return
            }
            do {
                let inferenceStart = Date()
                let text = try await recognizer.transcribe(samples: samples)
                Log.info("Inference completed in \(String(format: "%.2f", -inferenceStart.timeIntervalSinceNow))s")
                guard !text.isEmpty else {
                    finishWithError("No speech detected")
                    return
                }
                transition(.transcriptionSucceeded)
                inserter.insert(text,
                                autoPaste: settings.autoPaste,
                                excludeFromHistory: settings.excludeFromClipboardHistory)
                transition(.insertionCompleted)
            } catch {
                Log.error("Inference failed: \(error.localizedDescription)")
                finishWithError("Could not transcribe")
            }
        }
    }

    private func cancelRecording() {
        guard case .recording = machine.state else { return }
        stopTimer()
        recorder.cancel()
        transition(.cancelRequested)
        Log.info("Recording cancelled")
        updateOverlay()
    }

    // MARK: - State/UI plumbing

    private func transition(_ event: DictationEvent) {
        machine.handle(event)
        menuBar.update(state: machine.state)
        hotkeys.cancelEnabled = machine.state == .recording
        if case .modifierTap(_, let c) = settings.dictateBinding, c >= 2 {
            detector.mode = machine.state == .recording ? .singleTap : .doubleTap
        } else {
            detector.mode = .singleTap
        }
        updateOverlay()
    }

    private func updateOverlay() {
        guard settings.showOverlay else { return }
        switch machine.state {
        case .recording:
            if case .recording = overlayModel.phase {} else {
                overlayModel.phase = .recording(elapsed: 0)
            }
            overlayPanel.show()
        case .transcribing, .inserting:
            overlayModel.phase = .processing
            overlayPanel.show()
        case .error(let message):
            overlayModel.phase = .error(message)
            overlayPanel.show()
        case .idle, .loadingModel:
            overlayModel.phase = .hidden
            overlayPanel.hide()
        }
    }

    private func finishWithError(_ message: String) {
        transition(.transcriptionFailed(message))
        scheduleErrorDismiss(after: 1.5)
    }

    private func showTransientError(_ message: String) {
        machine = DictationStateMachine()
        machine.handle(.modelFailed(message))  // reuse error state
        menuBar.update(state: machine.state)
        overlayModel.phase = .error(message)
        overlayPanel.show()
        scheduleErrorDismiss(after: 1.5)
    }

    private func scheduleErrorDismiss(after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self else { return }
            if case .error = self.machine.state {
                self.transition(.errorDismissed)
            }
        }
    }

    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStarted = nil
    }
}
