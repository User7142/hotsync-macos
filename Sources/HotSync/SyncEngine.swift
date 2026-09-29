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

    /// Wartezeit auf den HotSync-Druck, bevor pilot-xfer aufgibt.
    private let connectTimeout: TimeInterval = 60
    /// Nach Verbindungsaufbau: maximale Zeit ohne jede Ausgabe.
    private let idleTimeout: TimeInterval = 30

    // Es läuft immer höchstens EIN pilot-xfer: zwei Prozesse konkurrieren
    // sonst um die USB-Verbindung, und der Palm redet mit dem falschen.
    // Jede Sitzung hat eine Nummer; ein abgebrochener Durchlauf darf danach
    // weder einen Prozess starten noch den Zustand der neuen Sitzung ändern.
    private let processLock = NSLock()
    private var currentProcess: Process?
    private var activeSession = 0

    /// Startet den Auto-Listen-Modus: Alle Dateien der Queue werden in EINER
    /// pilot-xfer-Sitzung übertragen - der User drückt einmal HotSync.
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

        let session = beginSession()
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
                self.idleListenSync(session: session)

                DispatchQueue.main.async {
                    guard self.isCurrent(session) else { return }
                    self.isIdleListening = false
                    self.lastSyncedCount = 0
                    self.state = .finished
                    self.appendLog(L10n.logSyncComplete)
                    onComplete()
                    self.returnToIdle(after: 5)
                }
            }
            return
        }

        isIdleListening = false
        appendLog(L10n.logFilesReady(files.count))

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let installed = self.installFilesSync(files, session: session)

            DispatchQueue.main.async {
                guard self.isCurrent(session) else { return }

                // Nur tatsächlich übertragene Dateien wandern nach Installed/,
                // der Rest bleibt in Install/ und wird beim nächsten HotSync
                // erneut angeboten.
                for file in files {
                    if installed.contains(file) {
                        queue.markInstalled(file)
                        self.appendLog(L10n.logFileInstalled(file.lastPathComponent))
                    } else {
                        self.appendLog(L10n.logFileNotInstalled(file.lastPathComponent))
                    }
                }

                self.currentFileIndex = self.totalFiles
                self.currentFileName = ""
                self.lastSyncedCount = installed.count
                self.state = .finished
                if installed.count == files.count {
                    self.appendLog(L10n.logAllInstalled(files.count))
                } else {
                    self.appendLog(L10n.logInstalledPartially(installed.count, files.count))
                }
                onComplete()
                self.returnToIdle(after: 5)
            }
        }
    }

    func clearLog() {
        logLines.removeAll()
    }

    func cancelSync(silent: Bool = false) {
        _ = beginSession()          // laufender Durchlauf ist ab jetzt ungültig
        isIdleListening = false
        state = .idle
        if !silent { appendLog(L10n.logCancelled) }

        // Prozess beenden und auf sein Ende warten - erst danach darf ein
        // neuer pilot-xfer die USB-Verbindung öffnen.
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            self.killCurrentProcess()
        }
    }

    // MARK: - Sitzungen und Prozesse

    private func beginSession() -> Int {
        processLock.lock()
        defer { processLock.unlock() }
        activeSession += 1
        return activeSession
    }

    private func isCurrent(_ session: Int) -> Bool {
        processLock.lock()
        defer { processLock.unlock() }
        return session == activeSession
    }

    /// Beendet den laufenden pilot-xfer (SIGKILL) und wartet, bis er weg ist.
    private func killCurrentProcess() {
        processLock.lock()
        let process = currentProcess
        currentProcess = nil
        processLock.unlock()

        guard let process, process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
    }

    private func returnToIdle(after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if self.state == .finished {
                self.state = .idle
            }
        }
    }

    private enum RunResult {
        case finished           // isDone() meldete das Ende der Sitzung
        case exited             // pilot-xfer hat sich selbst beendet
        case timedOut           // keine Verbindung / keine Ausgabe mehr
        case cancelled          // Sitzung wurde ungültig
        case failed(String)     // Start nicht möglich
    }

    /// Startet pilot-xfer für diese Sitzung und reicht jede Ausgabezeile
    /// (stdout und stderr) an `onLine` weiter. Kehrt zurück, sobald `isDone`
    /// true liefert, der Prozess endet oder ein Timeout greift - danach läuft
    /// garantiert kein pilot-xfer mehr.
    private func runPilotXfer(
        _ arguments: [String],
        session: Int,
        onLine: @escaping (String) -> Void,
        isDone: @escaping () -> Bool
    ) -> RunResult {
        guard let pilotXferURL = findPilotXfer() else {
            return .failed(L10n.logPilotXferNotFound)
        }

        // Einen eventuell noch laufenden Vorgänger zuerst sicher beenden
        killCurrentProcess()

        let process = Process()
        process.executableURL = pilotXferURL
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Jede Ausgabe und das Prozessende wecken den wartenden Thread
        let wakeUp = DispatchSemaphore(value: 0)
        let lines = LineCollector()

        func attach(_ pipe: Pipe) {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                for line in lines.append(data, from: ObjectIdentifier(pipe)) {
                    onLine(line)
                }
                wakeUp.signal()
            }
        }
        attach(outputPipe)
        attach(errorPipe)
        process.terminationHandler = { _ in wakeUp.signal() }

        processLock.lock()
        guard session == activeSession else {
            processLock.unlock()
            return .cancelled
        }
        do {
            try process.run()
        } catch {
            processLock.unlock()
            return .failed(error.localizedDescription)
        }
        currentProcess = process
        processLock.unlock()

        var result: RunResult = .exited
        while true {
            let timeout = lines.sawOutput ? idleTimeout : connectTimeout
            let waited = wakeUp.wait(timeout: .now() + timeout)

            if !isCurrent(session) { result = .cancelled; break }
            if isDone() { result = .finished; break }
            if !process.isRunning {
                // Die letzte Ausgabe kann noch in der Pipe stecken
                Thread.sleep(forTimeInterval: 0.5)
                result = isDone() ? .finished : .exited
                break
            }
            if waited == .timedOut { result = .timedOut; break }
        }

        // pilot-xfer schließt die USB-Verbindung nicht immer sauber und
        // beendet sich dann nicht - der Palm braucht den Kill, um aus dem
        // Sync herauszukommen (siehe README, Known issues).
        if case .finished = result {
            Thread.sleep(forTimeInterval: 1.0)
        }
        // Nur den eigenen Prozess beenden - currentProcess kann inzwischen
        // schon zu einer neuen Sitzung gehören.
        processLock.lock()
        if currentProcess === process {
            currentProcess = nil
        }
        processLock.unlock()
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        for line in lines.flush() {
            onLine(line)
        }
        return result
    }

    // MARK: - Idle-Listening und Installation

    /// Idle-Listening: pilot-xfer -l wartet auf Palm, listet Datenbanken.
    /// Gleiche USB-Erkennung wie beim File-Transfer — funktioniert zuverlässig.
    private func idleListenSync(session: Int) {
        DispatchQueue.main.async {
            guard self.isCurrent(session) else { return }
            self.appendLog(L10n.logPilotXferListStarted)
        }

        let connected = Flag()
        let result = runPilotXfer(
            ["-p", "usb:", "-l"],
            session: session,
            onLine: { [weak self] line in
                connected.set()
                DispatchQueue.main.async {
                    guard let self, self.isCurrent(session) else { return }
                    if self.state == .listening { self.state = .syncing }
                    self.appendLog(line)
                }
            },
            isDone: {
                // Nach der ersten Ausgabe noch kurz Zeit für den Rest lassen
                guard let since = connected.since else { return false }
                return Date().timeIntervalSince(since) >= 2.0
            }
        )

        DispatchQueue.main.async {
            guard self.isCurrent(session) else { return }
            switch result {
            case .failed(let message):
                self.state = .error(message)
                self.appendLog(L10n.logError(message))
            case .timedOut where connected.since == nil:
                self.appendLog(L10n.logTimeout)
            case .cancelled:
                break
            default:
                if connected.since != nil {
                    self.appendLog(L10n.logConnectionSuccess)
                }
            }
        }
    }

    /// Überträgt alle Dateien in einer pilot-xfer-Sitzung und liefert die
    /// Dateien zurück, deren Installation pilot-xfer bestätigt hat.
    private func installFilesSync(_ files: [URL], session: Int) -> Set<URL> {
        DispatchQueue.main.async {
            guard self.isCurrent(session) else { return }
            self.currentFileName = files.first?.lastPathComponent ?? ""
            self.appendLog(L10n.logPilotXferStarted)
        }

        let transcript = InstallTranscript(expected: files.map(\.lastPathComponent))
        let result = runPilotXfer(
            ["-p", "usb:", "-i"] + files.map(\.path),
            session: session,
            onLine: { [weak self] line in
                transcript.consume(line)
                let confirmed = transcript.confirmed.count
                let current = transcript.current
                DispatchQueue.main.async {
                    guard let self, self.isCurrent(session) else { return }
                    if self.state == .listening { self.state = .syncing }
                    self.currentFileIndex = confirmed
                    if let current {
                        self.currentFileName = current
                    }
                    self.appendLog(line)
                }
            },
            isDone: { transcript.isComplete }
        )

        DispatchQueue.main.async {
            guard self.isCurrent(session) else { return }
            switch result {
            case .failed(let message):
                self.state = .error(message)
                self.appendLog(L10n.logError(message))
            case .timedOut where !transcript.sawOutput:
                self.appendLog(L10n.logTimeout)
            default:
                break
            }
        }

        return Set(files.filter { transcript.confirmed.contains($0.lastPathComponent) })
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

// MARK: - Hilfstypen

/// Zerlegt die Ausgabe von pilot-xfer in Zeilen. Die Fortschrittsanzeige
/// überschreibt ihre Zeile mit "\r", ein Chunk kann mitten in einer Zeile
/// enden - der Rest wird pro Pipe bis zum nächsten Trenner gepuffert.
final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [ObjectIdentifier: String] = [:]
    private var output = false

    var sawOutput: Bool {
        lock.lock()
        defer { lock.unlock() }
        return output
    }

    func append(_ data: Data, from source: ObjectIdentifier) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        var text = (buffers[source] ?? "") + String(decoding: data, as: UTF8.self)
        var lines: [String] = []
        while let range = text.rangeOfCharacter(from: CharacterSet(charactersIn: "\r\n")) {
            let line = text[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            if !line.isEmpty {
                lines.append(line)
            }
            text.removeSubrange(..<range.upperBound)
        }
        buffers[source] = text
        if !lines.isEmpty {
            output = true
        }
        return lines
    }

    /// Liefert, was nach dem Prozessende noch ohne Zeilenende im Puffer steht.
    func flush() -> [String] {
        lock.lock()
        defer { lock.unlock() }

        let rest = buffers.values
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        buffers.removeAll()
        return rest
    }
}

