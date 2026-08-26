import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NiviCore

/// The Transcribe a file tab: drop a file in, get the text out, all on this Mac.
struct TranscribeFileSection: View {
    @ObservedObject var service: FileTranscriptionService
    @ObservedObject var modelStore: ModelStore
    @ObservedObject var profileStore: ProfileStore

    private let settings = Settings()
    @State private var chunkMinutes = Settings().fileChunkMinutes
    @State private var isDropTarget = false
    @State private var justCopied = false

    private var installedModels: [ManagedModel] {
        modelStore.catalog.models.filter { $0.isRunnable && modelStore.isInstalled($0.id) }
    }

    private var chosenModel: ManagedModel? {
        installedModels.first { $0.id == service.modelID } ?? installedModels.first
    }

    var body: some View {
        PrefPage(title: "Transcribe a file",
                 description: "Drop an audio or video file here and Nivi turns it into text, all on this Mac.") {
            if case .failed(let title, let message) = service.phase {
                PrefBanner(.danger,
                           icon: "exclamationmark.triangle.fill",
                           title: title,
                           message: message)
            }

            if installedModels.isEmpty {
                PrefGroup {
                    PrefEmptyState(icon: "cpu",
                                   title: "No models yet",
                                   message: "Install a model in Dictation models first, then come back here.")
                }
            } else {
                dropZone
                settingsGroup
                if service.isRunning { progressGroup }
                if !service.transcript.isEmpty && !service.isRunning { resultGroup }
            }
        }
        .navigationTitle("Transcribe File")
        .onAppear(perform: pickStartingModel)
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: 10) {
            Button(action: chooseFile) {
                VStack(spacing: 8) {
                    Image(systemName: "doc.badge.arrow.up")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(isDropTarget ? PrefTheme.accent : Color.secondary)
                    Text("Drop a file here").font(.headline)
                    Text("or click to choose one")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: PrefTheme.dropZoneHeight)
                .contentShape(Rectangle())
                .background(isDropTarget ? PrefTheme.accent.opacity(0.08) : Color.clear,
                            in: RoundedRectangle(cornerRadius: UITuning.cardCorner))
                .overlay(
                    RoundedRectangle(cornerRadius: UITuning.cardCorner)
                        .strokeBorder(isDropTarget ? PrefTheme.accent : PrefTheme.cardStroke,
                                      style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            }
            .buttonStyle(.plain)
            .disabled(service.isRunning)
            .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
                loadDroppedFile(from: providers)
            }
            .accessibilityLabel("Drop an audio or video file here, or click to choose one")

            HStack(spacing: 6) {
                ForEach(TranscribableFormat.displayNames, id: \.self) { name in
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
        }
    }

    // MARK: - Settings

    private var settingsGroup: some View {
        PrefGroup("Settings for this job",
                  footer: "Long files are split into parts so you can watch the progress and stop it. Dictation always comes first: if you start a recording, the file waits for it.") {
            PrefPickerRow(icon: "cpu",
                          "Model",
                          selection: Binding(get: { chosenModel?.id ?? "" },
                                             set: { service.modelID = $0 }),
                          options: installedModels.map(\.id)) { id in
                installedModels.first { $0.id == id }?.displayName ?? id
            }
            PrefPickerRow(icon: "globe",
                          "Language",
                          selection: $service.language,
                          options: ["auto", "en", "he"]) { ProfileStore.languageName($0) }
            PrefStepperRow(icon: "scissors",
                           "Split long files into parts of",
                           value: $chunkMinutes, in: 1...15, unit: "min")
                .onChange(of: chunkMinutes) { settings.fileChunkMinutes = $0 }
        }
    }

    // MARK: - Progress

    private var progressGroup: some View {
        PrefGroup("Working on it") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    ProgressView(value: progressFraction)
                        .progressViewStyle(.linear)
                    Button("Stop") { service.cancel() }
                        .controlSize(.small)
                }
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, UITuning.cardPadding)
            .padding(.vertical, PrefTheme.rowVerticalPadding)
        }
    }

    private var progressFraction: Double {
        switch service.phase {
        case .decoding(let fraction): return fraction * 0.1
        case .transcribing(let done, let total):
            return total > 0 ? 0.1 + 0.9 * Double(done) / Double(total) : 0.1
        case .waitingForDictation, .idle, .failed: return 0
        case .finished: return 1
        }
    }

    private var statusLine: String {
        switch service.phase {
        case .decoding: return "Reading the audio out of \(service.fileName)."
        case .waitingForDictation: return "Waiting for your dictation to finish."
        case .transcribing:
            let line = service.progressLine
            return line.isEmpty ? "Transcribing." : line
        default: return ""
        }
    }

    // MARK: - Result

    private var resultGroup: some View {
        PrefGroup("Result", footer: resultFooter) {
            VStack(alignment: .leading, spacing: 10) {
                if service.stoppedEarly {
                    Text("Stopped early. This is only part of the file.")
                        .font(.caption)
                        .foregroundStyle(PrefTheme.warning)
                }
                ScrollView {
                    Text(service.transcript)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlayScrollers()
                }
                .frame(height: PrefTheme.fileResultHeight)

                HStack(spacing: 8) {
                    Button(justCopied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(service.transcript, forType: .string)
                        justCopied = true
                    }
                    Button("Save as a text file...", action: saveTranscript)
                    Spacer()
                    Button("Clear") {
                        service.clearResult()
                        justCopied = false
                    }
                }
                .controlSize(.small)
            }
            .padding(.horizontal, UITuning.cardPadding)
            .padding(.vertical, PrefTheme.rowVerticalPadding)
        }
    }

    private var resultFooter: String {
        var parts = [service.fileName]
        if service.audioSeconds > 0 { parts.append(DurationFormatting.short(service.audioSeconds)) }
        if service.workSeconds > 0 {
            parts.append("took \(DurationFormatting.short(service.workSeconds))")
        }
        if !service.modelName.isEmpty { parts.append(service.modelName) }
        parts.append("also saved in History")
        return parts.joined(separator: " · ")
    }

    // MARK: - Files in and out

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an audio or video file to transcribe."
        panel.allowedContentTypes = TranscribableFormat.supportedExtensions
            .compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        startJob(with: url)
    }

    private func loadDroppedFile(from providers: [NSItemProvider]) -> Bool {
        guard !service.isRunning, let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in startJob(with: url) }
        }
        return true
    }

    private func startJob(with url: URL) {
        guard let model = chosenModel else {
            Log.error("File transcription: no model to run with")
            return
        }
        Log.info("File transcription starting: \(url.lastPathComponent), model \(model.id), language \(service.language)")
        justCopied = false
        service.start(url: url, model: model, language: service.language,
                      chunkMinutes: chunkMinutes)
    }

    private func saveTranscript() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = (service.fileName as NSString)
            .deletingPathExtension + ".txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try service.transcript.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.error("Could not save the transcript: \(error.localizedDescription)")
        }
    }

    /// Starts on the model and language the user already dictates with, which is the
    /// answer they meant nine times out of ten.
    private func pickStartingModel() {
        guard service.modelID.isEmpty else { return }
        let primary = profileStore.set.primary
        if let primary, installedModels.contains(where: { $0.id == primary.modelID }) {
            service.modelID = primary.modelID
            service.language = primary.language
        } else {
            service.modelID = installedModels.first?.id ?? ""
            service.language = installedModels.first?.defaultLanguage ?? "auto"
        }
        if !["auto", "en", "he"].contains(service.language) { service.language = "auto" }
    }
}
