import SwiftUI
import AppKit
import NiviCore

enum PrefSection: String, CaseIterable, Identifiable {
    case general = "General"
    case models = "Dictation Models"
    case profiles = "Profiles"
    case hotkeys = "Hotkeys"
    case speech = "Speech"
    case transcribeFile = "Transcribe File"
    case history = "History"
    case layout = "Layout"
    case debug = "Debug"
    var id: String { rawValue }

    /// The tabs an ordinary user sees. Layout and Debug are tools for whoever builds
    /// the app, so they are absent from the released build entirely rather than
    /// disabled — see DeveloperMode.
    static var visibleCases: [PrefSection] {
        DeveloperMode.isOn ? allCases : allCases.filter { $0 != .layout && $0 != .debug }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .models: return "cpu"
        case .profiles: return "person.crop.rectangle.stack"
        case .hotkeys: return "keyboard"
        case .speech: return "waveform"
        case .transcribeFile: return "doc.badge.arrow.up"
        case .history: return "clock.arrow.circlepath"
        case .layout: return "ruler"
        case .debug: return "ladybug"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: ModelStore
    @ObservedObject var profileStore: ProfileStore
    @ObservedObject var tester: ModelTester
    @ObservedObject var fileTranscription: FileTranscriptionService
    @ObservedObject private var tuning = UITuning.Store.shared
    @ObservedObject private var chrome = PreferencesWindowChrome.shared
    @State private var section: PrefSection = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        // The window itself is clear so it can draw rounded corners, so this view owns the
        // background. Without it the desktop shows straight through the whole window.
        .background(windowBackground)
        // Same radius the window rounds itself to, otherwise square corners poke out past
        // the window's mask. It goes to 0 in fullscreen, along with the window.
        .clipShape(RoundedRectangle(cornerRadius: chrome.cornerRadius))
        .ignoresSafeArea(.all)   // draw under the transparent titlebar so the sidebar hosts the traffic lights
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader
            tabs
            Spacer(minLength: 0)
            versionFooter
        }
        .frame(width: UITuning.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(sidebarBackground)
        .clipShape(RoundedRectangle(cornerRadius: UITuning.sidebarCorner))
        .overlay(RoundedRectangle(cornerRadius: UITuning.sidebarCorner).strokeBorder(.white.opacity(0.07), lineWidth: 1))
        .padding(UITuning.sidebarInset)
    }

    /// The nine tabs, drawn by hand instead of by a `List`.
    ///
    /// A sidebar `List` paints its own selection, a solid accent-filled row, and that
    /// highlight can only be fought with, not replaced. The set of tabs is fixed and
    /// nothing here needs scrolling, reordering or editing, so there is no list
    /// behaviour to lose. Arrow-key moves, the one thing the `List` did give us, are
    /// handled below.
    private var tabs: some View {
        SidebarTabList(selection: $section)
            .focusable()
            // The focus ring would draw a box around all the tabs at once, which says
            // nothing useful. The blue tab already shows where you are.
            .focusEffectDisabled()
            .onMoveCommand(perform: moveSelection)
    }

    /// Up and down arrows walk the tabs, stopping at the ends rather than wrapping,
    /// which is how a macOS sidebar behaves.
    private func moveSelection(_ direction: MoveCommandDirection) {
        let all = PrefSection.visibleCases
        guard let index = all.firstIndex(of: section) else { return }
        switch direction {
        case .up: section = all[max(0, index - 1)]
        case .down: section = all[min(all.count - 1, index + 1)]
        default: break
        }
    }

