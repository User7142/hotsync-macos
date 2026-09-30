import Foundation
import Observation

@Observable
final class PalmIdentity: @unchecked Sendable {

    var currentPalmName: String = ""
    private var activeProcess: Process?

    /// Liest den aktuellen Palm-Username aus. Blockiert bis der Palm verbindet.
    /// Gibt (username, userId) zurueck, oder nil bei Fehler/Abbruch.
    func checkUsername() -> (name: String, userId: UInt)? {
        guard let tool = findPilotInstallUser() else {
            DebugLog.shared.log(L10n.logPilotInstallNotFound, source: "Palm")
            return nil
        }

        DebugLog.shared.log(L10n.logStartingPilotInstall, source: "Palm")

        let process = Process()
        process.executableURL = tool
        process.arguments = ["-p", "usb:", "-l"]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let completionSemaphore = DispatchSemaphore(value: 0)
        var collectedOutput = ""
        var gotOutput = false

        // Beide Pipes überwachen
        let handleOutput: (FileHandle) -> Void = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            DebugLog.shared.log("pilot-install-user raw: \(output.trimmingCharacters(in: .whitespacesAndNewlines))", source: "Palm")
            collectedOutput += output
            if !gotOutput {
                gotOutput = true
                completionSemaphore.signal()
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = handleOutput
        stderrPipe.fileHandleForReading.readabilityHandler = handleOutput

        do {
            try process.run()
            activeProcess = process
            DebugLog.shared.log(L10n.logPilotInstallRunning, source: "Palm")

            // Warte auf Output oder Timeout (120 Sek.)
            let result = completionSemaphore.wait(timeout: .now() + 120)

            // Kurz warten damit restlicher Output reinkommt
            Thread.sleep(forTimeInterval: 1.5)

            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            activeProcess = nil

            if gotOutput {
                DebugLog.shared.log("Gesamtoutput: \(collectedOutput.trimmingCharacters(in: .whitespacesAndNewlines))", source: "Palm")
                return parseUserInfo(collectedOutput)
            } else if result == .timedOut {
                DebugLog.shared.log(L10n.logTimeout, source: "Palm")
            } else {
                DebugLog.shared.log(L10n.logNoOutput, source: "Palm")
            }
            return nil
        } catch {
            DebugLog.shared.log(L10n.logStartError("\(error)"), source: "Palm")
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            activeProcess = nil
            return nil
        }
    }

    /// Bricht laufenden pilot-install-user Prozess ab.
    func cancelActiveProcess() {
        guard let process = activeProcess, process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
        activeProcess = nil
        DebugLog.shared.log(L10n.logPilotInstallCancelled, source: "Palm")
    }

    /// Setzt den Palm-Username. Blockiert, bis der Palm verbunden, der Name
    /// übertragen und pilot-install-user beendet ist (oder nach 60 Sekunden).
    ///
    /// Erfolg heißt: der Prozess hat sich mit Status 0 beendet und keine
    /// Fehlermeldung ausgegeben. "-q" unterdrückt jede Ausgabe, darauf darf
    /// man also nicht warten - das Prozessende weckt den Wartenden.
    func setUsername(_ name: String, userId: UInt? = nil) -> (success: Bool, userId: UInt) {
        guard let tool = findPilotInstallUser() else {
            DebugLog.shared.log(L10n.logPilotInstallNotFound, source: "Palm")
            return (false, 0)
        }

        // User-ID: uebergeben oder zufaellig 5-stellig generieren
        let resolvedUserId = userId ?? UInt.random(in: 10000...99999)

        let process = Process()
        process.executableURL = tool
        process.arguments = ["-p", "usb:", "-u", name, "-i", "\(resolvedUserId)", "-q"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let wakeUp = DispatchSemaphore(value: 0)
        let collected = OutputBuffer()

        func attach(_ pipe: Pipe) {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    DebugLog.shared.log("pilot-install-user: \(trimmed)", source: "Palm")
                    collected.append(trimmed)
                    wakeUp.signal()
                }
            }
        }
        attach(outputPipe)
        attach(errorPipe)
        process.terminationHandler = { _ in wakeUp.signal() }

        do {
            try process.run()
            activeProcess = process
            DebugLog.shared.log(L10n.logPilotInstallStarted, source: "Palm")

            // Bis zum Prozessende oder zu einer Fehlerausgabe, höchstens 60 s
            let deadline = Date().addingTimeInterval(60)
            while process.isRunning, !collected.hasError, Date() < deadline {
                _ = wakeUp.wait(timeout: .now() + 1)
            }
            // Letzte Ausgabe kann noch in der Pipe stecken
            Thread.sleep(forTimeInterval: 0.3)

            let ended = !process.isRunning
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            activeProcess = nil

            let success = ended && process.terminationStatus == 0 && !collected.hasError
            DebugLog.shared.log(
                "pilot-install-user: \(success ? "OK" : "fehlgeschlagen") (beendet: \(ended), Status \(process.terminationStatus))",
                source: "Palm")
            if success {
                DispatchQueue.main.async {
                    self.currentPalmName = name
                }
            }
            return (success, resolvedUserId)
        } catch {
            DebugLog.shared.log(L10n.logSetError("\(error)"), source: "Palm")
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            activeProcess = nil
            return (false, resolvedUserId)
        }
    }

    // MARK: - Private

    private func parseUserInfo(_ output: String) -> (name: String, userId: UInt)? {
        var name = ""
        var userId: UInt = 0

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Palm user:") {
                name = trimmed
                    .replacingOccurrences(of: "Palm user:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("UserID:") {
                let idStr = trimmed
                    .replacingOccurrences(of: "UserID:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                userId = UInt(idStr) ?? 0
            }
        }

        return (name, userId)
    }

    private func findPilotInstallUser() -> URL? {
        // 1. Im App-Bundle suchen
        if let bundled = Bundle.main.url(forResource: "pilot-install-user", withExtension: nil) {
            return bundled
        }

        // 2. Bekannte Pfade pruefen
        let knownPaths = [
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/pilot-install-user",
            "/usr/local/bin/pilot-install-user",
            "/opt/homebrew/bin/pilot-install-user",
        ]

        for path in knownPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // 3. `which` als Fallback
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["pilot-install-user"]
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
}

/// Sammelt die Ausgabe von pilot-install-user threadsicher und erkennt
/// Fehlermeldungen ("Error accepting data on usb:" u. ä.).
final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ line: String) {
        lock.lock()
        text += line + "\n"
        lock.unlock()
    }

    var hasError: Bool {
        lock.lock()
        defer { lock.unlock() }
        return text.localizedCaseInsensitiveContains("error")
    }
}
