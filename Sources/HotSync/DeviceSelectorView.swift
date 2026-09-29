import SwiftUI

struct DeviceSelectorView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        Menu {
            // Profil-Liste
            ForEach(appState.deviceManager.profiles) { profile in
                Button(action: {
                    appState.switchProfile(profile)
                }) {
                    HStack {
                        if profile.id == appState.deviceManager.activeProfileId {
                            Image(systemName: "checkmark")
                        }
                        Text(profileLabel(profile))
                    }
                }
            }

            Divider()

            Button(action: {
                appState.showDeviceList = true
            }) {
                Label(L10n.manageDevicesMenu, systemImage: "gearshape")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "laptopcomputer.and.arrow.down")
                    .font(.caption)
                if let profile = appState.deviceManager.activeProfile {
                    Text(profileLabel(profile))
                        .font(.caption)
                        .lineLimit(1)
                } else {
                    Text(L10n.noDevice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func profileLabel(_ profile: DeviceProfile) -> String {
        if let note = profile.deviceNote, !note.isEmpty {
            return "\(profile.username) — \(note)"
        }
        return profile.username
    }
}
