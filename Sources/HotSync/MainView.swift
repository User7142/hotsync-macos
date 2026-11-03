import SwiftUI
import UniformTypeIdentifiers
import HotSyncCore

/// Das Hauptfenster: Tab-Leiste, darüber Hinweise (laufende Kette,
/// unbekannte Palms), darunter der gewählte Tab.
struct MainView: View {
    @Environment(AppState.self) var appState

    @State private var editingTab: SyncTab?

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if let chain = appState.activeChain {
                ChainBanner(active: chain)
            }
            ForEach(appState.notices) { notice in
                NoticeBanner(notice: notice)
            }

            tabBar

            if let id = appState.selectedTabId, let tab = appState.tabStore.tab(id) {
                TabDetailView(tab: tab, onEdit: { editingTab = tab })
                    .id(tab.id)
            } else {
                emptyState
            }
        }
        // Den ganzen Fensterraum nutzen, Inhalt oben beginnen - sonst
        // zentriert SwiftUI den Block, sobald das Fenster größer ist.
        .frame(minWidth: 560, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity, alignment: .top)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
        .sheet(item: Binding(
            get: { appState.newPalmPrompt },
            set: { if $0 == nil, let prompt = appState.newPalmPrompt { appState.ignoreNewPalm(prompt) } }
        )) { prompt in
            NewPalmSheet(prompt: prompt)
                .environment(appState)
        }
        .sheet(item: $editingTab) { tab in
            TabEditorView(tab: tab)
                .environment(appState)
        }
        // Konflikte entscheiden, während der Palm wartet; Schließen heißt auslassen
        .sheet(item: Binding(
            get: { appState.conflictPrompt },
            set: { if $0 == nil, appState.conflictPrompt != nil { appState.answerConflicts(nil) } }
        )) { prompt in
            ConflictSheet(prompt: prompt)
                .environment(appState)
        }
        .sheet(isPresented: Binding(
            get: { appState.showDeviceList },
            set: { appState.showDeviceList = $0 }
        )) {
            DeviceListView()
                .environment(appState)
        }
        .sheet(isPresented: Binding(
            get: { appState.showChains },
            set: { appState.showChains = $0 }
        )) {
            ChainsView()
                .environment(appState)
        }
    }

    // MARK: - Kopfzeile

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            Text("HotSync")
                .font(.headline)

            Spacer()

            Button {
                appState.showChains = true
            } label: {
                Label(L10n.chainsButton, systemImage: "arrow.right.circle")
            }
            Button {
                appState.showDeviceList = true
            } label: {
                Label(L10n.devicesButton, systemImage: "laptopcomputer.and.arrow.down")
            }

            Picker("", selection: Binding(
                get: { appState.language },
                set: { appState.language = $0 }
            )) {
                ForEach(Language.allCases, id: \.self) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Tab-Leiste

    /// Reiter wie in Safari/Finder: Die Leiste ist leicht abgedunkelt, der
    /// gewählte Reiter hat die Fensterfarbe und ist nach unten offen - er
    /// geht in den Inhalt darunter über. Die Grundlinie liegt unter allen
    /// Reitern; der gewählte deckt sie mit seiner Fläche ab.
    private var tabBar: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)

            HStack(alignment: .bottom, spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(appState.tabStore.tabs) { tab in
                            TabButton(tab: tab, isSelected: tab.id == appState.selectedTabId) {
                                appState.selectedTabId = tab.id
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                Button {
                    editingTab = newTab()
                } label: {
                    Image(systemName: "plus")
                        .padding(6)
                }
                .buttonStyle(.borderless)
                .help(L10n.tabAddHelp)
                .disabled(!appState.deviceManager.hasProfiles)
                .padding(.trailing, 12)
                .padding(.bottom, 4)
            }
        }
        .background(Color.primary.opacity(0.05))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(L10n.tabsEmpty)
                .foregroundStyle(.secondary)
            Button(L10n.tabAdd) {
                editingTab = newTab()
            }
            .disabled(!appState.deviceManager.hasProfiles)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Vorschlag für einen neuen Tab: erstes Profil an einem eben
    /// angesteckten seriellen Adapter, sonst USB.
    private func newTab() -> SyncTab? {
        guard let profile = appState.deviceManager.profiles.first else { return nil }
        let port = appState.portMonitor.serialPorts
            .filter { $0.connectedAt != nil }
            .max { ($0.connectedAt ?? .distantPast) < ($1.connectedAt ?? .distantPast) }?.id
            ?? SyncTab.usbPort
        return SyncTab(profileId: profile.id, port: port, autoListen: false)
    }

    /// Jede abgelegte Datei landet in der Warteschlange des gewählten Tabs.
    private func handleDrop(_ providers: [NSItemProvider]) {
        guard let id = appState.selectedTabId,
              let tab = appState.tabStore.tab(id),
              let queue = appState.queue(for: tab) else { return }
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    queue.add([url])
                }
            }
        }
    }
}

// MARK: - Reiter

