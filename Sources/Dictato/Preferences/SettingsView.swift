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
        .background(WindowMaterial(material: .windowBackground))
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
        }
        .frame(width: UITuning.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(WindowMaterial(material: .sidebar))
        .clipShape(RoundedRectangle(cornerRadius: UITuning.sidebarCorner))
        .overlay(RoundedRectangle(cornerRadius: UITuning.sidebarCorner).strokeBorder(.white.opacity(0.07), lineWidth: 1))
        .padding(UITuning.sidebarInset)
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
        case .hotkeys: HotkeysSection()
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

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        // Without .active the blur greys out whenever the window loses focus, which reads
        // as the window having gone half-transparent again.
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
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
        Form {
            Section {
                Toggle("Auto-paste after transcription", isOn: $autoPaste)
                    .onChange(of: autoPaste) { settings.autoPaste = $0 }
                Toggle("Copy only (never paste)", isOn: $copyOnly)
                    .onChange(of: copyOnly) { settings.copyOnly = $0 }
                Toggle("Keep dictation out of clipboard history", isOn: $excludeHistory)
                    .onChange(of: excludeHistory) { settings.excludeFromClipboardHistory = $0 }
                Toggle("Show overlay", isOn: $showOverlay)
                    .onChange(of: showOverlay) { settings.showOverlay = $0 }
                Toggle("Play sounds", isOn: $playSounds)
                    .onChange(of: playSounds) { settings.playSounds = $0 }
            }
            Section {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recording display").font(.body)
                        Text("Choose how the dictation interface looks.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 16)
                    RecordingDisplayPicker(selection: $display)
                        .onChange(of: display) { settings.recordingDisplay = $0 }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("Panel floats near the bottom of the screen. Notch hugs the top, merging with the MacBook notch where there is one.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LaunchAtLoginToggle()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

private struct LaunchAtLoginToggle: View {
    @State private var on = LoginItem.isEnabled
    var body: some View {
        Toggle("Launch at login", isOn: $on)
            .onChange(of: on) { LoginItem.set($0); on = LoginItem.isEnabled }
    }
}

private struct HotkeysSection: View {
    private var settings = Settings()
    var body: some View {
        Form {
            Section {
                HotkeyRecorderView(title: "Cancel", binding: settings.cancelBinding) {
                    settings.cancelBinding = $0
                }
            } footer: {
                Text("Global cancel key while recording. Dictate hotkeys are set per profile.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
        Form {
            Section {
                LabeledContent("Sample rate", value: "16 kHz")
            }
            Section {
                Stepper("Models kept in memory: \(cacheCap)", value: $cacheCap, in: 1...4)
                    .onChange(of: cacheCap) { settings.recognizerCacheCapacity = $0 }
            } footer: {
                Text("Higher keeps more models resident for instant switching (more RAM).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Stepper(idleMinutes == 0 ? "Release model when idle: Never"
                                         : "Release model after \(idleMinutes) min idle",
                        value: $idleMinutes, in: 0...30)
                    .onChange(of: idleMinutes) { settings.idleUnloadSeconds = $0 * 60 }
            } footer: {
                Text("Frees ~1.6 GB when unused; the model reloads (~1 s) on your next dictation.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Stepper("Minimum gap between live updates: \(streamingInterval) ms",
                        value: $streamingInterval, in: 500...2000, step: 100)
                    .onChange(of: streamingInterval) { settings.streamingIntervalMs = $0 }
                Stepper("Live preview window: \(windowSeconds) s",
                        value: $windowSeconds, in: 4...30, step: 1)
                    .onChange(of: windowSeconds) { settings.streamingWindowSeconds = $0 }
            } footer: {
                Text("Live modes re-transcribe only the last few seconds each pass, so the preview keeps up however long you speak. A shorter window is faster; a longer one gives whisper more context to correct itself.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Speech")
    }
}

private struct DebugSection: View {
    private var settings = Settings()
    @State private var showInference = Settings().showInferenceTime
    @State private var showDuration = Settings().showAudioDuration
    @State private var verbose = Settings().verboseLogging
    var body: some View {
        Form {
            Section {
                Toggle("Show inference time", isOn: $showInference)
                    .onChange(of: showInference) { settings.showInferenceTime = $0 }
                Toggle("Show audio duration", isOn: $showDuration)
                    .onChange(of: showDuration) { settings.showAudioDuration = $0 }
                Toggle("Verbose logging", isOn: $verbose)
                    .onChange(of: verbose) { settings.verboseLogging = $0 }
            }
            Section {
                Button("Open Logs") { NSWorkspace.shared.open(Log.logDirectory) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Debug")
    }
}