    /// An opaque base with a blur on top of it. The blur alone would be `.behindWindow`,
    /// which samples the desktop: on a colourful wallpaper the window picked up patches of
    /// it and looked broken rather than translucent. Painting a solid colour first and
    /// blending `.withinWindow` keeps the native depth but makes the result the same
    /// whatever is behind the window.
    private var windowBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            WindowMaterial(material: .windowBackground, blending: .withinWindow)
        }
    }

    /// The sidebar panel has to read as clearly lighter than the detail pane. The sidebar
    /// material on its own is a subtle effect, so a light tint is laid over it to keep the
    /// two panes apart in both light and dark mode.
    private var sidebarBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            WindowMaterial(material: .sidebar, blending: .withinWindow)
            Color.primary.opacity(0.07)
        }
    }

    /// Which build this is, so a bug report can name it. Text only: the sidebar's
    /// material behind it already draws the background.
    private var versionFooter: some View {
        Text(Self.versionString)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(10)
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "v\(short) (\(build))"
    }

    private var brandHeader: some View {
        HStack(spacing: 8) {
            if let img = LanguageGlyph.image(named: "NiviLogo") {
                Image(nsImage: img).resizable().frame(width: 24, height: 24)
            }
            Text("Nivi").font(.title3.weight(.semibold))
        }
        .padding(.horizontal, UITuning.brandLeading)
        .padding(.top, UITuning.brandTop)     // clear the traffic-light buttons + breathing room above the brand
        .padding(.bottom, UITuning.brandBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var detail: some View {
        // A tab that is not on the list cannot be reached by clicking, but belt and
        // braces: showing the first visible tab beats showing an empty pane.
        switch PrefSection.visibleCases.contains(section) ? section : .general {
        case .general: GeneralSection()
        case .models: ModelsSection(store: store, profileStore: profileStore, tester: tester)
        case .profiles: ProfilesSection(profileStore: profileStore, modelStore: store)
        case .hotkeys: HotkeysSection(profileStore: profileStore,
                                       openProfiles: { section = .profiles })
        case .speech: SpeechSection()
        case .transcribeFile: TranscribeFileSection(service: fileTranscription,
                                                    modelStore: store,
                                                    profileStore: profileStore)
        case .history: HistorySection(store: HistoryStore.shared)
        case .layout: LayoutTuningSection()
        case .debug: DebugSection()
        }
    }
}

/// The list of tabs down the sidebar. Its own view so the screenshot tool can draw the
/// real thing, which is how the released build is checked for the absence of the
/// developer-only tabs.
struct SidebarTabList: View {
    @Binding var selection: PrefSection

    var body: some View {
        VStack(spacing: UITuning.sidebarRowGap) {
            ForEach(PrefSection.visibleCases) { tab in
                SidebarTab(section: tab, isSelected: tab == selection) { selection = tab }
            }
        }
        .padding(.horizontal, UITuning.sidebarRowInset)
        .padding(.top, UITuning.sidebarRowGap)
    }
}

/// One tab in the sidebar: icon on the left, name beside it.
///
/// Selected means two things at once. The icon and the name turn the accent colour, and
/// a light rounded plate of glass appears behind them. Unselected tabs are grey and carry
/// no background at all, so there is only ever one thing on this list to find.
struct SidebarTab: View {
    let section: PrefSection
    let isSelected: Bool
    let select: () -> Void
    @State private var hovering = false

    /// Fixed width for the icon so every name in the sidebar starts at the same x,
    /// however wide the symbol happens to be.
    private static let iconWidth: CGFloat = 18

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: section.icon)
                .frame(width: Self.iconWidth)
            Text(section.rawValue)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isSelected ? PrefTheme.accent : PrefTheme.iconTint)
        .padding(.horizontal, 10)
        .frame(height: UITuning.sidebarRowHeight)
        .background(plate)
        // The whole row is clickable, not just the words on it.
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var plate: some View {
        let shape = RoundedRectangle(cornerRadius: UITuning.sidebarRowCorner, style: .continuous)
        if isSelected {
            shape.fill(PrefTheme.tabSelectionFill)
                .overlay(shape.fill(PrefTheme.tabSelectionTint))
                .overlay(shape.strokeBorder(PrefTheme.tabSelectionStroke, lineWidth: 1))
        } else if hovering {
            shape.fill(PrefTheme.tabHoverTint)
        }
    }
}

/// A native macOS blurred background. Used instead of a flat colour so the window keeps
/// the depth a real Mac app has, and follows light and dark mode without extra work.
private struct WindowMaterial: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        // Without .active the blur greys out whenever the window loses focus, which reads
        // as the window having gone half-transparent again.
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// Not private so Tools/pref-shots can photograph this page without opening the app.
struct GeneralSection: View {
    private var settings = Settings()
    @State private var appearance = Settings().appearance
    @State private var showInDock = Settings().showInDock
    @State private var showInStatusBar = Settings().showInStatusBar
    @State private var autoPaste = Settings().autoPaste
    @State private var showOverlay = Settings().showOverlay
    @State private var escapeToCancel = Settings().escapeToCancelEnabled
    @State private var playSounds = Settings().playSounds
    @State private var muteWhileRecording = Settings().muteWhileRecording
    @State private var trackpadFeedback = Settings().trackpadFeedback
    @State private var textInputMethod = Settings().textInputMethod
    @State private var copyOnly = Settings().copyOnly
    @State private var excludeHistory = Settings().excludeFromClipboardHistory
    @State private var removeSoundDescriptions = Settings().removeSoundDescriptions
    @State private var display = Settings().recordingDisplay
    @State private var showDictationTimer = Settings().showDictationTimer
    @State private var replacementCount = WordReplacing.decode(json: Settings().wordReplacementsJSON).count
    @State private var showingWordReplacements = false
    @State private var automaticUpdates = UpdateController.shared.automaticallyChecks

