import PalmSync
import SwiftUI

/// Die Konflikte eines Abgleichs, einer nach dem anderen: Mac, Palm oder
/// beide behalten. Der Palm wartet in der Sitzung, bis hier entschieden ist.
struct ConflictSheet: View {
    @Environment(AppState.self) var appState
    let prompt: ConflictPrompt

    @State private var choices: [ConflictPolicy]

    init(prompt: ConflictPrompt) {
        self.prompt = prompt
        _choices = State(initialValue: Array(repeating: .macWins, count: prompt.conflicts.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.conflictAskTitle(prompt.what, prompt.palmName), systemImage: "arrow.left.arrow.right.circle.fill")
                .font(.headline)
            Text(L10n.conflictAskHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(prompt.conflicts.indices, id: \.self) { i in
                        let conflict = prompt.conflicts[i]
                        GroupBox {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(conflict.title) · \(conflict.field)")
                                    .font(.subheadline.weight(.semibold))
                                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                                    GridRow {
                                        Text(L10n.conflictAskPalm).foregroundStyle(.secondary)
                                        Text(conflict.palmValue.isEmpty ? "–" : conflict.palmValue)
                                    }
                                    GridRow {
                                        Text(L10n.conflictAskMac).foregroundStyle(.secondary)
                                        Text(conflict.macValue.isEmpty ? "–" : conflict.macValue)
                                    }
                                }
                                .font(.caption)
                                Picker("", selection: $choices[i]) {
                                    Text(L10n.conflictAskMac).tag(ConflictPolicy.macWins)
                                    Text(L10n.conflictAskPalm).tag(ConflictPolicy.palmWins)
                                    Text(L10n.conflictAskBoth).tag(ConflictPolicy.keepBoth)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(width: 220)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 420)

            HStack {
                Button(L10n.conflictAskAllMac) { choices = choices.map { _ in .macWins } }
                Button(L10n.conflictAskAllPalm) { choices = choices.map { _ in .palmWins } }
                Spacer()
                Button(L10n.conflictAskSkip) { appState.answerConflicts(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.conflictAskApply) { appState.answerConflicts(choices) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}
