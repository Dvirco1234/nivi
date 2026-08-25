import SwiftUI
import AppKit
import DictatoCore

struct ModelsSection: View {
    @ObservedObject var store: ModelStore
    @ObservedObject var profileStore: ProfileStore
    @ObservedObject var tester: ModelTester
    @State private var showingAdd = false
    @State private var testingModel: ManagedModel?

    private var modelIDsInUseByProfiles: Set<String> {
        Set(profileStore.set.profiles.map(\.modelID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UITuning.cardSpacing) {
                HStack {
                    Text("Dictation Models").font(.title2.weight(.semibold))
                    Spacer()
                    Button { showingAdd = true } label: { Label("Add model", systemImage: "plus") }
                }
                ForEach(store.catalog.models) { model in
                    ModelCard(model: model,
                              state: store.installStates[model.id] ?? .notInstalled,
                              isDefault: model.id == store.catalog.defaultModelID,
                              isInUseByProfile: modelIDsInUseByProfiles.contains(model.id),
                              onDownload: { Task { await store.install(model) } },
                              onDelete: { store.delete(model.id) },
                              onTest: { testingModel = model })
                }
            }
            .padding(UITuning.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Dictation Models")
        .sheet(isPresented: $showingAdd) {
            AddModelSheet(onAdd: { store.addModel($0); showingAdd = false },
                          onCancel: { showingAdd = false })
        }
        .sheet(item: $testingModel) { model in
            ModelTestSheet(model: model, tester: tester) { testingModel = nil }
        }
    }
}

private struct ModelCard: View {
    let model: ManagedModel
    let state: InstallState
    let isDefault: Bool
    let isInUseByProfile: Bool
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onTest: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(model.displayName).font(.headline)
                if let badge = model.badge {
                    Text(badge).font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.blue.opacity(0.25), in: Capsule())
                }
                Spacer()
                action
            }
            if let summary = model.summary {
                Text(summary).font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                if let a = model.accuracy { dots("Accuracy", a) }
                if let s = model.speed { dots("Speed", s) }
                if let size = model.sizeBytesApprox { meta("shippingbox", byteString(size)) }
                meta("globe", model.languageLabel)
                meta("desktopcomputer", "Local")
            }
            .font(.caption)
        }
        .padding(UITuning.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PrefTheme.cardFill, in: RoundedRectangle(cornerRadius: UITuning.cardCorner))
        .overlay(RoundedRectangle(cornerRadius: UITuning.cardCorner).strokeBorder(
            isDefault ? PrefTheme.accent.opacity(0.6) : PrefTheme.cardStroke, lineWidth: isDefault ? 1.5 : 1))
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var action: some View {
        switch state {
        case .installed:
            HStack(spacing: 8) {
                // Only on hover: the card is otherwise a dense row of metadata, and a
                // permanent extra button competes with Default for attention.
                if hovering {
                    Button(action: onTest) { Label("Test it", systemImage: "mic") }
                        .buttonStyle(.link)
                }
                if isDefault {
                    Label("Default", systemImage: "checkmark.circle.fill").foregroundStyle(.blue)
                }
                Menu {
                    if !isDefault && !isInUseByProfile {
                        Button("Delete", role: .destructive, action: onDelete)
                    } else {
                        Text("In use by a profile")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).frame(width: 28)
                    .help(isInUseByProfile ? "In use by a profile" : "")
            }
        case .downloading(let f):
            ProgressView(value: f).frame(width: 120)
        case .failed(let msg):
            HStack { Text("Failed").foregroundStyle(.red); Button("Retry", action: onDownload) }
                .help(msg)
        case .notInstalled:
            if model.isRunnable {
                Button(action: onDownload) { Label("Download", systemImage: "arrow.down.circle") }
            } else {
                // Listed so the catalog shows what is coming, but not downloadable: no
                // engine here can run it yet, and half a gigabyte that then refuses to
                // load would be worse than an honest label.
                Text("Engine coming soon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Needs the NVIDIA Parakeet engine, which Dictato does not ship yet")
            }
        }
    }

    private func dots(_ label: String, _ n: Int) -> some View {
        HStack(spacing: 3) {
            Text(label)
            ForEach(0..<5, id: \.self) { i in
                Circle().fill(i < n ? Color.primary : Color.primary.opacity(0.25)).frame(width: 5, height: 5)
            }
        }
    }
    private func meta(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).foregroundStyle(.secondary)
    }
    private func byteString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private struct AddModelSheet: View {
    enum Kind: String, CaseIterable, Identifiable {
        case huggingFace = "HuggingFace", url = "Direct URL", local = "Local file"
        var id: String { rawValue }
    }
    @State private var kind: Kind = .huggingFace
    @State private var name = ""
    @State private var repo = ""
    @State private var file = ""
    @State private var url = ""
    @State private var localPath = ""
    @State private var language = "he"
    let onAdd: (ManagedModel) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a model").font(.headline)
            Picker("Source", selection: $kind) { ForEach(Kind.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented)
            TextField("Display name", text: $name)
            switch kind {
            case .huggingFace:
                TextField("Repo (e.g. ggerganov/whisper.cpp)", text: $repo)
                TextField("File (e.g. ggml-medium.bin)", text: $file)
            case .url:
                TextField("https://…/model.bin", text: $url)
            case .local:
                HStack { TextField("/path/model.bin", text: $localPath); Button("Choose…", action: choose) }
            }
            Picker("Language", selection: $language) {
                Text("Hebrew").tag("he"); Text("English").tag("en"); Text("Multilingual").tag("auto")
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Add", action: add).keyboardShortcut(.defaultAction).disabled(!isValid)
            }
        }
        .padding(20).frame(width: 440)
    }

    private var isValid: Bool {
        guard !name.isEmpty else { return false }
        switch kind {
        case .huggingFace: return !repo.isEmpty && !file.isEmpty
        case .url: return !url.isEmpty && URL(string: url) != nil
        case .local: return !localPath.isEmpty
        }
    }

    private func slug() -> String {
        let base = name.lowercased().replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return base.isEmpty ? "model-\(abs(name.hashValue))" : base
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowsOtherFileTypes = true
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let u = panel.url { localPath = u.path }
    }

    private func add() {
        let source: ModelSource
        switch kind {
        case .huggingFace: source = .huggingFace(repo: repo, file: file)
        case .url: source = .directURL(URL(string: url)!)
        case .local: source = .localFile(path: localPath)
        }
        onAdd(ManagedModel(id: slug(), displayName: name, source: source,
                           defaultLanguage: language, minSizeBytes: 0))
    }
}