    var body: some View {
        if showingWordReplacements {
            WordReplacementsPage {
                showingWordReplacements = false
                replacementCount = WordReplacing.decode(json: settings.wordReplacementsJSON).count
            }
        } else {
            page
        }
    }

    private var page: some View {
        PrefPage(title: "General",
                 description: "Set up how Nivi behaves and where your dictated text goes.") {
            PrefGroup("Interface",
                      footer: "Nivi needs at least one of the Dock icon and the menu bar icon, so you can always reach it.") {
                PrefPickerRow(icon: "circle.lefthalf.filled",
                              "Appearance",
                              selection: $appearance,
                              options: AppAppearance.allCases,
                              label: { $0.displayName })
                    .onChange(of: appearance) {
                        settings.appearance = $0
                        InterfaceSettings.announceChange()
                    }
                PrefToggleRow(icon: "dock.rectangle",
                              "Show in Dock",
                              caption: lastWayIn(isDock: true) ? "This is the only way left to open Nivi, so it stays on." : nil,
                              isOn: $showInDock)
                    .disabled(lastWayIn(isDock: true))
                    .onChange(of: showInDock) {
                        settings.showInDock = $0
                        InterfaceSettings.announceChange()
                    }
                PrefToggleRow(icon: "menubar.arrow.up.rectangle",
                              "Show in the menu bar",
                              caption: lastWayIn(isDock: false) ? "This is the only way left to open Nivi, so it stays on." : nil,
                              isOn: $showInStatusBar)
                    .disabled(lastWayIn(isDock: false))
                    .onChange(of: showInStatusBar) {
                        settings.showInStatusBar = $0
                        InterfaceSettings.announceChange()
                    }
                LaunchAtLoginRow()
            }

            PrefGroup("Updates",
                      footer: "Nivi asks a public web address which version is the newest. Nothing about you is sent. You are always asked before anything is installed.") {
                PrefToggleRow(icon: "arrow.triangle.2.circlepath",
                              "Check for updates automatically",
                              caption: "Once a day, in the background.",
                              isOn: $automaticUpdates)
                    .onChange(of: automaticUpdates) { UpdateController.shared.automaticallyChecks = $0 }
                PrefButtonRow(icon: "arrow.down.circle",
                              "Check for updates now",
                              caption: "Last checked: \(UpdateController.shared.lastCheckDescription)",
                              buttonTitle: "Check Now") {
                    UpdateController.shared.checkForUpdates()
                }
            }

            PrefGroup("Recording display",
                      footer: "Panel floats near the bottom of the screen. Notch hugs the top, and merges with the MacBook notch where there is one.") {
                // No icon here: the thumbnails are the widest control in the window and
                // need the whole row.
                PrefRow(icon: nil,
                        "Recording display",
                        caption: "Choose how the dictation window looks while you speak.") {
                    RecordingDisplayPicker(selection: $display)
                        .onChange(of: display) { settings.recordingDisplay = $0 }
                }
                PrefToggleRow(icon: "timer",
                              "Count the time while I dictate",
                              caption: "The panel shows how long the recording has been running. The notch bar has no room for it.",
                              isOn: $showDictationTimer)
                    .onChange(of: showDictationTimer) { settings.showDictationTimer = $0 }
            }

            PrefGroup("Behavior") {
                PrefToggleRow(icon: "rectangle.on.rectangle",
                              "Show the recording window",
                              isOn: $showOverlay)
                    .onChange(of: showOverlay) { settings.showOverlay = $0 }
                PrefToggleRow(icon: "escape",
                              "Press Esc to cancel a recording",
                              caption: "Change the key in Hotkeys.",
                              isOn: $escapeToCancel)
                    .onChange(of: escapeToCancel) { settings.escapeToCancelEnabled = $0 }
            }

            PrefGroup("Audio and feedback",
                      footer: "Muting stops system sounds and music from ending up in the recording. Nivi saves your volume first and puts it back when the recording ends, even if it is quit in the middle. Trackpad feedback only works on trackpads that support Force Touch.") {
                PrefToggleRow(icon: "speaker.wave.2",
                              "Play a sound when recording starts and stops",
                              isOn: $playSounds)
                    .onChange(of: playSounds) { settings.playSounds = $0 }
                PrefToggleRow(icon: "speaker.slash",
                              "Mute other audio while recording",
                              isOn: $muteWhileRecording)
                    .onChange(of: muteWhileRecording) { settings.muteWhileRecording = $0 }
                PrefToggleRow(icon: "hand.tap",
                              "Vibrate the trackpad when recording starts",
                              isOn: $trackpadFeedback)
                    .onChange(of: trackpadFeedback) { settings.trackpadFeedback = $0 }
            }

            PrefGroup("Text handling",
                      footer: "Pasting is faster. Typing it out is slower but does not touch your clipboard, and works in apps that block paste. Copy only leaves the text on the clipboard for you to paste yourself.") {
                PrefPickerRow(icon: "arrow.down.doc",
                              "How text is inserted",
                              selection: $textInputMethod,
                              options: TextInputMethod.allCases,
                              label: { $0.displayName })
                    .onChange(of: textInputMethod) { settings.textInputMethod = $0 }
                PrefToggleRow(icon: "paperplane",
                              "Put the text in as soon as it is ready",
                              isOn: $autoPaste)
                    .onChange(of: autoPaste) { settings.autoPaste = $0 }
                PrefToggleRow(icon: "doc.on.clipboard",
                              "Copy to the clipboard only, never paste",
                              isOn: $copyOnly)
                    .onChange(of: copyOnly) { settings.copyOnly = $0 }
                PrefToggleRow(icon: "eye.slash",
                              "Keep dictated text out of clipboard history",
                              caption: "Clipboard managers such as Raycast and Maccy skip it.",
                              isOn: $excludeHistory)
                    .onChange(of: excludeHistory) { settings.excludeFromClipboardHistory = $0 }
                PrefToggleRow(icon: "speaker.slash",
                              "Remove sound descriptions such as (music)",
                              caption: "Models write notes like (people chattering) when they hear a sound instead of speech. Nivi drops them so only your words are left.",
                              isOn: $removeSoundDescriptions)
                    .onChange(of: removeSoundDescriptions) { settings.removeSoundDescriptions = $0 }
                PrefDisclosureRow(icon: "text.badge.checkmark",
                                  "Word replacements",
                                  value: replacementCountText) {
                    showingWordReplacements = true
                }
            }

            MicrophonePriorityGroup()
        }
        .navigationTitle("General")
    }