/// Wertet die Ausgabe von `pilot-xfer -i datei1 datei2 ...` aus
/// (pilot-link src/pilot-xfer.c, palm_install_internal):
///
///     Installing 'a.prc'... Installing 'a.prc' ... (1234 bytes)   1 KiB total.
///     ERROR: pi_file_install failed (...)        <- Übertragung gescheitert
///     ERROR: Unable to open '/pfad/b.prc'!       <- Datei nicht lesbar
///     Thank you for using pilot-link.            <- Sitzung beendet
///
/// "KiB total." folgt nur auf eine erfolgreiche Übertragung - nur dann gilt
/// eine Datei als installiert.
final class InstallTranscript: @unchecked Sendable {
    private let lock = NSLock()
    private let expected: Set<String>
    private var currentName: String?
    private var confirmedNames: Set<String> = []
    private var failedNames: Set<String> = []
    private var ended = false
    private var output = false

    init(expected: [String]) {
        self.expected = Set(expected)
    }

    var confirmed: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return confirmedNames
    }

    var current: String? {
        lock.lock()
        defer { lock.unlock() }
        return currentName
    }

    var sawOutput: Bool {
        lock.lock()
        defer { lock.unlock() }
        return output
    }

    /// Sitzung vorbei: pilot-xfer hat sich verabschiedet oder jede Datei
    /// ist bestätigt bzw. gescheitert.
    var isComplete: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ended || confirmedNames.union(failedNames).isSuperset(of: expected)
    }

    func consume(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        output = true

        if let name = Self.quoted(in: line, after: "Installing '") {
            currentName = name
        }
        if line.contains("KiB total."), let name = currentName {
            confirmedNames.insert(name)
            currentName = nil
        } else if let path = Self.quoted(in: line, after: "Unable to open '") {
            failedNames.insert((path as NSString).lastPathComponent)
        } else if line.contains("ERROR"), let name = currentName {
            failedNames.insert(name)
            currentName = nil
        }
        if line.contains("Thank you for using pilot-link") || line.contains("CANCEL") {
            ended = true
        }
    }

    private static func quoted(in line: String, after prefix: String) -> String? {
        guard let start = line.range(of: prefix),
              let end = line[start.upperBound...].firstIndex(of: "'") else { return nil }
        return String(line[start.upperBound..<end])
    }
}

/// Merkt sich threadsicher, wann etwas zum ersten Mal passiert ist.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date?

    var since: Date? {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func set() {
        lock.lock()
        defer { lock.unlock() }
        if date == nil {
            date = Date()
        }
    }
}
