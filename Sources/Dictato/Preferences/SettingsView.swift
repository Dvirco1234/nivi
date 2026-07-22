import SwiftUI
import AppKit
import DictatoCore

enum PrefSection: String, CaseIterable, Identifiable {
    case general = "General"
    case models = "Dictation Models"
    case hotkeys = "Hotkeys"
    case speech = "Speech"
    case debug = "Debug"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .models: return "cpu"
        case .hotkeys: return "keyboard"
        case .speech: return "waveform"
        case .debug: return "ladybug"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: ModelStore
    @State private var section: PrefSection = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Section {
                    ForEach(PrefSection.allCases) { s in
                        Label(s.rawValue, systemImage: s.icon).tag(s)
                    }
                } header: {
                    brandHeader
                }
            }
            .navigationSplitViewColumnWidth(210)
        } detail: {
            ScrollView { detail.padding(20).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(minWidth: 460, minHeight: 460)
        }
        .frame(width: 720, height: 500)
    }

    private var brandHeader: some View {
        HStack(spacing: 8) {
            if let url = Bundle.main.url(forResource: "DictatoLogo", withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().frame(width: 26, height: 26)
            }
            Text("Dictato").font(.title3.weight(.semibold))
        }
        .padding(.vertical, 8)
        .textCase(nil)
    }

    @ViewBuilder private var detail: some View {
        switch section {
        case .general: GeneralSection()
        case .models: ModelsSection(store: store)
        case .hotkeys: HotkeysSection()
        case .speech: SpeechSection()
        case .debug: DebugSection()
        }
    }
}

private struct GeneralSection: View {
    private var settings = Settings()
    @State private var autoPaste = Settings().autoPaste
    @State private var showOverlay = Settings().showOverlay
    @State private var playSounds = Settings().playSounds
    @State private var copyOnly = Settings().copyOnly
    @State private var mode = Settings().insertionMode
    @State private var excludeHistory = Settings().excludeFromClipboardHistory

    var body: some View {
        Form {
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
            Picker("Insertion mode", selection: $mode) {
                ForEach(InsertionMode.allCases, id: \.self) { m in
                    Text(m.isImplemented ? m.displayName : "\(m.displayName) — coming soon").tag(m)
                }
            }
            .onChange(of: mode) { newValue in
                settings.insertionMode = newValue.isImplemented ? newValue : .batch
                if !newValue.isImplemented { mode = settings.insertionMode }
            }
            Divider()
            LaunchAtLoginToggle()
        }
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
            HotkeyRecorderView(title: "Dictate", binding: settings.dictateBinding) {
                settings.dictateBinding = $0
            }
            HotkeyRecorderView(title: "Cancel", binding: settings.cancelBinding) {
                settings.cancelBinding = $0
            }
            Text("Changes apply after you quit and reopen Dictato.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct SpeechSection: View {
    private var settings = Settings()
    @State private var cacheCap = Settings().recognizerCacheCapacity
    var body: some View {
        Form {
            LabeledContent("Sample rate", value: "16 kHz")
            Stepper("Models kept in memory: \(cacheCap)", value: $cacheCap, in: 1...4)
                .onChange(of: cacheCap) { settings.recognizerCacheCapacity = $0 }
            Text("Higher keeps more models resident for instant switching (more RAM).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct DebugSection: View {
    private var settings = Settings()
    @State private var showInference = Settings().showInferenceTime
    @State private var showDuration = Settings().showAudioDuration
    @State private var verbose = Settings().verboseLogging
    var body: some View {
        Form {
            Toggle("Show inference time", isOn: $showInference)
                .onChange(of: showInference) { settings.showInferenceTime = $0 }
            Toggle("Show audio duration", isOn: $showDuration)
                .onChange(of: showDuration) { settings.showAudioDuration = $0 }
            Toggle("Verbose logging", isOn: $verbose)
                .onChange(of: verbose) { settings.verboseLogging = $0 }
            Button("Open Logs") { NSWorkspace.shared.open(Log.logDirectory) }
        }
    }
}