    private var replacementCountText: String {
        replacementCount == 1 ? "1 rule" : "\(replacementCount) rules"
    }

    /// Whether this toggle is the last way into the app. The one that is still on cannot
    /// be turned off, because with both off there is no Dock icon and no menu bar icon
    /// left to open Preferences from.
    private func lastWayIn(isDock: Bool) -> Bool {
        isDock ? (showInDock && !showInStatusBar) : (showInStatusBar && !showInDock)
    }
}

private struct LaunchAtLoginRow: View {
    @State private var on = LoginItem.isEnabled
    var body: some View {
        PrefToggleRow(icon: "power", "Start Nivi when I log in", isOn: $on)
            .onChange(of: on) { LoginItem.set($0); on = LoginItem.isEnabled }
    }
}

private struct HotkeysSection: View {
    @ObservedObject var profileStore: ProfileStore
    let openProfiles: () -> Void
    private var settings = Settings()
    @State private var cancelBinding = Settings().cancelBinding

    init(profileStore: ProfileStore, openProfiles: @escaping () -> Void) {
        self.profileStore = profileStore
        self.openProfiles = openProfiles
    }

    var body: some View {
        PrefPage(title: "Hotkeys",
                 description: "The keys that start, stop and cancel a recording.") {
            if !PermissionManager.inputMonitoringGranted {
                PrefBanner(.warning,
                           icon: "exclamationmark.triangle.fill",
                           title: "Esc to cancel is not working",
                           message: "Give Nivi Input Monitoring access so it can see the Escape key in other apps.",
                           actionTitle: "Open Settings") {
                    PermissionManager.openInputMonitoringSettings()
                }
            }
            PrefGroup("Cancel", footer: "Works in any app while a recording is running.") {
                PrefRow(icon: "escape", "Cancel a recording") {
                    HotkeyMenu(binding: cancelBinding) { newBinding in
                        cancelBinding = newBinding
                        settings.cancelBinding = newBinding
                    }
                    .fixedSize()
                }
            }
            PrefGroup("Dictation hotkeys",
                      footer: "Each profile has its own key. Edit them in Profiles.") {
                ForEach(profileStore.set.profiles) { profile in
                    PrefDisclosureRow(icon: "keyboard",
                                      profile.name.isEmpty ? "Untitled" : profile.name,
                                      value: profile.hotkey.displayString,
                                      action: openProfiles)
                }
            }
        }
        .navigationTitle("Hotkeys")
    }
}

