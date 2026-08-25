import SwiftUI
import AppKit
import DictatoCore

enum PrefSection: String, CaseIterable, Identifiable {
    case general = "General"
    case models = "Dictation Models"
    case profiles = "Profiles"
    case hotkeys = "Hotkeys"
    case speech = "Speech"
    case layout = "Layout"
    case debug = "Debug"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .models: return "cpu"
        case .profiles: return "person.crop.rectangle.stack"
        case .hotkeys: return "keyboard"
        case .speech: return "waveform"
        case .layout: return "ruler"
        case .debug: return "ladybug"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: ModelStore
    @ObservedObject var profileStore: ProfileStore
    @ObservedObject var tester: ModelTester
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
            List(selection: $section) {
                ForEach(PrefSection.allCases) { s in
                    Label(s.rawValue, systemImage: s.icon).tag(s)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            versionFooter
        }
        .frame(width: UITuning.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(sidebarBackground)
        .clipShape(RoundedRectangle(cornerRadius: UITuning.sidebarCorner))
        .overlay(RoundedRectangle(cornerRadius: UITuning.sidebarCorner).strokeBorder(.white.opacity(0.07), lineWidth: 1))
        .padding(UITuning.sidebarInset)
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
            if let img = LanguageGlyph.image(named: "DictatoLogo") {
                Image(nsImage: img).resizable().frame(width: 24, height: 24)
            }
            Text("Dictato").font(.title3.weight(.semibold))
        }
        .padding(.horizontal, UITuning.brandLeading)
        .padding(.top, UITuning.brandTop)     // clear the traffic-light buttons + breathing room above the brand
        .padding(.bottom, UITuning.brandBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var detail: some View {
        switch section {
        case .general: GeneralSection()
        case .models: ModelsSection(store: store, profileStore: profileStore, tester: tester)
        case .profiles: ProfilesSection(profileStore: profileStore, modelStore: store)
        case .hotkeys: HotkeysSection(profileStore: profileStore,
                                       openProfiles: { section = .profiles })
        case .speech: SpeechSection()
        case .layout: LayoutTuningSection()
        case .debug: DebugSection()
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

private struct GeneralSection: View {
    private var settings = Settings()
    @State private var autoPaste = Settings().autoPaste
    @State private var showOverlay = Settings().showOverlay
    @State private var playSounds = Settings().playSounds
    @State private var copyOnly = Settings().copyOnly
    @State private var excludeHistory = Settings().excludeFromClipboardHistory
    @State private var display = Settings().recordingDisplay

    var body: some View {
        PrefPage(title: "General",
                 description: "Set up how Dictato behaves and where your dictated text goes.") {
            PrefGroup("Interface") {
                LaunchAtLoginRow()
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
            }

            PrefGroup("Behavior") {
                PrefToggleRow(icon: "rectangle.on.rectangle",
                              "Show the recording window",
                              isOn: $showOverlay)
                    .onChange(of: showOverlay) { settings.showOverlay = $0 }
            }

            PrefGroup("Audio and feedback") {
                PrefToggleRow(icon: "speaker.wave.2",
                              "Play a sound when recording starts and stops",
                              isOn: $playSounds)
                    .onChange(of: playSounds) { settings.playSounds = $0 }
            }

            PrefGroup("Text handling",
                      footer: "Copy only leaves the text on the clipboard for you to paste yourself.") {
                PrefToggleRow(icon: "arrow.down.doc",
                              "Paste the text as soon as it is ready",
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
            }
        }
        .navigationTitle("General")
    }
}

private struct LaunchAtLoginRow: View {
    @State private var on = LoginItem.isEnabled
    var body: some View {
        PrefToggleRow(icon: "power", "Start Dictato when I log in", isOn: $on)
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
                           message: "Give Dictato Input Monitoring access so it can see the Escape key in other apps.",
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

private struct SpeechSection: View {
    private var settings = Settings()
    @State private var cacheCap = Settings().recognizerCacheCapacity
    @State private var idleMinutes = Settings().idleUnloadSeconds / 60
    @State private var streamingInterval = Settings().streamingIntervalMs
    @State private var windowSeconds = Settings().streamingWindowSeconds

    var body: some View {
        PrefPage(title: "Speech",
                 description: "How Dictato loads models and how fast the live preview updates.") {
            PrefGroup("Audio",
                      footer: "Dictato always records at 16 kHz mono, which is what the speech models expect.") {
                PrefValueRow(icon: "waveform", "Sample rate", value: "16 kHz")
            }
            PrefGroup("Memory",
                      footer: "Keeping more models loaded lets you switch instantly, but uses more RAM. Releasing frees about 1.6 GB, and the model reloads in about a second on your next dictation.") {
                PrefStepperRow(icon: "memorychip",
                               "Models kept in memory",
                               value: $cacheCap, in: 1...4) { "\($0)" }
                    .onChange(of: cacheCap) { settings.recognizerCacheCapacity = $0 }
                PrefStepperRow(icon: "clock.arrow.circlepath",
                               "Release the model after",
                               value: $idleMinutes, in: 0...30) { $0 == 0 ? "Never" : "\($0) min" }
                    .onChange(of: idleMinutes) { settings.idleUnloadSeconds = $0 * 60 }
            }
            PrefGroup("Live preview",
                      footer: "Live modes re-transcribe only the last few seconds each pass, so the preview keeps up however long you speak. A shorter window is faster. A longer one gives the model more context to correct itself.") {
                PrefStepperRow(icon: "timer",
                               "Minimum gap between updates",
                               value: $streamingInterval, in: 500...2000, step: 100) { "\($0) ms" }
                    .onChange(of: streamingInterval) { settings.streamingIntervalMs = $0 }
                PrefStepperRow(icon: "arrow.left.and.right",
                               "Live preview window",
                               value: $windowSeconds, in: 4...30) { "\($0) s" }
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
