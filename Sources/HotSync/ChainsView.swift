import SwiftUI

/// Ketten verwalten und starten: "wenn A fertig ist, dann B, dann C".
struct ChainsView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) var dismiss

    @State private var editing: SyncChain?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.chainsTitle)
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            if appState.tabStore.chains.isEmpty {
                VStack(spacing: 8) {
                    Text(L10n.chainsEmpty)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(appState.tabStore.chains) { chain in
                        chainRow(chain)
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Button {
                    editing = SyncChain(name: L10n.chainDefaultName(appState.tabStore.chains.count + 1))
                } label: {
                    Label(L10n.chainNew, systemImage: "plus")
                }
                .disabled(appState.tabStore.tabs.isEmpty)
                Spacer()
                Button(L10n.done) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480, height: 400)
        .sheet(item: $editing) { chain in
            ChainEditorView(chain: chain)
                .environment(appState)
        }
    }

    private func chainRow(_ chain: SyncChain) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(chain.name)
                    .fontWeight(.medium)
                Text(stepsText(chain))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(L10n.chainRun) {
                appState.runChain(chain.id)
                dismiss()
            }
            .disabled(appState.activeChain != nil || chain.steps.isEmpty)
            Button {
                editing = chain
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            Button {
                appState.tabStore.deleteChain(chain.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.borderless)
            .disabled(appState.activeChain?.chainId == chain.id)
        }
        .padding(.vertical, 4)
    }

    private func stepsText(_ chain: SyncChain) -> String {
        guard !chain.steps.isEmpty else { return L10n.chainNoSteps }
        return chain.steps
            .map { id in appState.tabStore.tab(id).map { appState.title(of: $0) } ?? "?" }
            .joined(separator: " → ")
    }
}

/// Eine Kette bearbeiten: Name und Schritte in ihrer Reihenfolge.
private struct ChainEditorView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) var dismiss

    @State private var draft: SyncChain

    init(chain: SyncChain) {
        _draft = State(initialValue: chain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField(L10n.chainName, text: $draft.name)
                .textFieldStyle(.roundedBorder)

            Text(L10n.chainSteps)
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(Array(draft.steps.enumerated()), id: \.offset) { index, tabId in
                    HStack {
                        Text("\(index + 1).")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(appState.tabStore.tab(tabId).map { appState.title(of: $0) } ?? "?")
                        Spacer()
                        Button {
                            draft.steps.swapAt(index, index - 1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                        Button {
                            draft.steps.swapAt(index, index + 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == draft.steps.count - 1)
                        Button {
                            draft.steps.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .frame(minHeight: 140)

            Menu {
                ForEach(appState.tabStore.tabs) { tab in
                    Button(appState.title(of: tab)) {
                        draft.steps.append(tab.id)
                    }
                }
            } label: {
                Label(L10n.chainAddStep, systemImage: "plus")
            }
            .fixedSize()

            Text(L10n.chainHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(L10n.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.save) {
                    appState.tabStore.save(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440, height: 420)
    }
}
