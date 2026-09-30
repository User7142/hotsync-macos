import SwiftUI

struct DeviceListView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) var dismiss

    enum AddMode: String, Identifiable {
        case readFromPalm
        case createNew
        var id: String { rawValue }
    }

    @State private var addMode: AddMode?
    @State private var newUsername = ""
    @State private var newDeviceNote = ""
    @State private var isReading = false
    @State private var isSetting = false
    @State private var readError: String?
    @State private var profileToDelete: DeviceProfile?
    @FocusState private var isNewNameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(L10n.manageDevices)
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Profil-Liste
            List {
                ForEach(appState.deviceManager.profiles) { profile in
                    profileRow(profile)
                }
            }
            .listStyle(.inset)

            Divider()

            // Aktionen
            HStack {
                Menu {
                    Button(action: { addMode = .createNew }) {
                        Label(L10n.newNameAction, systemImage: "plus.circle")
                    }
                    Button(action: { addMode = .readFromPalm }) {
                        Label(L10n.readFromPalmAction, systemImage: "antenna.radiowaves.left.and.right")
                    }
                } label: {
                    Label(L10n.newDevice, systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()

                Button(L10n.done) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 440, height: 380)
        .sheet(item: $addMode) { mode in
            switch mode {
            case .createNew:
                addNewDeviceSheet
            case .readFromPalm:
                readFromPalmSheet
            }
        }
        .alert(L10n.deleteDevice, isPresented: Binding(
            get: { profileToDelete != nil },
            set: { if !$0 { profileToDelete = nil } }
        )) {
            Button(L10n.cancel, role: .cancel) { profileToDelete = nil }
            Button(L10n.delete, role: .destructive) {
                if let profile = profileToDelete {
                    appState.deviceManager.deleteProfile(profile)
                }
                profileToDelete = nil
            }
        } message: {
            if let profile = profileToDelete {
                Text(L10n.deleteMessage(profile.username))
            }
        }
    }

    // MARK: - Profil-Zeile

    private func profileRow(_ profile: DeviceProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.username)
                        .fontWeight(.medium)
                    if profile.id == appState.deviceManager.activeProfileId {
                        Text(L10n.active)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.15), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }
                HStack(spacing: 8) {
                    if let note = profile.deviceNote, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let lastSync = profile.lastSyncAt {
                        Text("Sync: \(lastSync, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if profile.id != appState.deviceManager.activeProfileId {
                Button(L10n.activate) {
                    appState.switchProfile(profile)
                }
                .controlSize(.small)
            }

            Button(action: { profileToDelete = profile }) {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Neues Gerät erstellen

    private var addNewDeviceSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text(L10n.setupNewDevice)
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.username)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(L10n.usernamePlaceholder, text: $newUsername)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNewNameFocused)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.deviceNoteLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(L10n.deviceNotePlaceholder, text: $newDeviceNote)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .frame(width: 260)

            HStack(spacing: 12) {
                Button(L10n.cancel) {
                    if isSetting { appState.palmIdentity.cancelActiveProcess() }
                    resetAddState()
                    addMode = nil
                }
                .keyboardShortcut(.cancelAction)

                Button(L10n.createProfileOnly) {
                    createLocalProfile()
                }
                .disabled(newUsername.trimmingCharacters(in: .whitespaces).isEmpty || isSetting)

                Button(L10n.setOnPalm) {
                    setOnPalm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newUsername.trimmingCharacters(in: .whitespaces).isEmpty || isSetting)
            }
            .fixedSize()

            if let error = readError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if isSetting {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text(L10n.waitingForPalm)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(30)
        .frame(width: 480)
        .onAppear { isNewNameFocused = true }
    }

    // MARK: - Vom Palm lesen

    private var readFromPalmSheet: some View {
        VStack(spacing: 20) {
            if isReading {
                ProgressView()
                    .scaleEffect(1.2)
                    .padding(.bottom, 4)

                Text(L10n.readPalmTitle)
                    .font(.headline)

                Text(L10n.readPalmSubtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(L10n.cancel) {
                    isReading = false
                }
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)

                Text(L10n.readPalmIdentityTitle)
                    .font(.headline)

                Text(L10n.readPalmIdentitySubtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let error = readError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 12) {
                    Button(L10n.cancel) {
                        resetAddState()
                        addMode = nil
                    }
                    .keyboardShortcut(.cancelAction)

                    Button(L10n.readPalmButton) {
                        readFromPalm()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(30)
        .frame(width: 360)
    }

    // MARK: - Actions

    private func createLocalProfile() {
        let name = newUsername.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let note = newDeviceNote.trimmingCharacters(in: .whitespaces)
        let userId = UInt.random(in: 10000...99999)
        let profile = appState.deviceManager.addProfile(
            username: name, userId: userId,
            deviceNote: note.isEmpty ? nil : note
        )
        // Zum neuen Profil wechseln
        appState.switchProfile(profile)
        resetAddState()
        addMode = nil
    }

    private func setOnPalm() {
        let name = newUsername.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isSetting = true
        readError = nil
        // Der Leerlauf-Listener (pilot-xfer -l) würde dem Einrichten die
        // USB-Verbindung streitig machen: erst anhalten, dann einrichten.
        appState.isSettingUsername = true

        DispatchQueue.global(qos: .userInitiated).async {
            appState.syncEngine.stopAndWait()
            let result = appState.palmIdentity.setUsername(name)
            DispatchQueue.main.async {
                isSetting = false
                appState.isSettingUsername = false
                if result.success {
                    let note = newDeviceNote.trimmingCharacters(in: .whitespaces)
                    let profile = appState.deviceManager.addProfile(
                        username: name, userId: result.userId,
                        deviceNote: note.isEmpty ? nil : note
                    )
                    appState.switchProfile(profile)
                    resetAddState()
                    addMode = nil
                } else {
                    readError = L10n.connectionFailed
                    appState.startListeningIfReady()
                }
            }
        }
    }

    private func readFromPalm() {
        isReading = true
        readError = nil
        appState.isSettingUsername = true

        DispatchQueue.global(qos: .userInitiated).async {
            appState.syncEngine.stopAndWait()
            let info = appState.palmIdentity.checkUsername()
            DispatchQueue.main.async {
                isReading = false
                appState.isSettingUsername = false
                if let info, !info.name.isEmpty {
                    let profile = appState.deviceManager.addProfile(
                        username: info.name, userId: info.userId,
                        deviceNote: nil
                    )
                    appState.switchProfile(profile)
                    resetAddState()
                    addMode = nil
                } else {
                    readError = L10n.noUsernameFound
                    appState.startListeningIfReady()
                }
            }
        }
    }

    private func resetAddState() {
        newUsername = ""
        newDeviceNote = ""
        readError = nil
        isReading = false
        isSetting = false
    }
}
