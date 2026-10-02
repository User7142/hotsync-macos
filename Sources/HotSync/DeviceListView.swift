import SwiftUI

/// Profile verwalten. Die Identität (Name + User-ID) kommt vom Palm: Ein
/// neues Profil ist zunächst keinem Palm zugeordnet; der erste Palm ohne
/// Benutzer, der in seinem Tab synct, übernimmt es - oder man ordnet einen
/// schon benutzten Palm zu, wenn er sich meldet.
struct DeviceListView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) var dismiss

    @State private var showAdd = false
    @State private var profileToDelete: DeviceProfile?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.manageDevices)
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            List {
                ForEach(appState.deviceManager.profiles) { profile in
                    profileRow(profile)
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Button {
                    showAdd = true
                } label: {
                    Label(L10n.newDevice, systemImage: "plus")
                }
                Spacer()
                Button(L10n.done) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 460, height: 380)
        .sheet(isPresented: $showAdd) {
            AddProfileView()
                .environment(appState)
        }
        .alert(L10n.deleteDevice, isPresented: Binding(
            get: { profileToDelete != nil },
            set: { if !$0 { profileToDelete = nil } }
        )) {
            Button(L10n.cancel, role: .cancel) { profileToDelete = nil }
            Button(L10n.delete, role: .destructive) {
                if let profile = profileToDelete {
                    appState.deleteProfile(profile)
                }
                profileToDelete = nil
            }
        } message: {
            if let profile = profileToDelete {
                Text(L10n.deleteMessage(profile.username))
            }
        }
    }

    private func profileRow(_ profile: DeviceProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.username)
                    .fontWeight(.medium)
                HStack(spacing: 8) {
                    Text(profile.isBound ? L10n.profileUserId(profile.userId) : L10n.profileUnbound)
                        .font(.caption)
                        .foregroundStyle(profile.isBound ? Color.secondary : Color.orange)
                    if let note = profile.deviceNote, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let lastSync = profile.lastSyncAt {
                        Text("Sync: \(lastSync.formatted(date: .numeric, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            Button(action: { profileToDelete = profile }) {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

/// Neues Profil: Name und optional eine Notiz. Dazu entsteht ein USB-Tab.
struct AddProfileView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var note = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.blue)
            Text(L10n.setupNewDevice)
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.username)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(L10n.usernamePlaceholder, text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.deviceNoteLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(L10n.deviceNotePlaceholder, text: $note)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .frame(width: 280)

            Text(L10n.addProfileHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button(L10n.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.createProfile) {
                    let trimmedNote = note.trimmingCharacters(in: .whitespaces)
                    appState.addProfile(name: name.trimmingCharacters(in: .whitespaces),
                                        note: trimmedNote.isEmpty ? nil : trimmedNote)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(28)
        .frame(width: 400)
        .onAppear { nameFocused = true }
    }
}
