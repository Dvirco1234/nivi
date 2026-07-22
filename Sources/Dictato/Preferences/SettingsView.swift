import SwiftUI
import AppKit
import DictatoCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            HotkeysTab().tabItem { Label("Hotkeys", systemImage: "keyboard") }
            SpeechTab().tabItem { Label("Speech", systemImage: "waveform") }
            DebugTab().tabItem { Label("Debug", systemImage: "ladybug") }
        }
        .frame(width: 520, height: 380)
        .padding()
    }
}

private struct GeneralTab: View {
    private var settings = Settings()
    @State private var autoPaste = Settings().autoPaste
    @State private var showOverlay = Settings().showOverlay
    @State private var playSounds = Settings().playSounds
    @State private var copyOnly = Settings().copyOnly
    @State private var mode = Settings().insertionMode

    var body: some View {
        Form {
            Toggle("Auto-paste after transcription", isOn: $autoPaste)
                .onChange(of: autoPaste) { settings.autoPaste = $0 }
            Toggle("Copy only (never paste)", isOn: $copyOnly)
                .onChange(of: copyOnly) { settings.copyOnly = $0 }
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

private struct HotkeysTab: View {
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

private struct SpeechTab: View {
    var body: some View {
        Form {
            LabeledContent("Model", value: "ivrit-ai large-v3-turbo")
            LabeledContent("Language", value: "Hebrew (he)")
            LabeledContent("Sample rate", value: "16 kHz")
            Text("More models and languages arrive with streaming mode.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct DebugTab: View {
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
