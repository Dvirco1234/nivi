import SwiftUI
import DictatoCore

/// Try one model without leaving Preferences: record a clip, see what it produces.
struct ModelTestSheet: View {
    let model: ManagedModel
    @ObservedObject var tester: ModelTester
    let onClose: () -> Void

    /// Presets are single-language; multilingual ones are tested on auto-detect.
    private var language: String { model.defaultLanguage }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Test \(model.displayName)").font(.headline)
                    Text("Record a few words and see what this model makes of them. Nothing is pasted anywhere.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title3) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 10) {
                Button(action: toggleRecording) {
                    Label(tester.isRecording ? "Stop" : "Start recording",
                          systemImage: tester.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(tester.isTranscribing)

                if tester.isTranscribing {
                    ProgressView().controlSize(.small)
                    Text("Transcribing…").font(.caption).foregroundStyle(.secondary)
                } else if tester.isRecording {
                    Text("Listening…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Label(model.languageLabel, systemImage: "globe")
                    .font(.caption).foregroundStyle(.secondary)
            }

            ScrollView {
                Text(tester.transcript.isEmpty ? "Transcription appears here." : tester.transcript)
                    .font(.system(size: 13))
                    .foregroundStyle(tester.transcript.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 130)
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.08), lineWidth: 1))

            if let error = tester.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func toggleRecording() {
        if tester.isRecording {
            tester.stopAndTranscribe(model: model, language: language)
        } else {
            tester.start()
        }
    }

    private func close() {
        tester.cancel()
        onClose()
    }
}
