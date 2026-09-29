import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @Environment(AppState.self) var appState

    // Timer-basierter Refresh — umgeht @Observable-Tracking-Probleme
    @State private var tick = 0
    @State private var fileLogLines: [String] = []

    private let refreshTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Fixierter Header
            headerSection
            Divider()

            // Content — füllt verfügbaren Platz
            VStack(spacing: 16) {
                if (appState.syncEngine.isActive && !isIdleListening) || appState.isSettingUsername {
                    syncProgressSection
                }

                queueSection

                installedSection

                // Live-Log füllt den restlichen Platz
                fileLogSection
            }
            .padding()
        }
        .frame(minWidth: 480, minHeight: 400)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
        .onReceive(refreshTimer) { _ in
            // Timer erzwingt UI-Refresh durch @State-Änderung
            tick += 1
            fileLogLines = DebugLog.shared.readLastLines(100)
        }
        .sheet(isPresented: Binding(
            get: { appState.showDeviceList },
            set: { appState.showDeviceList = $0 }
        )) {
            DeviceListView()
                .environment(appState)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            // Status-Badge
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 36, height: 36)

                Image(systemName: statusIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                // tick erzwingt Text-Refresh
                Text(statusText)
                    .font(.headline)
                    .id("status-\(tick)")
                Text(statusDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .id("detail-\(tick)")
            }

            Spacer()

            // Language Toggle
            Picker("", selection: Binding(
                get: { appState.language },
                set: { appState.language = $0 }
            )) {
                ForEach(Language.allCases, id: \.self) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)

            // Device-Selector
            if appState.deviceManager.profiles.count > 0 {
                DeviceSelectorView()
                    .environment(appState)
            }

            // Sync / Abbrechen Button
            if (appState.syncEngine.isActive && !isIdleListening) || appState.isSettingUsername {
                Button(action: { appState.syncEngine.cancelSync() }) {
                    Label(L10n.cancel, systemImage: "xmark.circle")
                }
                .controlSize(.large)
            } else {
                Button {
                    appState.startListening()
                } label: {
                    Label(
                        appState.installQueue.pendingFiles.isEmpty
                            ? L10n.syncStart
                            : L10n.syncStartN(appState.installQueue.pendingFiles.count),
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                .controlSize(.large)
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(16)
    }

    // MARK: - Sync Progress

    private var syncProgressSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if appState.isSettingUsername {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(L10n.progressSettingUsername)
                            .font(.callout)
                            .fontWeight(.medium)
                    }
                } else if appState.syncEngine.state == .listening {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(L10n.progressWaiting)
                            .font(.callout)
                            .fontWeight(.medium)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc.fill")
                            .foregroundStyle(.blue)
                        Text(appState.syncEngine.currentFileName)
                            .font(.system(.callout, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        if appState.syncEngine.totalFiles > 1 {
                            Text("\(appState.syncEngine.currentFileIndex + 1)/\(appState.syncEngine.totalFiles)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    ProgressView(value: appState.syncEngine.progress)
                        .tint(.blue)
                }
            }
            .padding(4)
            .id("progress-\(tick)")
        } label: {
            Label(L10n.progressLabel, systemImage: "arrow.triangle.2.circlepath")
        }
    }

    // MARK: - Queue

    private var queueSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                if appState.installQueue.pendingFiles.isEmpty {
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
                    ForEach(appState.installQueue.pendingFiles, id: \.absoluteString) { file in
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(.blue)
                                .font(.callout)
                            Text(file.lastPathComponent)
                                .font(.callout)
                                .lineLimit(1)
                            Spacer()
                            Button(action: {
                                appState.installQueue.removeFromQueue(file)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(4)
            .id("queue-\(tick)")
        } label: {
            HStack {
                Label(L10n.queueLabel, systemImage: "tray.full")
                Spacer()
                Text(L10n.queueFiles(appState.installQueue.pendingFiles.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Installed

    private var installedSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                if appState.installQueue.installedItems.isEmpty {
                    HStack {
                        Spacer()
                        Text(L10n.installedEmpty)
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                        Spacer()
                    }
                } else {
                    ForEach(Array(appState.installQueue.installedItems.prefix(10))) { item in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.callout)
                            Text(item.name)
                                .font(.callout)
                                .lineLimit(1)
                            Spacer()
                            Text(item.date, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
            .padding(4)
            .id("installed-\(tick)")
        } label: {
            Label(L10n.installedLabel, systemImage: "checkmark.circle")
        }
    }

    // MARK: - File-Based Live Log

    private var fileLogSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 2) {
                if fileLogLines.isEmpty {
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
                                ForEach(Array(fileLogLines.enumerated()), id: \.offset) { idx, line in
                                    Text(line)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(idx)
                                }
                            }
                        }
                        .frame(maxHeight: .infinity)
                        .onChange(of: fileLogLines.count) { _, newCount in
                            if newCount > 0 {
                                proxy.scrollTo(newCount - 1, anchor: .bottom)
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
                if !fileLogLines.isEmpty {
                    Button(L10n.logCopy) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(fileLogLines.joined(separator: "\n"), forType: .string)
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

    // MARK: - Helpers

    private var isIdleListening: Bool {
        appState.syncEngine.isIdleListening
    }

    private var statusColor: Color {
        if appState.isSettingUsername { return .purple }
        if isIdleListening { return .green }
        switch appState.syncEngine.state {
        case .syncing: return .blue
        case .listening: return .orange
        case .finished: return .green
        case .error: return .red
        case .idle: return .gray
        }
    }

    private var statusIcon: String {
        if appState.isSettingUsername { return "person.crop.circle" }
        if isIdleListening { return "antenna.radiowaves.left.and.right" }
        switch appState.syncEngine.state {
        case .syncing: return "arrow.triangle.2.circlepath"
        case .listening: return "antenna.radiowaves.left.and.right"
        case .finished: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .idle: return "power.circle"
        }
    }

    private var statusText: String {
        if appState.isSettingUsername { return L10n.statusSettingUsername }

        let palmName = appState.palmIdentity.currentPalmName
        let prefix = palmName.isEmpty ? "" : "[\(palmName)] "

        if isIdleListening {
            return "\(prefix)\(L10n.statusReady)"
        }

        switch appState.syncEngine.state {
        case .syncing: return "\(prefix)\(L10n.statusSyncing)"
        case .listening: return "\(prefix)\(L10n.statusWaiting)"
        case .finished: return "\(prefix)\(L10n.statusFinished)"
        case .error(let msg): return L10n.statusError(msg)
        case .idle:
            return appState.installQueue.pendingFiles.isEmpty
                ? "\(prefix)\(L10n.statusReady)"
                : "\(prefix)\(L10n.statusFilesReady(appState.installQueue.pendingFiles.count))"
        }
    }

    private var statusDetail: String {
        if appState.isSettingUsername { return L10n.detailSettingUsername }

        if isIdleListening {
            return L10n.detailListening
        }

        switch appState.syncEngine.state {
        case .syncing:
            return L10n.detailSyncing(appState.syncEngine.currentFileIndex + 1, appState.syncEngine.totalFiles)
        case .listening:
            return L10n.detailWaiting
        case .finished:
            return L10n.detailFinished(appState.syncEngine.totalFiles)
        case .error:
            return L10n.detailError
        case .idle:
            return appState.installQueue.pendingFiles.isEmpty
                ? L10n.detailIdleEmpty
                : L10n.detailIdleFiles
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      InstallQueue.supportedExtensions.contains(url.pathExtension.lowercased()) else { return }

                let dest = self.appState.installQueue.installDir.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: url, to: dest)

                DispatchQueue.main.async {
                    self.appState.installQueue.enqueue(dest)
                }
            }
        }
    }
}
