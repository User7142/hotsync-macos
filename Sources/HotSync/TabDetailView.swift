import SwiftUI
import AppKit
import HotSyncCore

/// Inhalt eines Tabs: Anschluss und Zustand, Ergebnis der letzten Sitzung,
/// Warteschlange des Profils, zuletzt installiert und das Log des Tabs.
struct TabDetailView: View {
    @Environment(AppState.self) var appState
    let tab: SyncTab
    let onEdit: () -> Void

    @State private var confirmRestore = false

    var body: some View {
        VStack(spacing: 12) {
            header
                .padding([.horizontal, .top])
            // Der Kopf bleibt stehen, der Rest rollt: mit den Abgleich-
            // Abschnitten passt nicht mehr alles ins Fenster. Der Rand liegt
            // am Inhalt, nicht am ScrollView, damit der Rollbalken am
            // Fensterrand sitzt.
            ScrollView {
                VStack(spacing: 12) {
                    if let status = appState.status(tab.id) {
                        if status.isSyncing || status.lastResult != nil || status.lastBackup != nil
                            || status.lastRestore != nil || status.lastROMDump != nil {
                            resultBox(status)
                        }
                    }
                    if palmOS?.hasGarnetPIM ?? true {
                        DryRunSection(profileId: tab.profileId)
                        CalendarSyncSection(profileId: tab.profileId)
                        ContactSyncSection(profileId: tab.profileId)
                        TaskSyncSection(profileId: tab.profileId)
                        TimeSyncSection(profileId: tab.profileId)
                    } else if let os = palmOS {
                        // Datebook/Address/ToDo-Geräte: kein Abgleich, keine Zeitzonen, nur die Uhr
                        GroupBox {
                            Text(L10n.palmOSTooOld(os.description))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(4)
                        }
                    }
                    if let queue = appState.queue(for: tab) {
                        QueueSection(queue: queue, profileId: tab.profileId,
                                     isSyncing: appState.status(tab.id)?.isSyncing == true)
                        InstalledSection(queue: queue)
                    }
                    if let status = appState.status(tab.id) {
                        TabLogSection(log: status.log)
                            .frame(height: 260)
                    }
                }
                .padding([.horizontal, .bottom])
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .alert(L10n.restoreConfirmTitle, isPresented: $confirmRestore) {
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.restoreConfirm) { appState.requestRestore(true, for: tab.profileId) }
        } message: {
            Text(L10n.restoreConfirmMessage(appState.profileName(tab.profileId), backupSummary))
        }
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            SyncLogo(phase: phase, color: phaseColor, icon: phaseIcon)

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.title(of: tab))
                    .font(.headline)
                Text(phaseText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(portText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if appState.restoreRequests.contains(tab.profileId) {
                    Label(L10n.backupRestorePending, systemImage: "arrow.counterclockwise.circle")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                if appState.romRequests.contains(tab.profileId) {
                    Label(L10n.romDumpPending, systemImage: "memorychip")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Text(L10n.tabSyncModeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Menu {
                    Picker("", selection: Binding(
                        get: { tab.hotSyncMode },
                        set: { appState.setMode($0, for: tab.id) }
                    )) {
                        ForEach(HotSyncMode.allCases, id: \.self) { mode in
                            Text(L10n.modeName(mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if appState.tabStore.tabs.count > 1 {
                        Divider()
                        ForEach(HotSyncMode.allCases, id: \.self) { mode in
                            Button(L10n.allTabsMode(mode)) { appState.setModeForAllTabs(mode) }
                        }
                    }
                } label: {
                    Text(L10n.modeName(tab.hotSyncMode))
                }
                .menuStyle(.button)
                .fixedSize()
            }
            .help(L10n.tabSyncModeHint)

            Menu {
                Text(backupSummary)
                if appState.restoreRequests.contains(tab.profileId) {
                    Button(L10n.backupRestoreCancel) { appState.requestRestore(false, for: tab.profileId) }
                } else {
                    Button(L10n.backupRestoreNext) { confirmRestore = true }
                        .disabled(backupCount == 0)
                }
                Divider()
                Button(L10n.backupOpenFolder) { openBackupFolder() }
                Divider()
                if appState.romRequests.contains(tab.profileId) {
                    Button(L10n.romDumpCancel) { appState.requestROMDump(false, for: tab.profileId) }
                } else if let os = palmOS, !os.canDumpROM {
                    Text(L10n.romDumpUnsupported(os.description))
                } else {
                    Button(L10n.romDumpNext) { appState.requestROMDump(true, for: tab.profileId) }
                }
                if hasROM {
                    Button(L10n.romOpenFolder) { openROMFolder() }
                }
            } label: {
                Label(L10n.backupMenu, systemImage: "externaldrive.badge.timemachine")
            }
            .menuStyle(.button)
            .fixedSize()
            .help(L10n.backupMenuHelp)

            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
            }
            .help(L10n.tabEditHelp)

            if appState.isStarted(tab.id) || appState.status(tab.id)?.isSyncing == true {
                Button {
                    appState.stopTab(tab.id)
                } label: {
                    Label(L10n.tabStop, systemImage: "stop.circle")
                }
            } else {
                Button {
                    appState.startTab(tab.id)
                } label: {
                    Label(L10n.tabSyncNow, systemImage: "arrow.triangle.2.circlepath")
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!appState.portMonitor.isConnected(tab.port))
                .help(L10n.tabSyncNowHelp)
            }
        }
    }

    private var phase: TabStatus.Phase {
        appState.status(tab.id)?.phase ?? .idle
    }

    private var backupDirectory: URL? {
        appState.deviceManager.profile(tab.profileId).map { appState.deviceManager.backupDirectory(for: $0) }
    }

    private var backupCount: Int { appState.backupCount(for: tab.profileId) }

    private var backupSummary: String {
        let date = appState.deviceManager.profile(tab.profileId)?.lastBackupAt
            .map { $0.formatted(date: .abbreviated, time: .shortened) }
        return L10n.backupSummary(backupCount, date)
    }

    private var palmOS: PalmOSVersion? { appState.deviceManager.profile(tab.profileId)?.palmOS }

    private var romDirectory: URL? {
        appState.deviceManager.profile(tab.profileId).map { appState.deviceManager.romDirectory(for: $0) }
    }

    private var hasROM: Bool {
        guard let dir = romDirectory, let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return false }
        return names.contains { $0.hasSuffix(".rom") }
    }

    private func openROMFolder() {
        if let dir = romDirectory { NSWorkspace.shared.open(dir) }
    }

    private func openBackupFolder() {
        guard let dir = backupDirectory else { return }
        if FileManager.default.fileExists(atPath: dir.path) {
            NSWorkspace.shared.open(dir)
        } else {
            // noch keine Sicherung: der Geräteordner, in dem sie entstehen wird
            NSWorkspace.shared.open(dir.deletingLastPathComponent())
        }
    }

    private var phaseColor: Color {
        switch phase {
        case .restoring, .syncing, .backingUp, .readingCalendar, .dumpingROM: return .blue
        case .listening: return .green
        case .waitingForPort: return .orange
        case .idle: return .gray
        }
    }

    private var phaseIcon: String {
        switch phase {
        case .syncing: return "arrow.triangle.2.circlepath"
        case .restoring: return "arrow.counterclockwise.circle"
        case .backingUp: return "externaldrive.badge.timemachine"
        case .readingCalendar: return "calendar"
        case .dumpingROM: return "memorychip"
        case .listening: return "antenna.radiowaves.left.and.right"
        case .waitingForPort: return "hourglass"
        case .idle: return "power.circle"
        }
    }

    private var phaseText: String {
        switch phase {
        case .syncing(let user, let file, let done, let total):
            if total == 0 { return L10n.phaseSyncingNothing(user.name) }
            return L10n.phaseSyncing(user.name, done, total, file)
        case .restoring(let user, let file, let done, let total):
            return L10n.phaseRestoring(user.name, done, total, file)
        case .backingUp(let user, let file, let done, let total):
            return L10n.phaseBackingUp(user.name, done, total, file)
        case .readingCalendar(let user, let database, let done):
            return L10n.phaseReadingCalendar(user.name, database, done)
        case .dumpingROM(let user, let done, let total):
            return L10n.phaseDumpingROM(user.name, done, total)
        case .listening:
            return appState.isStarted(tab.id) ? L10n.phaseListeningTargeted : L10n.phaseListeningAuto
        case .waitingForPort:
            return appState.portMonitor.isConnected(tab.port)
                ? L10n.phaseWaitingForPort : L10n.phasePortMissing
        case .idle:
            if !appState.portMonitor.isConnected(tab.port) { return L10n.phasePortMissing }
            return tab.autoListen ? L10n.phaseIdleAuto : L10n.phaseIdleManual
        }
    }

    /// Damit man beim Zuweisen sieht, was eben angesteckt wurde bzw. wer
    /// sich zuletzt gemeldet hat.
    private var portText: String {
        var parts: [String] = []
        if let interface = tab.networkInterface {
            let address = interface == SyncTab.networkAll ? LocalAddress.ipv4().first : LocalAddress.address(ofInterface: interface)
            parts.append(L10n.portNetworkAddress(address?.ip))
        }
        if tab.isSerial {
            if let serial = appState.portMonitor.serialPort(tab.port) {
                parts.append(serial.connectedAt.map {
                    L10n.portConnectedAt($0.formatted(date: .omitted, time: .shortened))
                } ?? L10n.portConnectedBeforeLaunch)
            } else {
                parts.append(L10n.portNotConnected)
            }
            parts.append("\(tab.baudRate) Bd")
        }
        if let seen = appState.portMonitor.lastSeen[tab.port] {
            parts.append(L10n.portLastSeen(seen.user.name, seen.date.formatted(date: .omitted, time: .shortened)))
        }
        return ([appState.portLabel(tab.port)] + parts).joined(separator: " · ")
    }

    // MARK: - Ergebnis

    @ViewBuilder
    private func resultBox(_ status: TabStatus) -> some View {
        if let (done, total) = progress(status.phase) {
            GroupBox {
                if total > 0 {
                    ProgressView(value: Double(done), total: Double(total))
                        .tint(.blue)
                        .padding(4)
                } else {
                    // Sicherung: die Liste der Datenbanken wird noch gelesen
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .padding(4)
                }
            }
        } else if status.lastResult != nil || status.lastBackup != nil || status.lastRestore != nil
                    || status.lastROMDump != nil {
            GroupBox {
                HStack(alignment: .top, spacing: 10) {
                    if let result = status.lastResult {
                        Image(systemName: resultIcon(result))
                            .foregroundStyle(resultColor(result))
                    } else {
                        Image(systemName: "externaldrive.badge.timemachine")
                            .foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        if let result = status.lastResult {
                            Text(resultText(result))
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                            if case .rejected(_, let rejection) = result {
                                rejectionActions(rejection)
                            }
                        }
                        if let restore = status.lastRestore {
                            Text(L10n.resultRestore(restore.installed, restore.failed))
                                .font(.callout)
                                .foregroundStyle(restore.failed == 0 ? Color.primary : Color.orange)
                        }
                        if let dump = status.lastROMDump {
                            HStack(spacing: 8) {
                                Text(L10n.resultROM(dump))
                                    .font(.callout)
                                    .foregroundStyle({ if case .saved = dump { return Color.primary } else { return Color.orange } }())
                                if case .saved = dump {
                                    Button(L10n.showInFinder) { openROMFolder() }
                                        .controlSize(.small)
                                }
                            }
                        }
                        if let backup = status.lastBackup {
                            HStack(spacing: 8) {
                                Text(L10n.resultBackup(backup.saved, backup.unchanged, backup.failed,
                                                       complete: backup.complete))
                                    .font(.callout)
                                    .foregroundStyle(backup.complete && backup.failed == 0 ? Color.primary : Color.orange)
                                Button(L10n.showInFinder) { openBackupFolder() }
                                    .controlSize(.small)
                            }
                        }
                    }
                    Spacer()
                    Button {
                        appState.clearResult(tab.id)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(4)
            }
        }
    }

    /// Fortschritt einer laufenden Stufe: erledigt, gesamt
    private func progress(_ phase: TabStatus.Phase) -> (Int, Int)? {
        switch phase {
        case .syncing(_, _, let done, let total) where total > 0: return (done, total)
        case .restoring(_, _, let done, let total): return (done, total)
        case .backingUp(_, _, let done, let total): return (done, total)
        case .dumpingROM(_, let done, let total): return (done, total)
        default: return nil
        }
    }

    @ViewBuilder
    private func rejectionActions(_ rejection: TabStatus.Rejection) -> some View {
        let user: PalmUser = {
            switch rejection {
            case .wrongPalm(let found, _), .unknown(let found): return found
            }
        }()
        HStack(spacing: 8) {
            Button(L10n.assignThisProfile(appState.profileName(tab.profileId))) {
                appState.assign(user, to: tab.profileId)
            }
            if case .unknown = rejection {
                Button(L10n.createProfileFromPalm) {
                    appState.createProfile(from: user, port: tab.port)
                }
            }
        }
        .controlSize(.small)
        Text(L10n.assignHint)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func resultIcon(_ result: TabStatus.Result) -> String {
        switch result {
        case .finished(_, _, let failed): return failed > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        case .timedOut: return "clock.badge.exclamationmark"
        case .failed: return "xmark.octagon.fill"
        case .rejected: return "person.crop.circle.badge.exclamationmark"
        case .stopped: return "stop.circle"
        }
    }

    private func resultColor(_ result: TabStatus.Result) -> Color {
        switch result {
        case .finished(_, _, let failed): return failed > 0 ? .orange : .green
        case .timedOut, .failed, .rejected: return .red
        case .stopped: return .secondary
        }
    }

    private func resultText(_ result: TabStatus.Result) -> String {
        func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
        switch result {
        case .finished(let date, let installed, let failed):
            return L10n.resultFinished(time(date), installed, failed)
        case .timedOut(let date):
            return L10n.resultTimedOut(time(date))
        case .failed(let date, let message):
            return L10n.resultFailed(time(date), message)
        case .rejected(let date, let rejection):
            let expected = appState.deviceManager.profile(tab.profileId)
            let expectedText = expected.map {
                $0.isBound ? L10n.identity($0.username, UInt32(truncatingIfNeeded: $0.userId))
                           : L10n.identityUnbound($0.username)
            } ?? "?"
            switch rejection {
            case .wrongPalm(let found, let owner):
                return L10n.resultWrongPalm(time(date), L10n.identity(found.name, found.userId),
                                            appState.profileName(owner), expectedText)
            case .unknown(let found):
                return L10n.resultUnknownPalm(time(date), L10n.identity(found.name, found.userId), expectedText)
            }
        case .stopped(let date):
            return L10n.resultStopped(time(date))
        }
    }
}

// MARK: - Warteschlange

struct QueueSection: View {
    @Environment(AppState.self) var appState
    let queue: InstallQueue
    let profileId: UUID
    let isSyncing: Bool

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                if queue.items.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "tray.and.arrow.down")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                            Text(L10n.queueEmpty)
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 12)
                        Spacer()
                    }
                } else {
                    ForEach(queue.items) { item in
                        queueRow(item)
                    }
                }
            }
            .padding(4)
        } label: {
            HStack {
                Label(L10n.queueLabel, systemImage: "tray.full")
                Spacer()
                Text(queue.invalidCount == 0
                     ? L10n.queueFiles(queue.items.count)
                     : L10n.queueFilesInvalid(queue.items.count, queue.invalidCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func queueRow(_ item: InstallQueue.QueueItem) -> some View {
        let look = rowLook(item.status)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: look.icon)
                .foregroundStyle(look.color)
                .font(.callout)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.callout)
                    .lineLimit(1)
                if let details = databaseDetails(item) {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(look.text)
                    .font(.caption)
                    .foregroundStyle(look.textColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(action: { queue.remove(item) }) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.queueRemoveHelp)
            .disabled(isInstalling(item.status))
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background {
            if queue.selection.selected.contains(item.name) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor.opacity(0.18))
            }
        }
        .contentShape(Rectangle())
        // Auswahl wie im Finder: Klick, ⇧-Klick (Bereich), ⌘-Klick (einzeln dazu)
        .onTapGesture {
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            let modifier: ListSelection<String>.Modifier =
                flags.contains(.shift) ? .extend : flags.contains(.command) ? .toggle : .none
            queue.selection.click(item.name, modifier: modifier, order: queue.items.map(\.name))
        }
        // Auf den Reiter eines anderen Geräts ziehen verschiebt die Datei
        // dorthin - gehört sie zur Auswahl, die ganze Auswahl
        .draggable(item.url) {
            dragPreview(count: queue.targets(for: item).count, name: item.name)
        }
        .contextMenu {
            let others = appState.deviceManager.profiles.filter { $0.id != profileId }
            let targets = queue.targets(for: item)
            Menu(targets.count == 1 ? L10n.queueMoveTo : L10n.queueMoveFilesTo(targets.count)) {
                ForEach(others) { profile in
                    Button(profile.username) {
                        appState.move(targets, from: queue, to: profile.id)
                    }
                }
            }
            .disabled(others.isEmpty || targets.allSatisfy { isInstalling($0.status) })
        }
    }

    private func dragPreview(count: Int, name: String) -> some View {
        Label(count == 1 ? name : L10n.queueFiles(count), systemImage: count == 1 ? "doc.fill" : "doc.on.doc.fill")
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func isInstalling(_ status: InstallQueue.Status) -> Bool {
        if case .installing = status { return true }
        return false
    }

    private func databaseDetails(_ item: InstallQueue.QueueItem) -> String? {
        let size = ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
        switch item.status {
        case .ready(let db), .installing(let db), .failed(let db, _):
            return L10n.queueDatabase(db.name, db.version, db.type, db.creator, size)
        case .invalid:
            return size
        }
    }

    private func rowLook(_ status: InstallQueue.Status)
        -> (icon: String, color: Color, text: String, textColor: Color) {
        switch status {
        case .ready:
            return ("doc.fill", .blue, L10n.queueReady, .secondary)
        case .installing:
            return isSyncing
                ? ("arrow.down.doc.fill", .blue, L10n.queueInstalling, .blue)
                : ("hourglass", .orange, L10n.queueWaiting, .orange)
        case .failed(_, let failure):
            return ("exclamationmark.triangle.fill", .red,
                    L10n.queueFailed(L10n.failureText(failure)), .red)
        case .invalid(let problem):
            return ("xmark.octagon.fill", .red, L10n.queueInvalid(L10n.problemText(problem)), .red)
        }
    }
}

// MARK: - Zuletzt installiert

struct InstalledSection: View {
    let queue: InstallQueue

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                if queue.installedItems.isEmpty {
                    HStack {
                        Spacer()
                        Text(L10n.installedEmpty)
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                        Spacer()
                    }
                } else {
                    ForEach(Array(queue.installedItems.prefix(10))) { item in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.callout)
                            Text(item.name)
                                .font(.callout)
                                .lineLimit(1)
                            Spacer()
                            // Feste Zeitangabe statt .relative: eine relative Angabe
                            // zählt Sekunden und zeichnet das Fenster jede Sekunde neu.
                            Text(item.date.formatted(date: .numeric, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
            .padding(4)
        } label: {
            Label(L10n.installedLabel, systemImage: "checkmark.circle")
        }
    }
}

// MARK: - Log des Tabs

struct TabLogSection: View {
    let log: LiveLog

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 2) {
                if log.lines.isEmpty {
                    Text(L10n.logEmpty)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(log.lines) { line in
                                    Text(line.text)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(line.id)
                                }
                            }
                        }
                        .frame(maxHeight: .infinity)
                        // Auf die letzte Zeile-ID achten, nicht auf die Anzahl:
                        // Die bleibt bei vollem Puffer gleich.
                        .onChange(of: log.lines.last?.id) { _, lastId in
                            if let lastId {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .padding(4)
            .frame(maxHeight: .infinity)
        } label: {
            HStack {
                Label(L10n.logLabel, systemImage: "text.alignleft")
                    .foregroundStyle(.primary)
                Spacer()
                if !log.lines.isEmpty {
                    Button(L10n.logCopy) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(log.lines.map(\.text).joined(separator: "\n"),
                                                       forType: .string)
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Text("~/HotSync/hotsync.log")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Das HotSync-Logo im Kopf des Tabs: die beiden Pfeile drehen sich,
/// solange ein HotSync läuft; sonst stehen sie, und ein kleines Abzeichen
/// zeigt den Zustand (lauschen, Anschluss fehlt, …).
struct SyncLogo: View {
    let phase: TabStatus.Phase
    let color: Color
    let icon: String

    @State private var spinning = false

    private static let image: NSImage? = Bundle.main.url(forResource: "HotSyncLogo", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }

    private var isSyncing: Bool {
        switch phase {
        case .restoring, .syncing, .backingUp, .readingCalendar, .dumpingROM: return true
        default: return false
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image = Self.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 36, height: 36)
                    .opacity(isSyncing ? 1 : 0.55)
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .animation(spinning ? .linear(duration: 1.6).repeatForever(autoreverses: false) : .default,
                               value: spinning)
            } else {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 36, height: 36)
            }
            if !isSyncing {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Circle().fill(color))
                    .offset(x: 4, y: 4)
            }
        }
        .frame(width: 40, height: 40)
        .onAppear { spinning = isSyncing }
        .onChange(of: isSyncing) { _, now in spinning = now }
    }
}

/// Probelauf für alle Abgleiche eines Profils: ein Schalter über den
/// Abschnitten, damit er nicht übersehen wird.
struct DryRunSection: View {
    @Environment(AppState.self) var appState
    let profileId: UUID

    var body: some View {
        let on = appState.deviceManager.profile(profileId)?.isDryRun ?? false
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(
                    get: { appState.deviceManager.profile(profileId)?.isDryRun ?? false },
                    set: { appState.setDryRun($0, for: profileId) }
                )) {
                    Text(L10n.dryRunToggle)
                }
                Text(L10n.dryRunHint)
                    .font(.caption)
                    .foregroundStyle(on ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(isOn: Binding(
                    get: { appState.deviceManager.profile(profileId)?.isMassDeleteAllowed ?? false },
                    set: { appState.setAllowMassDelete($0, for: profileId) }
                )) {
                    Text(L10n.massDeleteToggle)
                }
                Text(L10n.massDeleteHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Label(L10n.dryRunTitle, systemImage: "eye")
        }
    }
}

/// Uhr und Zeitzonen: zwei Schalter je Profil.
struct TimeSyncSection: View {
    @Environment(AppState.self) var appState
    let profileId: UUID

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(
                    get: { appState.deviceManager.profile(profileId)?.isClockSyncOn ?? false },
                    set: { appState.setClockSync($0, for: profileId) }
                )) {
                    Text(L10n.clockSyncToggle)
                }
                Text(L10n.clockSyncHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(isOn: Binding(
                    get: { appState.deviceManager.profile(profileId)?.isZoneSyncOn ?? false },
                    set: { appState.setZoneSync($0, for: profileId) }
                )) {
                    Text(L10n.zoneSyncToggle)
                }
                Text(L10n.zoneSyncHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(isOn: Binding(
                    get: { appState.deviceManager.profile(profileId)?.isNetSyncOn ?? false },
                    set: { appState.setNetSync($0, for: profileId) }
                )) {
                    Text(L10n.netSyncToggle)
                }
                Text(L10n.netSyncHint(LocalAddress.ipv4().first?.ip, LocalAddress.computerName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)   // so breit wie die anderen Abschnitte
            .padding(4)
        } label: {
            Label(L10n.timeSyncTitle, systemImage: "clock")
        }
    }
}
