import Foundation
import Observation

@Observable
final class SyncEngine: @unchecked Sendable {

    enum State: Equatable {
        case idle               // Kein Sync, keine Dateien
        case listening          // pilot-xfer läuft, wartet auf Palm
        case syncing            // Aktiver Transfer
        case finished           // Sync abgeschlossen
        case error(String)      // Fehler
    }

    private(set) var state: State = .idle
    private(set) var logLines: [String] = []
    private(set) var currentFileIndex = 0
    private(set) var totalFiles = 0
    private(set) var currentFileName = ""
    private(set) var lastSyncedCount = 0

    var progress: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(currentFileIndex) / Double(totalFiles)
    }

    var isActive: Bool {
        switch state {
        case .idle, .finished, .error: return false
        case .listening, .syncing: return true
        }
    }

    /// True wenn der Engine nur auf Verbindung lauscht (ohne Dateien).
    /// Kann abgebrochen werden wenn Dateien dazukommen.
    private(set) var isIdleListening = false

    private var currentProcess: Process?
    private var autoListenEnabled = true
    private let syncTimeout: TimeInterval = 60

    /// Startet den Auto-Listen-Modus: Wenn Dateien in der Queue sind,
    /// wird pilot-xfer für jede Datei gestartet.
    /// Der User drückt einfach HotSync.
    ///
    /// Hinweis: pilot-install-user wird NICHT aufgerufen, weil es die
    /// HotSync-Session verbraucht und danach pilot-xfer nicht mehr
    /// verbinden kann.
    func autoListen(
        queue: InstallQueue,
        palmIdentity: PalmIdentity,
        onComplete: @escaping @Sendable () -> Void
    ) {
        guard !isActive else { return }

        let files = queue.dequeueAll()

        totalFiles = files.count
        currentFileIndex = 0
        currentFileName = ""
        lastSyncedCount = 0
        logLines.removeAll()

        state = .listening

        // Ohne Dateien: Idle-Listening via pilot-xfer -l (wartet auf Palm, listet DBs)
        if files.isEmpty {
            isIdleListening = true
            appendLog(L10n.logWaitingForConnection)

            DispatchQueue.global(qos: .userInitiated).async { [self] in
                if !self.isActive { return }
                self.idleListenSync()

                DispatchQueue.main.async {
                    self.isIdleListening = false

                    // Abgebrochen (z.B. weil Dateien dazukamen)
                    if !self.isActive { return }

                    self.lastSyncedCount = 0
                    self.state = .finished
                    self.appendLog(L10n.logSyncComplete)
                    onComplete()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        if self.state == .finished {
                            self.state = .idle
                        }
                    }
                }
            }
            return
        }

        isIdleListening = false
        appendLog(L10n.logFilesReady(files.count))

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            // Prüfen ob abgebrochen
            if !self.isActive { return }

            // Dateien installieren
            for (index, file) in files.enumerated() {
                DispatchQueue.main.async {
                    self.currentFileIndex = index
                    self.currentFileName = file.lastPathComponent
                }
                self.installFileSync(file, queue: queue)

                // Prüfen ob abgebrochen
                if !self.isActive { return }
            }
            DispatchQueue.main.async {
                self.currentFileIndex = self.totalFiles
                self.currentFileName = ""
                self.lastSyncedCount = self.totalFiles
                self.state = .finished
                self.appendLog(L10n.logAllInstalled(self.totalFiles))
                onComplete()

                // Nach 5 Sekunden zurück auf idle, dann ggf. neue Dateien aufnehmen
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if self.state == .finished {
                        self.state = .idle
                    }
                }
            }
        }
    }

    func clearLog() {
        logLines.removeAll()
    }

    func cancelSync(silent: Bool = false) {
        autoListenEnabled = false
        isIdleListening = false
        currentProcess?.terminate()
        currentProcess = nil
        state = .idle
        if !silent { appendLog(L10n.logCancelled) }
        // Re-enable nach kurzer Pause
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.autoListenEnabled = true
        }
    }

    // MARK: - Private

    /// Idle-Listening: pilot-xfer -l wartet auf Palm, listet Datenbanken.
    /// Gleiche USB-Erkennung wie beim File-Transfer — funktioniert zuverlässig.
    private func idleListenSync() {
        guard let pilotXferURL = findPilotXfer() else {
            DispatchQueue.main.async {
                self.state = .error(L10n.logPilotXferNotFound)
            }
            return
        }

        let process = Process()
        process.executableURL = pilotXferURL
        process.arguments = ["-p", "usb:", "-l"]

        if let resourcePath = Bundle.main.resourcePath {
            var env = ProcessInfo.processInfo.environment
            let frameworksPath = Bundle.main.bundlePath + "/Contents/Frameworks"
            let existingDyld = env["DYLD_LIBRARY_PATH"] ?? ""
            env["DYLD_LIBRARY_PATH"] = "\(frameworksPath):\(resourcePath):\(existingDyld)"
            process.environment = env
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let completionSemaphore = DispatchSemaphore(value: 0)
        var gotOutput = false

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            DispatchQueue.main.async {
                if self?.state == .listening {
                    self?.state = .syncing
                }
                self?.appendLog(trimmed)
            }

            if !gotOutput {
                gotOutput = true
                completionSemaphore.signal()
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            DispatchQueue.main.async {
                self?.appendLog(trimmed)
            }
        }

        do {
            self.currentProcess = process
            try process.run()

            DispatchQueue.main.async {
                self.appendLog(L10n.logPilotXferListStarted)
            }

            // Warte auf Output oder Timeout
            let result = completionSemaphore.wait(timeout: .now() + syncTimeout)

            // Warten damit restlicher Output reinkommt
            if gotOutput {
                Thread.sleep(forTimeInterval: 2.0)
            }

            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }

            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil

            if gotOutput {
                DispatchQueue.main.async {
                    self.appendLog(L10n.logConnectionSuccess)
                }
            } else if result == .timedOut {
                DispatchQueue.main.async {
                    self.appendLog(L10n.logTimeout)
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.state = .error(error.localizedDescription)
            }
        }

        self.currentProcess = nil
    }

    private func installFileSync(_ file: URL, queue: InstallQueue) {
        let fileName = file.lastPathComponent
        DispatchQueue.main.async {
            self.appendLog(L10n.logFileProgress(self.currentFileIndex + 1, self.totalFiles, fileName))
        }

        let pilotXferURL = findPilotXfer()
        guard let pilotXferURL else {
            DispatchQueue.main.async {
                self.state = .error(L10n.logPilotXferNotFound)
                self.appendLog(L10n.logErrorPilotXfer)
            }
            return
        }

        let process = Process()
        process.executableURL = pilotXferURL
        process.arguments = ["-p", "usb:", "-i", file.path]

        // Wichtig: Library-Pfade setzen falls embedded
        if let resourcePath = Bundle.main.resourcePath {
            var env = ProcessInfo.processInfo.environment
            let frameworksPath = Bundle.main.bundlePath + "/Contents/Frameworks"
            let existingDyld = env["DYLD_LIBRARY_PATH"] ?? ""
            env["DYLD_LIBRARY_PATH"] = "\(frameworksPath):\(resourcePath):\(existingDyld)"
            process.environment = env
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let completionSemaphore = DispatchSemaphore(value: 0)
        let syncCompletedFlag = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        syncCompletedFlag.initialize(to: false)

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            DispatchQueue.main.async {
                self?.appendLog(trimmed)

                // Sobald wir Transfer-Output bekommen → syncing
                if self?.state == .listening {
                    self?.state = .syncing
                }
            }

            // NUR "total" erkennen (z.B. "17 KiB total.")
            // NICHT "Install" — das matcht zu früh bei "Installing..."
            if output.lowercased().contains("total") {
                syncCompletedFlag.pointee = true
                completionSemaphore.signal()
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            DispatchQueue.main.async {
                self?.appendLog(trimmed)
            }
        }

        do {
            self.currentProcess = process
            try process.run()

            DispatchQueue.main.async {
                self.appendLog(L10n.logPilotXferStarted)
            }

            // Warte auf "total" im Output oder Timeout
            let result = completionSemaphore.wait(timeout: .now() + syncTimeout)
            let didComplete = syncCompletedFlag.pointee
            syncCompletedFlag.deallocate()

            // Genau wie WRITEUP.md #8: Nach Erkennung von "total"
            // 1 Sekunde warten, dann pilot-xfer killen.
            // pilot-xfer schließt die USB-Verbindung nicht sauber,
            // aber der Palm braucht den Kill um aus dem Sync rauszukommen.
            if didComplete {
                Thread.sleep(forTimeInterval: 1.0)
            }

            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }

            // Cleanup handlers
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil

            if didComplete || result == .timedOut {
                DispatchQueue.main.async {
                    queue.markInstalled(file)
                    self.appendLog(L10n.logFileInstalled(fileName))
                }
            } else if process.terminationStatus == 0 {
                DispatchQueue.main.async {
                    queue.markInstalled(file)
                    self.appendLog(L10n.logFileInstalled(fileName))
                }
            } else {
                DispatchQueue.main.async {
                    self.appendLog(L10n.logExitCode(process.terminationStatus, fileName))
                }
            }
        } catch {
            syncCompletedFlag.deallocate()
            DispatchQueue.main.async {
                self.state = .error(error.localizedDescription)
                self.appendLog(L10n.logError(error.localizedDescription))
            }
        }

        self.currentProcess = nil
    }

    private func findPilotXfer() -> URL? {
        // 1. Im App-Bundle suchen
        if let bundled = Bundle.main.url(forResource: "pilot-xfer", withExtension: nil) {
            return bundled
        }

        // 2. Bekannte Pfade prüfen
        let knownPaths = [
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/pilot-xfer",
            "/usr/local/bin/pilot-xfer",
            "/opt/homebrew/bin/pilot-xfer",
        ]

        for path in knownPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // 3. `which` als Fallback
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["pilot-xfer"]
        let pipe = Pipe()
        which.standardOutput = pipe
        try? which.run()
        which.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return URL(fileURLWithPath: path)
        }

        return nil
    }

    private func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > 100 {
            logLines = Array(logLines.suffix(100))
        }
        DebugLog.shared.log(line, source: "Sync")
    }
}
