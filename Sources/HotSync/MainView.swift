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
        .sheet(item: $editingTab) { tab in
            TabEditorView(tab: tab)
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
    }

    private static let radius: CGFloat = 7

    @ViewBuilder
    private var background: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: Self.radius, topTrailingRadius: Self.radius)
        if isSelected {
            shape.fill(Color(nsColor: .windowBackgroundColor))
        } else if isHovered {
            shape.fill(Color.primary.opacity(0.06))
        }
    }

    private var dotColor: Color {
        guard let status = appState.status(tab.id) else { return .gray }
        switch status.phase {
        case .syncing: return .blue
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
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)
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
        }
    }
}
