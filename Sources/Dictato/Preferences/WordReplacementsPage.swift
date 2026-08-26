import DictatoCore
import SwiftUI

/// The sub-page where the user says "when I dictate this, write that instead".
///
/// The rules run on every transcript, right after the notes the model writes for silence
/// and music are removed. They are saved as JSON in one setting, so the whole page is a
/// list editor over that one value.
struct WordReplacementsPage: View {
    let goBack: () -> Void

    private let settings = Settings()
    @State private var rules: [WordReplacement] = WordReplacing.decode(json: Settings().wordReplacementsJSON)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: goBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text("General")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(PrefTheme.accent)
            .padding(.horizontal, UITuning.contentPadding)
            .padding(.top, UITuning.contentPadding)

            PrefPage(title: "Word replacements",
                     description: "Fix the words Dictato keeps getting wrong. Every rule is applied to the text before it reaches your app.") {
                PrefGroup(footer: "Matching ignores capital letters. The replacement is written exactly as you type it here, so a rule can also fix capitals. Whole word means \"cat\" does not match inside \"category\".") {
                    if rules.isEmpty {
                        PrefEmptyState(icon: "text.badge.checkmark",
                                       title: "No rules yet",
                                       message: "Add one to fix a name or a term the model keeps mishearing.")
                    } else {
                        ForEach($rules) { $rule in
                            RuleRow(rule: $rule, remove: { remove(rule.id) }, save: save)
                        }
                    }
                    PrefButtonRow(icon: "plus", "Add a rule", buttonTitle: "Add", action: addRule)
                }
            }
        }
    }

    private func addRule() {
        rules.append(WordReplacement(find: "", replaceWith: ""))
        save()
    }

    private func remove(_ id: String) {
        rules.removeAll { $0.id == id }
        save()
    }

    private func save() {
        settings.wordReplacementsJSON = WordReplacing.encode(rules)
    }
}

/// One rule: what to listen for, what to write, and the two switches that change how it
/// matches.
private struct RuleRow: View {
    @Binding var rule: WordReplacement
    let remove: () -> Void
    let save: () -> Void

    var body: some View {
        HStack(spacing: PrefTheme.rowIconGap) {
            TextField("Say this", text: $rule.find)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120)
            Image(systemName: "arrow.right")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField("Write this", text: $rule.replaceWith)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120)
            Toggle("Whole word", isOn: $rule.matchWholeWord)
                .toggleStyle(.checkbox)
                .fixedSize()
            Toggle("On", isOn: $rule.isEnabled)
                .toggleStyle(.checkbox)
                .fixedSize()
            Button(role: .destructive, action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(PrefTheme.danger)
            .help("Delete this rule")
        }
        .controlSize(.small)
        .padding(.horizontal, UITuning.cardPadding)
        .padding(.vertical, PrefTheme.rowVerticalPadding)
        .frame(minHeight: PrefTheme.rowMinHeight)
        // Saving on every keystroke keeps the setting and the screen the same thing. The
        // value is a short JSON string, so there is nothing to gain by waiting.
        .onChange(of: rule) { _ in save() }
    }
}
