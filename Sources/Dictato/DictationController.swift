import AppKit
import DictatoCore

@MainActor
final class DictationController {
    private var machine = DictationStateMachine()
    private var settings = Settings()

    private let menuBar = MenuBarController()
    private let overlayModel = OverlayModel()
    private lazy var overlayPanel = OverlayPanel(model: overlayModel)
    private lazy var notchPanel = NotchOverlayPanel(model: overlayModel)
    private let recorder = AudioRecorder()
    private let inserter = TextInserter()
    let modelStore: ModelStore
    private lazy var recognizerCache = RecognizerCache(capacity: settings.recognizerCacheCapacity)
    /// Shares the recognizer cache so previewing a model costs no extra memory.
    private lazy var modelTester = ModelTester(cache: recognizerCache, modelStore: modelStore)

    let profileStore: ProfileStore
    private let router: HotkeyRouter
    private var activeProfileID: String?

    private var recordingStarted: Date?
    /// The app that was in front when the recording started, saved for the history entry.
    private var frontAppName: String?
    private var recordingTimer: Timer?
    private var idleUnloadTimer: Timer?
    private var streamer: StreamingTranscriber?
    /// Exactly what in-app-live has already typed into the user's document. The
    /// append-only invariant is enforced against this text, so it must be reset for
    /// every recording rather than left to a later path to clear.
    private var typedText = ""
    /// Identifies the current recording. Async work started for one recording must not
    /// act on a later one: `state == .recording` cannot tell two recordings apart.
    private var recordingGeneration = 0

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

