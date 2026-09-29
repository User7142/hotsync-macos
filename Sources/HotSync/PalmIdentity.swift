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

    /// Setzt den Palm-Username. Blockiert bis der Palm verbindet.
    /// Gibt (success, userId) zurueck.
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
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        let completionSemaphore = DispatchSemaphore(value: 0)
        var gotOutput = false

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                DebugLog.shared.log("pilot-install-user: \(trimmed)", source: "Palm")
                gotOutput = true
                completionSemaphore.signal()
            }
        }

        do {
            try process.run()
            DebugLog.shared.log(L10n.logPilotInstallStarted, source: "Palm")

            // Warte auf Output oder Timeout (60 Sek.)
            let result = completionSemaphore.wait(timeout: .now() + 60)

            // pilot-install-user hängt nach Completion — wie pilot-xfer: kurz warten, dann killen
            if gotOutput {
                Thread.sleep(forTimeInterval: 1.0)
            }

            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }

            outputPipe.fileHandleForReading.readabilityHandler = nil

            if gotOutput || result == .timedOut {
                DispatchQueue.main.async {
                    self.currentPalmName = name
                }
                return (true, resolvedUserId)
            }
            return (false, resolvedUserId)
        } catch {
            DebugLog.shared.log(L10n.logSetError("\(error)"), source: "Palm")
            outputPipe.fileHandleForReading.readabilityHandler = nil
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
