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
    let modelStore: ModelStore
    private lazy var recognizerCache = RecognizerCache(capacity: settings.recognizerCacheCapacity)

    let profileStore: ProfileStore
    private let router: HotkeyRouter
    private var activeProfileID: String?

    private var recordingStarted: Date?
    private var recordingTimer: Timer?
    private var idleUnloadTimer: Timer?

    init() {
        let store = ModelStore()
        let primaryModel = store.catalog.defaultModel
        profileStore = ProfileStore(defaultModelID: primaryModel?.id,
                                    defaultLanguage: primaryModel?.defaultLanguage ?? "he")
        router = HotkeyRouter(doubleTapWindowMs: settings.doubleTapWindowMs)
        modelStore = store
    }

    func start() {
        router.onActivate = { [weak self] pid in
            Task { @MainActor in self?.hotkeyActivated(profileID: pid) }
        }
        router.onCancel = { [weak self] in
            Task { @MainActor in self?.cancelRecording() }
        }
        router.rebuild(profiles: profileStore.set, cancel: profileStore.cancelBinding)
        router.start()
        syncCatalogDefaultToPrimary()

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
        NotificationCenter.default.addObserver(forName: .dictatoProfilesChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Don't disturb an in-flight recording: rebuilding the router / re-warming the
                // model mid-recording would swap out state under the active session. The next
                // idle transition re-warms normally via scheduleIdleUnload/loadModel, so it's
                // safe to just skip the sync here and let it catch up later.
                guard self.machine.state != .recording else { return }
                self.router.rebuild(profiles: self.profileStore.set, cancel: self.profileStore.cancelBinding)
                self.menuBar.setDictateHint(self.profileStore.set.primary?.hotkey.displayString ?? "")
                self.syncCatalogDefaultToPrimary()
                await self.warmPrimaryModel()
            }
        }
        // Global NSEvent monitors can stop delivering after sleep — re-arm on wake.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Log.info("System woke — re-arming hotkey monitors")
            self.router.stop()
            self.router.start()
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
        menuBar.setDictateHint(profileStore.set.primary?.hotkey.displayString ?? "")
        PreferencesWindow.configure(store: modelStore, profileStore: profileStore)
    }

    func toggleFromMenu() {
        hotkeyActivated(profileID: profileStore.set.primaryID)
    }

    // MARK: - Model

    private func loadModel() {
        machine = DictationStateMachine()
        menuBar.update(state: machine.state)
        Task { await warmPrimaryModel() }
    }

    private func warmPrimaryModel() async {
        guard let profile = profileStore.set.primary,
              let model = modelStore.catalog.model(id: profile.modelID) else {
            transition(.modelFailed("No primary profile model configured"))
            return
        }
        do {
            if !modelStore.isInstalled(model.id) {
                menuBar.setStatusText("Downloading \(model.displayName)…")
                await modelStore.install(model)
                guard modelStore.isInstalled(model.id) else {
                    transition(.modelFailed("Model download failed"))
                    scheduleErrorDismiss(after: 3); return
                }
            }
            _ = try await recognizerCache.recognizer(
                id: model.id, modelPath: modelStore.installedURL(for: model))
            menuBar.setPrimaryLanguage(profile.language)
            transition(.modelLoaded)
        } catch {
            Log.error("Model warm failed: \(error.localizedDescription)")
            transition(.modelFailed(error.localizedDescription))
            scheduleErrorDismiss(after: 3)
        }
    }

    private func reloadModel() {
        Task { await recognizerCache.evictAll(); await warmPrimaryModel() }
    }

    /// The primary profile is the single source of truth for which model is active;
    /// keep the catalog's "default model" following it.
    private func syncCatalogDefaultToPrimary() {
        guard let primaryModelID = profileStore.set.primary?.modelID,
              primaryModelID != modelStore.catalog.defaultModelID else { return }
        modelStore.setDefault(primaryModelID)
    }

    // MARK: - Recording flow

    private func hotkeyActivated(profileID: String) {
        Log.info("Hotkey activated for profile \(profileID) (state: \(machine.state))")
        switch machine.state {
        case .idle:
            activeProfileID = profileID
            startRecording()
        case .recording:
            stopAndTranscribe()
        default:
            break
        }
    }

    private func startRecording() {
        cancelIdleUnload()
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
            let profile = profileStore.set.profile(id: activeProfileID ?? profileStore.set.primaryID)
            overlayModel.languageCode = profile?.language ?? "he"
            router.beginRecording(profileID: profile?.id ?? profileStore.set.primaryID)
            let mouse = NSEvent.mouseLocation
            overlayPanel.preferredScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            transition(.startRequested)
            if settings.playSounds { SoundPlayer.playStart() }
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
        if settings.playSounds { SoundPlayer.playStop() }
        transition(.stopRequested)
        Log.info("Recording stopped (\(String(format: "%.1f", Double(samples.count) / AudioRecorder.sampleRate))s)")
        updateOverlay()
        Task {
            guard let profile = profileStore.set.profile(id: activeProfileID ?? profileStore.set.primaryID),
                  let model = modelStore.catalog.model(id: profile.modelID) else {
                finishWithError("No model"); return
            }
            do {
                let recognizer = try await recognizerCache.recognizer(
                    id: model.id, modelPath: modelStore.installedURL(for: model))
                let inferenceStart = Date()
                let text = try await recognizer.transcribe(samples: samples, language: profile.language)
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
        router.cancelEnabled = machine.state == .recording
        if machine.state != .recording {
            router.endRecording()
            activeProfileID = nil
        }
        if machine.state == .idle { scheduleIdleUnload() }
        updateOverlay()
    }

    // MARK: - Idle model unload

    private func scheduleIdleUnload() {
        idleUnloadTimer?.invalidate()
        let seconds = settings.idleUnloadSeconds
        guard seconds > 0 else { return }
        idleUnloadTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.machine.state == .idle else { return }
                await self.recognizerCache.evictAll()
                Log.info("Idle \(seconds)s — released model from memory")
            }
        }
    }

    private func cancelIdleUnload() {
        idleUnloadTimer?.invalidate()
        idleUnloadTimer = nil
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
