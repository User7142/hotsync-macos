import SwiftUI

/// Legt einen Tab an oder ändert ihn: welcher Palm, an welchem Anschluss.
struct TabEditorView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) var dismiss

    @State private var draft: SyncTab
    @State private var confirmDelete = false

    init(tab: SyncTab) {
        _draft = State(initialValue: tab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNewTab ? L10n.tabNewTitle : L10n.tabEditTitle)
                .font(.headline)

            Form {
                Picker(L10n.tabProfile, selection: $draft.profileId) {
                    ForEach(appState.deviceManager.profiles) { profile in
                        Text(profileLabel(profile)).tag(profile.id)
                    }
                }

                Picker(L10n.tabPort, selection: $draft.port) {
                    Text("USB").tag(SyncTab.usbPort)
                    ForEach(appState.portMonitor.serialPorts) { port in
                        Text(serialLabel(port)).tag(port.id)
                    }
                    // ein gespeicherter Adapter, der gerade nicht steckt
                    if !draft.isUSB && appState.portMonitor.serialPort(draft.port) == nil {
                        Text(L10n.tabPortMissing(draft.portLabel)).tag(draft.port)
                    }
                }

                if !draft.isUSB {
                    Picker(L10n.tabBaudRate, selection: $draft.baudRate) {
                        ForEach(SyncTab.baudRates, id: \.self) { rate in
                            Text("\(rate)").tag(rate)
                        }
                    }
                }

                Toggle(L10n.tabAutoListen, isOn: $draft.autoListen)
                Text(L10n.tabAutoListenHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let duplicate {
                Text(L10n.tabDuplicate(appState.title(of: duplicate)))
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                if !isNewTab {
                    Button(L10n.tabDelete, role: .destructive) {
                        confirmDelete = true
                    }
                }
                Spacer()
                Button(L10n.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.save) {
                    appState.saveTab(draft)
                    appState.selectedTabId = draft.id
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(duplicate != nil)
            }
        }
        .padding(24)
        .frame(width: 440)
        .alert(L10n.tabDeleteConfirm, isPresented: $confirmDelete) {
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.delete, role: .destructive) {
                appState.deleteTab(draft.id)
                dismiss()
            }
        } message: {
            Text(L10n.tabDeleteMessage)
        }
    }

    private var isNewTab: Bool {
        appState.tabStore.tab(draft.id) == nil
    }

    /// Derselbe Palm am selben Anschluss als zweiter Tab ergibt keinen Sinn.
    private var duplicate: SyncTab? {
        appState.tabStore.tabs.first {
            $0.id != draft.id && $0.profileId == draft.profileId && $0.port == draft.port
        }
    }

    private func profileLabel(_ profile: DeviceProfile) -> String {
        profile.isBound
            ? L10n.identity(profile.username, UInt32(truncatingIfNeeded: profile.userId))
            : L10n.identityUnbound(profile.username)
    }

    /// "cu.usbserial-A1 · verbunden um 10:12" - so erkennt man den Adapter,
    /// den man eben angesteckt hat.
    private func serialLabel(_ port: PortMonitor.SerialPort) -> String {
        let when = port.connectedAt.map {
            L10n.portConnectedAt($0.formatted(date: .omitted, time: .shortened))
        } ?? L10n.portConnectedBeforeLaunch
        return "\(port.name) · \(when)"
    }
}
