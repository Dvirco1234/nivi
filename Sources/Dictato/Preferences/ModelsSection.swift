import SwiftUI
import AppKit
import DictatoCore

struct ModelsSection: View {
    @ObservedObject var store: ModelStore
    @State private var showingAdd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Dictation Models").font(.title2.weight(.semibold))
                Spacer()
                Button { showingAdd = true } label: { Label("Add model", systemImage: "plus") }
            }
            ForEach(store.catalog.models) { model in
                ModelCard(model: model,
                          state: store.installStates[model.id] ?? .notInstalled,
                          isDefault: model.id == store.catalog.defaultModelID,
                          onDownload: { Task { await store.install(model) } },
                          onDelete: { store.delete(model.id) },
                          onSetDefault: { store.setDefault(model.id) })
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddModelSheet(onAdd: { store.addModel($0); showingAdd = false },
                          onCancel: { showingAdd = false })
        }
    }
}

private struct ModelCard: View {
    let model: ManagedModel
    let state: InstallState
    let isDefault: Bool
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onSetDefault: () -> Void

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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
            isDefault ? Color.blue.opacity(0.6) : .white.opacity(0.08), lineWidth: isDefault ? 1.5 : 1))
    }

    @ViewBuilder private var action: some View {
        switch state {
        case .installed:
            HStack(spacing: 8) {
                if isDefault {
                    Label("Default", systemImage: "checkmark.circle.fill").foregroundStyle(.blue)
                } else {
                    Button("Set default", action: onSetDefault)
                }
                Menu {
                    if !isDefault { Button("Delete", role: .destructive, action: onDelete) }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).frame(width: 28)
            }
        case .downloading(let f):
            ProgressView(value: f).frame(width: 120)
        case .failed(let msg):
            HStack { Text("Failed").foregroundStyle(.red); Button("Retry", action: onDownload) }
                .help(msg)
        case .notInstalled:
            Button(action: onDownload) { Label("Download", systemImage: "arrow.down.circle") }
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
