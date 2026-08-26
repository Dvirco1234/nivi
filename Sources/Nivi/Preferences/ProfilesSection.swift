import SwiftUI
import AppKit
import NiviCore

struct ProfilesSection: View {
    @ObservedObject var profileStore: ProfileStore
    @ObservedObject var modelStore: ModelStore
    @State private var editing: DictationProfile?
    @State private var showingSheet = false

    var body: some View {
        PrefPage(title: "Profiles",
                 description: "A profile ties one hotkey to one model and one language. Make one per language you dictate in.") {
            if !PermissionManager.accessibilityGranted {
                PrefBanner(.warning,
                           icon: "exclamationmark.triangle.fill",
                           title: "Nivi cannot paste yet",
                           message: "Give Nivi Accessibility access so it can paste into other apps.",
                           actionTitle: "Open Settings") {
                    PermissionManager.openAccessibilitySettings()
                }
            }
            PrefCardList("Your profiles") {
                Button { startAdd() } label: { Label("Add profile", systemImage: "plus") }
                    .disabled(installedModels.isEmpty)
            } content: {
                if installedModels.isEmpty {
                    PrefEmptyState(icon: "cpu",
                                   title: "No models yet",
                                   message: "Install a model in Dictation models first, then come back here.")
                        .background(PrefTheme.cardFill,
                                    in: RoundedRectangle(cornerRadius: UITuning.cardCorner))
                        .overlay(RoundedRectangle(cornerRadius: UITuning.cardCorner)
                            .strokeBorder(PrefTheme.cardStroke, lineWidth: 1))
                }
                ForEach(profileStore.set.profiles) { profile in
                    ProfileCard(
                        profile: profile,
                        modelName: modelStore.catalog.model(id: profile.modelID)?.displayName ?? profile.modelID,
                        isPrimary: profile.id == profileStore.set.primaryID,
                        canDelete: profileStore.set.profiles.count > 1,
                        onPrimary: { profileStore.setPrimary(profile.id) },
                        onEdit: { startEdit(profile) },
                        onDelete: { profileStore.remove(profile.id) })
                }
            }
        }
        .navigationTitle("Profiles")
        .sheet(isPresented: $showingSheet) {
            ProfileEditSheet(
                draft: editing ?? blankDraft(),
                isNew: editing == nil,
                models: installedModels,
                conflict: { hotkey, id in profileStore.conflict(for: hotkey, excluding: id) },
                onSave: { profileStore.upsert($0); showingSheet = false },
                onCancel: { showingSheet = false })
        }
    }

    private var installedModels: [ManagedModel] {
        modelStore.catalog.models.filter { modelStore.isInstalled($0.id) }
    }

    private func startAdd() { editing = nil; showingSheet = true }
    private func startEdit(_ p: DictationProfile) { editing = p; showingSheet = true }

    private func blankDraft() -> DictationProfile {
        let model = installedModels.first
        return DictationProfile(id: profileStore.newProfileID(),
                                name: "", modelID: model?.id ?? "",
                                language: model?.defaultLanguage ?? "he",
                                mode: .batch,
                                hotkey: .modifierTap(.rightCommand, count: 2))
    }
}

private struct ProfileCard: View {
    let profile: DictationProfile
    let modelName: String
    let isPrimary: Bool
    let canDelete: Bool
    let onPrimary: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(profile.name.isEmpty ? "Untitled" : profile.name).font(.headline)
                if isPrimary {
                    Text("Primary").font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.blue.opacity(0.25), in: Capsule())
                }
                Spacer()
                Text(profile.hotkey.displayString)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(0.08), in: Capsule())
            }
            HStack(spacing: 16) {
                Label(modelName, systemImage: "cpu")
                Label(profile.languageLabel, systemImage: "globe")
                Label(modeLabel, systemImage: "text.cursor")
            }
            .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if !isPrimary { Button("Set primary", action: onPrimary) }
                Button("Edit", action: onEdit)
                Spacer()
                // A bordered button around one small icon looks far heavier than
                // anything else on the page, so delete is a bare red icon instead.
                Button(action: onDelete) {
                    Image(systemName: "trash").font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(canDelete ? PrefTheme.danger : Color.secondary)
                .help("Delete this profile")
                .disabled(!canDelete)
            }
            // A profile card draws its own row instead of going through PrefRow, so it
            // has to ask for the small control size the same way PrefRow does.
            .controlSize(.small)
        }
        .padding(UITuning.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PrefTheme.cardFill, in: RoundedRectangle(cornerRadius: UITuning.cardCorner))
        .overlay(RoundedRectangle(cornerRadius: UITuning.cardCorner).strokeBorder(
            isPrimary ? PrefTheme.accent.opacity(0.6) : PrefTheme.cardStroke, lineWidth: isPrimary ? 1.5 : 1))
    }

    private var modeLabel: String { profile.mode.displayName }
}

private struct ProfileEditSheet: View {
    @State var draft: DictationProfile
    let isNew: Bool
    let models: [ManagedModel]
    let conflict: (HotkeyBinding, String?) -> Bool
    let onSave: (DictationProfile) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "Add profile" : "Edit profile").font(.headline)
            TextField("Name", text: $draft.name)
            Picker("Model", selection: $draft.modelID) {
                ForEach(models) { Text($0.displayName).tag($0.id) }
            }
            Picker("Language", selection: $draft.language) {
                Text("Hebrew").tag("he"); Text("English").tag("en"); Text("Multilingual").tag("auto")
            }
            Picker("Insertion mode", selection: $draft.mode) {
                ForEach(InsertionMode.allCases, id: \.self) { m in
                    Text(m.displayName).tag(m)
                }
            }
            HotkeyRecorderView(title: "Hotkey", binding: draft.hotkey) { draft.hotkey = $0 }
            if hotkeyConflict {
                Label("This hotkey is already used by another profile or Cancel.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") { onSave(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(20).frame(width: 460)
    }

    private var hotkeyConflict: Bool { conflict(draft.hotkey, isNew ? nil : draft.id) }
    private var isValid: Bool {
        !draft.name.isEmpty && !draft.modelID.isEmpty && !hotkeyConflict
    }
}