private struct TabButton: View {
    @Environment(AppState.self) var appState
    let tab: SyncTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @State private var isDropTarget = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                Text(appState.title(of: tab))
                    .fontWeight(isSelected ? .medium : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                if tab.autoListen {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(background)
            .overlay {
                if isSelected {
                    TabOutline(radius: Self.radius)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        // Dateien auf den Reiter ziehen: aus einer anderen Warteschlange
        // verschoben, aus dem Finder kopiert
        .dropDestination(for: URL.self) { urls, _ in
            appState.drop(urls, on: tab)
            return true
        } isTargeted: { isDropTarget = $0 }
    }

    private static let radius: CGFloat = 7

    @ViewBuilder
    private var background: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: Self.radius, topTrailingRadius: Self.radius)
        if isDropTarget {
            shape.fill(Color.accentColor.opacity(0.25))
        } else if isSelected {
            shape.fill(Color(nsColor: .windowBackgroundColor))
        } else if isHovered {
            shape.fill(Color.primary.opacity(0.06))
        }
    }

    private var dotColor: Color {
        guard let status = appState.status(tab.id) else { return .gray }
        switch status.phase {
        case .restoring, .syncing, .backingUp, .readingCalendar, .dumpingROM: return .blue
        case .listening: return .green
        case .waitingForPort: return .orange
        case .idle:
            switch status.lastResult {
            case .rejected, .failed, .timedOut: return .red
            case .finished(_, _, let failed): return failed > 0 ? .orange : .gray
            case .stopped, nil: return .gray
            }
        }
    }
}

/// Umriss eines Reiters: links, oben (abgerundet) und rechts - unten offen,
/// damit der gewählte Reiter in den Inhalt übergeht.
private struct TabOutline: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY), radius: radius)
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius), radius: radius)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

// MARK: - Banner: laufende Kette

private struct ChainBanner: View {
    @Environment(AppState.self) var appState
    let active: AppState.ActiveChain

    var body: some View {
        let name = appState.tabStore.chain(active.chainId)?.name ?? ""
        HStack(spacing: 10) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(isPaused ? .orange : .blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.chainBannerTitle(name, stepIndex + 1, active.run.steps.count))
                    .font(.callout)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(isPaused ? .orange : .secondary)
            }
            Spacer()
            if isPaused {
                Button(L10n.chainRetry) { appState.retryChainStep() }
                Button(L10n.chainSkip) { appState.skipChainStep() }
            }
            Button(L10n.chainCancel, role: .destructive) { appState.cancelChain() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background((isPaused ? Color.orange : Color.blue).opacity(0.08))
    }

    private var isPaused: Bool {
        if case .paused = active.run.state { return true }
        return false
    }

    private var stepIndex: Int {
        switch active.run.state {
        case .running(let step), .paused(let step, _): return step
        case .finished, .cancelled: return max(active.run.steps.count - 1, 0)
        }
    }

    private var detail: String {
        let tabName = active.run.currentTab.flatMap { appState.tabStore.tab($0) }
            .map { appState.title(of: $0) } ?? "?"
        if case .paused(_, let reason) = active.run.state {
            return L10n.chainPausedDetail(tabName, reason)
        }
        return L10n.chainRunningDetail(tabName)
    }
}

// MARK: - Banner: Palm ohne Tab