        Log.info("Permissions — Accessibility: \(PermissionManager.accessibilityGranted), InputMonitoring: \(PermissionManager.inputMonitoringGranted)")
        if !PermissionManager.accessibilityGranted {
            PermissionManager.promptForAccessibility()
        }
        if !PermissionManager.inputMonitoringGranted {
            // Esc-to-cancel relies on a global keyDown monitor, which macOS gates behind
            // Input Monitoring (separate from Accessibility). Prompt AND open the pane so
            // the toggle is one click away — the IOHID prompt alone is easy to miss.
            PermissionManager.requestInputMonitoring()
            PermissionManager.openInputMonitoringSettings()
            Log.info("Input Monitoring not granted — opened settings pane for Esc-to-cancel")
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
        modelTester.isDictationBusy = { [weak self] in self?.machine.state == .recording }
        PreferencesWindow.configure(store: modelStore, profileStore: profileStore, tester: modelTester)
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
        // Invalidate any async work still in flight for a previous recording, and clear
        // the append-only bookkeeping unconditionally: it must never carry over from a
        // recording whose final pass failed or was abandoned.
        recordingGeneration &+= 1
        let generation = recordingGeneration
        typedText = ""
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
            frontAppName = front?.localizedName
            overlayModel.setTarget(name: front?.localizedName, icon: front?.icon)
            let profile = profileStore.set.profile(id: activeProfileID ?? profileStore.set.primaryID)
            overlayModel.languageCode = profile?.language ?? "he"
            router.beginRecording(profileID: profile?.id ?? profileStore.set.primaryID)
            let mouse = NSEvent.mouseLocation
            let activeScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            overlayPanel.preferredScreen = activeScreen
            notchPanel.preferredScreen = activeScreen
            transition(.startRequested)
            if settings.playSounds { SoundPlayer.playStart() }
            if let profile, profile.mode.streamsDuringRecording {
                startStreaming(for: profile, generation: generation)
            }
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

    private func startStreaming(for profile: DictationProfile, generation: Int) {
        overlayModel.liveText = ""
        Task { [weak self] in
            guard let self,
                  let model = self.modelStore.catalog.model(id: profile.modelID),
                  let recognizer = try? await self.recognizerCache.recognizer(
                      id: model.id, modelPath: self.modelStore.installedURL(for: model))
            else {
                // The mode is unchanged, so the final pass still inserts per the profile's
                // mode — only the live preview is missing for this recording.
                Log.error("Streaming preview unavailable; will insert the full text at stop")
                return
            }
            // Loading a cold model takes ~1s, in which the user can stop this recording and
            // start another. `state == .recording` cannot tell the two apart, so without the
            // generation check this streamer would attach to the *new* recording — typing
            // the old profile's transcript into the document during what may even be a batch
            // recording, and orphaning a streamer that stop() can no longer reach.
            guard generation == self.recordingGeneration,
                  case .recording = self.machine.state,
                  self.streamer == nil else {
                Log.info("Discarding streaming setup for a superseded recording")
                return
            }
            let streamer = StreamingTranscriber(
                recognizer: recognizer,
                language: profile.language,
                sampleProvider: { [weak self] in self?.recorder.currentSamples() ?? [] },
                intervalMs: self.settings.streamingIntervalMs,
                windowSeconds: self.settings.streamingWindowSeconds,
                onUpdate: { [weak self] update in
                    self?.handleStreamingUpdate(update, mode: profile.mode, generation: generation)
                })
            Log.info("Streaming: profile \(profile.id), model \(model.id), language \(profile.language)")
            self.streamer = streamer
            streamer.start()
        }
    }

    private func handleStreamingUpdate(_ update: StreamingUpdate, mode: InsertionMode, generation: Int) {
        guard generation == recordingGeneration, case .recording = machine.state else { return }
        // The live passes produce the same [BLANK_AUDIO] style notes as the final one, so
        // clean them here too. Otherwise a pause mid-sentence types a note into the
        // document, and nothing later can take it back out.
        let fullText = TranscriptCleaning.clean(update.fullText)
        switch mode {
        case .overlayLive:
            overlayModel.liveText = fullText
        case .inAppLive:
            overlayModel.liveText = fullText
            // "Copy only" means never write into the app. Typing as the user speaks would
            // break that promise in a way nothing later can undo, so a copy-only profile
            // shows the preview and keeps the text for the clipboard instead.
            if !settings.copyOnly { typeAppendOnly(TranscriptCleaning.clean(update.stableText)) }
        case .batch:
            break
        case .batchFastFinish:
            // Deliberately silent. This mode streams only to shorten the wait at the end,
            // so the overlay keeps showing the ordinary recording card and nothing reaches
            // the user's app until the finished text is inserted in one piece.
            break
        }
    }

    /// Types only the part of `text` that isn't in the document yet. Append-only: if the
    /// new text disagrees with what we typed, we still only ever add. Rewriting the
    /// user's document would be worse than an imperfect seam.
    private func typeAppendOnly(_ text: String) {
        let tail = appendOnlyTail(alreadyTyped: typedText, fullText: text)
        guard !tail.isEmpty else { return }
        inserter.typeUnicode(tail)
        typedText += tail
    }

    private func stopAndTranscribe() {
        stopTimer()
        // Keep what streaming already resolved: the frozen prefix needs no re-transcription,
        // so the final pass only has to cover the tail the window never froze.
        let streamedTailStart = streamer?.windowStartSample ?? 0
        let frozenText = streamer?.frozenText ?? ""
        streamer?.stop()
        streamer = nil
        let samples = recorder.stop()
        if settings.playSounds { SoundPlayer.playStop() }
        // Resolve the profile BEFORE transitioning: leaving .recording clears
        // activeProfileID, so the async pass below would fall back to the primary
        // profile and transcribe with the wrong model and language — which is why a
        // non-primary English profile produced Hebrew from the final pass.
        let activeProfile = profileStore.set.profile(id: activeProfileID ?? profileStore.set.primaryID)
        transition(.stopRequested)
        Log.info("Recording stopped (\(String(format: "%.1f", Double(samples.count) / AudioRecorder.sampleRate))s)")
        updateOverlay()
        Task {
            guard let profile = activeProfile,
                  let model = modelStore.catalog.model(id: profile.modelID) else {
                finishWithError("No model"); return
            }
            Log.info("Final pass: profile \(profile.id), model \(model.id), language \(profile.language)")
            do {
                let recognizer = try await recognizerCache.recognizer(
                    id: model.id, modelPath: modelStore.installedURL(for: model))
                let inferenceStart = Date()
                let text: String
                if streamedTailStart > 0, samples.count > streamedTailStart {
                    // Re-transcribe only the un-frozen tail, at full context for quality.
                    // Bounding this is what keeps stopping fast after a long dictation; the
                    // cost is that frozen text never gets a whole-buffer correction.
                    let tail = Array(samples[streamedTailStart...])
                    let tailText = try await recognizer.transcribe(samples: tail, language: profile.language)
                    // No overlap to reconcile: `frozenText` is exactly the transcript for
                    // [0, streamedTailStart) and the tail pass covers [streamedTailStart, end),
                    // so the two partition the recording. Plain concatenation is the whole join.
                    if frozenText.isEmpty {
                        text = tailText
                    } else if tailText.isEmpty {
                        text = frozenText
                    } else {
                        text = frozenText + " " + tailText
                    }
                } else {
                    text = try await recognizer.transcribe(samples: samples, language: profile.language)
                }
                Log.info("Inference completed in \(String(format: "%.2f", -inferenceStart.timeIntervalSinceNow))s")
                // Whisper writes a note such as [BLANK_AUDIO] when it hears no speech.
                // Those notes are not words anyone said, so they are dropped before the
                // text goes anywhere. If nothing real is left, this counts as silence.
                let cleanedText = TranscriptCleaning.clean(text)
                guard !cleanedText.isEmpty else {
                    finishWithError("No speech detected")
                    return
                }
                transition(.transcriptionSucceeded)
                // Save it before inserting. The write is queued onto a background queue,
                // so it costs the paste nothing, and a failed save can never stop the
                // text reaching the user's app.
                HistoryStore.shared.record(
                    text: cleanedText,
                    durationSeconds: Double(samples.count) / AudioRecorder.sampleRate,
                    source: .dictation,
                    modelID: model.id,
                    language: profile.language,
                    profileID: profile.id,
                    sourceName: frontAppName)
                switch profile.mode {
                case .batch, .batchFastFinish, .overlayLive:
                    inserter.insert(cleanedText,
                                    autoPaste: settings.autoPaste,
                                    copyOnly: settings.copyOnly,
                                    excludeFromHistory: settings.excludeFromClipboardHistory)
                case .inAppLive:
                    if settings.copyOnly {
                        // Nothing was typed during the recording either, so the document is
                        // untouched and the whole transcript goes to the clipboard.
                        inserter.insert(cleanedText,
                                        autoPaste: settings.autoPaste,
                                        copyOnly: true,
                                        excludeFromHistory: settings.excludeFromClipboardHistory)
                    } else {
                        // Type only what streaming hasn't already typed. The final pass
                        // re-punctuates and re-capitalizes words already in the document, so
                        // the seam is found by word, not by character offset.
                        typeAppendOnly(cleanedText)
                    }
                }
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
        streamer?.stop()
        streamer = nil
        typedText = ""
        overlayModel.liveText = ""
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

    /// Routes to whichever recording display the user picked. Both panels share one
    /// model, so only the presentation differs; hiding both on the way out avoids
    /// leaving the other style on screen if the setting changed mid-session.
    private func showOverlayPanel() {
        switch settings.recordingDisplay {
        case .panel:
            notchPanel.hide()
            overlayPanel.show()
        case .notch:
            overlayPanel.hide()
            notchPanel.show()
        }
    }

    private func hideOverlayPanels() {
        overlayPanel.hide()
        notchPanel.hide()
    }

    private func updateOverlay() {
        guard settings.showOverlay else { return }
        switch machine.state {
        case .recording:
            if case .recording = overlayModel.phase {} else {
                overlayModel.phase = .recording(elapsed: 0)
            }
            showOverlayPanel()
        case .transcribing, .inserting:
            // Clear the preview as soon as recording ends: the card sizes itself from
            // liveText, so leaving it set keeps the processing card oversized.
            overlayModel.liveText = ""
            overlayModel.phase = .processing
            showOverlayPanel()
        case .error(let message):
            overlayModel.liveText = ""
            overlayModel.phase = .error(message)
            showOverlayPanel()
        case .idle, .loadingModel:
            overlayModel.liveText = ""
            overlayModel.phase = .hidden
            hideOverlayPanels()
        }
    }

    private func finishWithError(_ message: String) {
        // The recording is over; nothing more will be appended for it.
        typedText = ""
        transition(.transcriptionFailed(message))
        scheduleErrorDismiss(after: 1.5)
    }

    private func showTransientError(_ message: String) {
        // This resets the state machine out of .recording without going through
        // stopAndTranscribe/cancelRecording, so tear the streamer down here too —
        // otherwise it is orphaned and `streamer == nil` wedges live preview off for
        // the rest of the process.
        streamer?.stop()
        streamer = nil
        typedText = ""
        machine = DictationStateMachine()
        machine.handle(.modelFailed(message))  // reuse error state
        menuBar.update(state: machine.state)
        overlayModel.phase = .error(message)
        showOverlayPanel()
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