/// Not private so Tools/pref-shots can photograph this page without opening the app.
struct SpeechSection: View {
    private var settings = Settings()
    @State private var cacheCap = Settings().recognizerCacheCapacity
    @State private var idleMinutes = Settings().idleUnloadSeconds / 60
    @State private var streamingInterval = Settings().streamingIntervalMs
    @State private var windowSeconds = Settings().streamingWindowSeconds

    var body: some View {
        PrefPage(title: "Speech",
                 description: "How Nivi loads models and how fast the live preview updates.") {
            PrefGroup("Audio",
                      footer: "Nivi always records at 16 kHz mono, which is what the speech models expect.") {
                PrefValueRow(icon: "waveform", "Sample rate", value: "16 kHz")
            }
            PrefGroup("Memory",
                      footer: "Keeping more models loaded lets you switch instantly, but uses more RAM. Releasing frees about 1.6 GB, and the model reloads in about a second on your next dictation.") {
                PrefStepperRow(icon: "memorychip",
                               "Models kept in memory",
                               value: $cacheCap, in: 1...4)
                    .onChange(of: cacheCap) { settings.recognizerCacheCapacity = $0 }
                PrefStepperRow(icon: "clock.arrow.circlepath",
                               "Release the model after",
                               caption: idleMinutes == 0 ? "Zero means keep it in memory until you quit." : nil,
                               value: $idleMinutes, in: 0...30, unit: "min")
                    .onChange(of: idleMinutes) { settings.idleUnloadSeconds = $0 * 60 }
            }
            PrefGroup("Live preview",
                      footer: "Live modes re-transcribe only the last few seconds each pass, so the preview keeps up however long you speak. A shorter window is faster. A longer one gives the model more context to correct itself.") {
                PrefStepperRow(icon: "timer",
                               "Minimum gap between updates",
                               value: $streamingInterval, in: 500...2000, step: 100, unit: "ms")
                    .onChange(of: streamingInterval) { settings.streamingIntervalMs = $0 }
                PrefStepperRow(icon: "arrow.left.and.right",
                               "Live preview window",
                               value: $windowSeconds, in: 4...30, unit: "s")
                    .onChange(of: windowSeconds) { settings.streamingWindowSeconds = $0 }
            }
        }
        .navigationTitle("Speech")
    }
}

private struct DebugSection: View {
    private var settings = Settings()
    @State private var showInference = Settings().showInferenceTime
    @State private var showDuration = Settings().showAudioDuration
    @State private var verbose = Settings().verboseLogging

    var body: some View {
        PrefPage(title: "Debug",
                 description: "Extra detail for tracking down problems. Leave these off day to day.") {
            PrefGroup("Show extra detail") {
                PrefToggleRow(icon: "stopwatch",
                              "Show how long transcription took",
                              isOn: $showInference)
                    .onChange(of: showInference) { settings.showInferenceTime = $0 }
                PrefToggleRow(icon: "waveform",
                              "Show how long the recording was",
                              isOn: $showDuration)
                    .onChange(of: showDuration) { settings.showAudioDuration = $0 }
                PrefToggleRow(icon: "text.alignleft",
                              "Write verbose logs",
                              isOn: $verbose)
                    .onChange(of: verbose) { settings.verboseLogging = $0 }
            }
            PrefGroup("Logs") {
                PrefButtonRow(icon: "folder",
                              "Open the log folder",
                              buttonTitle: "Open") {
                    NSWorkspace.shared.open(Log.logDirectory)
                }
                PrefValueRow(icon: "doc.text", "Log folder", value: Log.logDirectory.path)
            }
        }
        .navigationTitle("Debug")
    }
}