private struct NoticeBanner: View {
    @Environment(AppState.self) var appState
    let notice: PortNotice

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isFailure ? "exclamationmark.triangle.fill" : "questionmark.circle.fill")
                .foregroundStyle(isFailure ? .red : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)
                Text(L10n.noticeDetail(appState.portLabel(notice.port),
                                       notice.date.formatted(date: .omitted, time: .shortened)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if case .unknown(let user) = notice.kind {
                Menu(L10n.assignToProfile) {
                    ForEach(appState.deviceManager.profiles) { profile in
                        Button(profile.username) { appState.assign(user, to: profile.id) }
                    }
                }
                .fixedSize()
                Button(L10n.createProfileFromPalm) {
                    appState.createProfile(from: user, port: notice.port)
                }
            }

            Button {
                appState.dismissNotice(notice.id)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    private var title: String {
        switch notice.kind {
        case .unknown(let user): return L10n.noticeUnknownPalm(user.name, user.userId)
        case .blank: return L10n.noticeBlankPalm
        case .failed(let message): return L10n.noticeListenerFailed(message)
        }
    }

    private var isFailure: Bool {
        if case .failed = notice.kind { return true }
        return false
    }
}

// MARK: - Neuer Palm

/// Fragt bei einem Palm, den HotSync nicht kennt, ob er ein neues Gerät mit
/// eigenem Tab werden soll - ein Palm ohne Benutzer bekommt dabei einen Namen.
private struct NewPalmSheet: View {
    @Environment(AppState.self) var appState
    let prompt: NewPalmPrompt

    /// neues Gerät anlegen oder ein bekanntes übernehmen (z. B. dieser Palm
    /// nach einem Hard Reset)
    enum Mode: Hashable { case new, existing }

    @State private var mode = Mode.new
    @State private var name = ""
    @State private var selectedId: UUID?
    /// beim Übernehmen eines Geräts mit Sicherung: diese zurückspielen
    @State private var restoreBackup = true

    /// Palm OS speichert höchstens 40 Zeichen Benutzername
    private static let maxNameLength = 40

    private var trimmedName: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(Self.maxNameLength))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L10n.newPalmTitle(appState.portLabel(prompt.port)),
                  systemImage: "arrow.triangle.2.circlepath.circle.fill")
                .font(.headline)
            Text(prompt.user.isBlank
                 ? L10n.newPalmBlank
                 : L10n.newPalmUnknown(prompt.user.name, prompt.user.userId))
                .fixedSize(horizontal: false, vertical: true)

            if canTakeOver {
                Picker("", selection: $mode) {
                    Text(L10n.newPalmModeNew).tag(Mode.new)
                    Text(L10n.newPalmModeExisting).tag(Mode.existing)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if mode == .existing, canTakeOver {
                Picker(L10n.newPalmDevice, selection: $selectedId) {
                    ForEach(devices) { device in
                        Text(deviceLabel(device)).tag(Optional(device.id))
                    }
                }
                if let device = selectedDevice, appState.backupCount(for: device.id) > 0 {
                    Toggle(L10n.newPalmRestore(restoreSummary(device)), isOn: $restoreBackup)
                }
            } else {
                if nameEditable {
                    TextField(L10n.newPalmNamePlaceholder, text: $name)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(submit)
                }
                if let taken = nameTakenBy {
                    // derselbe Name: wohl dieser Palm - zum Übernehmen wechseln
                    HStack(alignment: .firstTextBaseline) {
                        Label(L10n.newPalmExisting(taken.username), systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(L10n.newPalmSwitchToTakeOver) {
                            selectedId = taken.id
                            mode = .existing
                        }
                        .controlSize(.small)
                    }
                }
            }

            Text(hint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L10n.newPalmIgnore) {
                    appState.ignoreNewPalm(prompt)
                }
                .keyboardShortcut(.cancelAction)
                if mode == .existing, canTakeOver {
                    Button(selectedDevice.map { L10n.newPalmTakeOver($0.username) } ?? L10n.newPalmModeExisting,
                           action: submit)
                        .keyboardShortcut(.defaultAction)
                        .disabled(selectedDevice == nil)
                } else {
                    Button(L10n.newPalmCreate, action: submit)
                        .keyboardShortcut(.defaultAction)
                        .disabled((nameEditable && trimmedName.isEmpty) || nameTakenBy != nil)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            // Vorbelegt mit dem Namen, den der Palm trägt - auch ein Palm ohne
            // User-ID kann schon einen haben (z. B. von einem anderen Desktop).
            // Gehört er einem Gerät, ist es vermutlich dieses.
            name = prompt.user.name
            if canTakeOver, let match = appState.profile(named: trimmedName), !trimmedName.isEmpty {
                selectedId = match.id
                mode = .existing
            } else {
                selectedId = devices.first?.id
            }
        }
    }

    /// Ein Name lässt sich nur wählen, solange der Palm verbunden ist: Er
    /// wird ihm in derselben Sitzung geschrieben. Ebenso Name und ID eines
    /// übernommenen Geräts.
    private var nameEditable: Bool { prompt.sessionToken != nil }
    private var canTakeOver: Bool { nameEditable && !devices.isEmpty }

    /// zuletzt gesyncte zuerst - nach einem Hard Reset das wahrscheinlichste
    private var devices: [DeviceProfile] {
        appState.deviceManager.profiles.sorted {
            ($0.lastSyncAt ?? .distantPast) > ($1.lastSyncAt ?? .distantPast)
        }
    }

    private var selectedDevice: DeviceProfile? {
        selectedId.flatMap { appState.deviceManager.profile($0) }
    }

    private func deviceLabel(_ device: DeviceProfile) -> String {
        let count = appState.backupCount(for: device.id)
        return count > 0 ? L10n.newPalmDeviceWithBackup(device.username, count) : device.username
    }

    /// Ein neues Gerät darf nicht wie ein bestehendes heißen
    private var nameTakenBy: DeviceProfile? {
        guard nameEditable, !trimmedName.isEmpty else { return nil }
        return appState.profile(named: trimmedName)
    }

    private func restoreSummary(_ device: DeviceProfile) -> String {
        L10n.backupSummary(appState.backupCount(for: device.id),
                           device.lastBackupAt.map { $0.formatted(date: .abbreviated, time: .shortened) })
    }

    private var hint: String {
        if !nameEditable { return L10n.newPalmAgainHint }
        if mode == .existing, canTakeOver { return L10n.newPalmTakeOverHint }
        if prompt.user.isBlank { return L10n.newPalmBlankHint }
        return trimmedName == prompt.user.name ? L10n.newPalmWaitingHint : L10n.newPalmRenameHint
    }

    private func submit() {
        if mode == .existing, canTakeOver {
            guard let device = selectedDevice else { return }
            let restore = restoreBackup && appState.backupCount(for: device.id) > 0
            appState.takeOverDevice(for: prompt, profileId: device.id, restore: restore)
            return
        }
        guard (!nameEditable || !trimmedName.isEmpty), nameTakenBy == nil else { return }
        appState.createDevice(for: prompt, name: trimmedName)
    }
}
