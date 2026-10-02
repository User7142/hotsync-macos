import SwiftUI
import HotSyncCore

/// Inhalt eines Tabs: Anschluss und Zustand, Ergebnis der letzten Sitzung,
/// Warteschlange des Profils, zuletzt installiert und das Log des Tabs.
struct TabDetailView: View {
    @Environment(AppState.self) var appState
    let tab: SyncTab
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            header
            if let status = appState.status(tab.id) {
                if status.isSyncing || status.lastResult != nil {
                    resultBox(status)
                }
            }
            if let queue = appState.queue(for: tab) {
                QueueSection(queue: queue, isSyncing: appState.status(tab.id)?.isSyncing == true)
                InstalledSection(queue: queue)
            }
            if let status = appState.status(tab.id) {
                TabLogSection(log: status.log)
            }
        }
        .padding()
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(phaseColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                Image(systemName: phaseIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(phaseColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.title(of: tab))
                    .font(.headline)
                Text(phaseText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(portText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

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
                .controlSize(.large)
            } else {
                Button {
                    appState.startTab(tab.id)
                } label: {
                    Label(L10n.tabSyncNow, systemImage: "arrow.triangle.2.circlepath")
                }
                .controlSize(.large)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!appState.portMonitor.isConnected(tab.port))
                .help(L10n.tabSyncNowHelp)
            }
        }
    }

    private var phase: TabStatus.Phase {
        appState.status(tab.id)?.phase ?? .idle
    }

    private var phaseColor: Color {
        switch phase {
        case .syncing: return .blue
        case .listening: return .green
        case .waitingForPort: return .orange
        case .idle: return .gray
        }
    }

    private var phaseIcon: String {
        switch phase {
        case .syncing: return "arrow.triangle.2.circlepath"
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
        if !tab.isUSB {
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
        if case .syncing(_, _, let done, let total) = status.phase, total > 0 {
            GroupBox {
                ProgressView(value: Double(done), total: Double(total))
                    .tint(.blue)
                    .padding(4)
            }
        } else if let result = status.lastResult {
            GroupBox {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: resultIcon(result))
                        .foregroundStyle(resultColor(result))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(resultText(result))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        if case .rejected(_, let rejection) = result {
                            rejectionActions(rejection)
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
                    HStack {
                        Spacer()
                        Text(L10n.logEmpty)
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                        Spacer()
                    }
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
