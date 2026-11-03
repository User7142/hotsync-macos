import Contacts
import PalmSync
import PalmSyncMac
import SwiftUI

/// Der Kontakte-Abgleich Mac → Palm eines Profils: ein- und ausschalten,
/// die Konten wählen; die Gruppen werden Kategorien auf dem Palm.
struct ContactSyncSection: View {
    @Environment(AppState.self) var appState
    let profileId: UUID

    @State private var containers: [ContactSource.Container] = []
    @State private var accessStatus: CNAuthorizationStatus = .notDetermined
    @State private var showContainers = false

    private var settings: ContactSyncSettings {
        appState.deviceManager.profile(profileId)?.contactSync ?? ContactSyncSettings()
    }

    private func update(_ change: (inout ContactSyncSettings) -> Void) {
        var s = settings
        change(&s)
        appState.setContactSync(s, for: profileId)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle(isOn: Binding(get: { settings.enabled }, set: { on in update { $0.enabled = on } })) {
                        Text(L10n.contactSyncToggle)
                    }
                    Spacer()
                    Button {
                        showContainers.toggle()
                    } label: {
                        Label(L10n.contactSyncChoose, systemImage: showContainers ? "chevron.up" : "chevron.down")
                    }
                    .disabled(accessStatus != .authorized)
                }
                if settings.enabled {
                    let twoWay = appState.deviceManager.profile(profileId)?.isContactTwoWay ?? false
                    Text(twoWay ? L10n.twoWayHintContacts : L10n.contactSyncWarning)
                        .font(.caption)
                        .foregroundStyle(twoWay ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 16) {
                        Toggle(isOn: Binding(
                            get: { appState.deviceManager.profile(profileId)?.isContactTwoWay ?? false },
                            set: { appState.setContactTwoWay($0, for: profileId) }
                        )) {
                            Text(L10n.twoWayToggle)
                        }
                        if twoWay {
                            Picker(selection: Binding(get: { settings.conflicts }, set: { v in update { $0.conflictPolicy = v } })) {
                                ForEach(ConflictPolicy.allCases, id: \.self) { Text(L10n.conflictPolicyName($0)).tag($0) }
                            } label: {
                                Text(L10n.conflictPolicyLabel)
                            }
                            .pickerStyle(.menu)
                            .fixedSize()
                            .help(L10n.conflictPolicyHelp)
                        }
                    }
                    .font(.caption)
                }

                switch accessStatus {
                case .authorized:
                    if showContainers { containerList }
                    summary
                case .denied, .restricted:
                    Text(L10n.contactSyncDenied)
                        .font(.caption)
                        .foregroundStyle(.red)
                default:
                    Button(L10n.contactSyncAllow) { requestAccess() }
                }
            }
            .padding(4)
        } label: {
            Label(appState.deviceManager.profile(profileId)?.isContactTwoWay == true ? L10n.contactSyncTitleTwoWay : L10n.contactSyncTitle, systemImage: "person.crop.circle")
        }
        .onAppear {
            refreshAccess()
            if appState.contactPreview(for: profileId) == nil { appState.refreshContactPreview(for: profileId) }
        }
    }

    private var containerList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(containers) { container in
                Toggle(isOn: Binding(
                    get: { settings.containers.contains { $0.id == container.id } },
                    set: { on in
                        update { s in
                            s.containers.removeAll { $0.id == container.id }
                            if on { s.containers.append(.init(id: container.id, title: container.title)) }
                        }
                    }
                )) {
                    Text(container.title)
                    Text(container.kind)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(L10n.contactSyncGroupsHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var summary: some View {
        HStack {
            if settings.containers.isEmpty {
                Text(L10n.contactSyncNoContainers)
            } else {
                Text(settings.containers.map(\.title).joined(separator: ", "))
                if let preview = appState.contactPreview(for: profileId) { Text("· " + preview) }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func refreshAccess() {
        accessStatus = appState.contactSource.accessStatus
        if accessStatus == .authorized {
            containers = appState.contactSource.containers()
            for choice in settings.containers where !containers.contains(where: { $0.id == choice.id }) {
                containers.append(.init(id: choice.id, title: choice.title, kind: L10n.calendarGone))
            }
        }
    }

    private func requestAccess() {
        Task {
            _ = try? await appState.contactSource.requestAccess()
            refreshAccess()
            appState.refreshContactPreview(for: profileId)
        }
    }
}
