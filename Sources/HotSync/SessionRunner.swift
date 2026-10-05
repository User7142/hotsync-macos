import Foundation
import HotSyncCore

/// Ein laufendes hotsync-session an einem Anschluss.
///
/// Reicht jedes Ereignis auf dem Main-Thread weiter und meldet das
/// Prozessende erst, wenn alle Ausgabezeilen ausgewertet sind - so kommt
/// "onExit" nie vor dem letzten "installed"/"failed" an.
final class SessionRunner {

    let port: String

    /// Wie sich das Werkzeug beendet hat
    enum Exit: Equatable {
        /// mit diesem Exit-Status (0 Ende, 1 Fehler, 2 Timeout)
        case status(Int32)
        /// durch dieses Signal - abgestürzt oder abgebrochen
        case signal(Int32)
    }

    var onEvent: ((SessionEvent) -> Void)?
    var onExit: ((Exit) -> Void)?

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()

    /// - Parameter timeout: Sekunden bis "kein Palm", 0 = bis gestoppt
    init(port: String, baudRate: Int, timeout: Int) {
        self.port = port
        process.arguments = ["--port", port, "--timeout", String(timeout)]
        var environment = ProcessInfo.processInfo.environment
        // pilot-link liest die serielle Baudrate aus PILOTRATE
        environment["PILOTRATE"] = String(baudRate)
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
    }

    static var toolURL: URL? {
        Bundle.main.url(forResource: "hotsync-session", withExtension: nil)
    }

    func start() throws {
        guard let tool = Self.toolURL else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "hotsync-session"])
        }
        process.executableURL = tool
        try process.run()

        let port = self.port
        // stderr: libpisock meldet manches nur dort - ins Log, nicht in die Logik
        DispatchQueue.global(qos: .utility).async { [errors] in
            Self.readLines(errors.fileHandleForReading) { line in
                DebugLog.shared.log("[\(port)] \(line)", source: "Session")
            }
        }
        // stdout bis EOF lesen, dann erst das Ende melden
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            Self.readLines(output.fileHandleForReading) { line in
                guard let event = SessionEvent.parse(line) else {
                    DebugLog.shared.log(L10n.logSessionBrokenLine(line), source: "Session")
                    return
                }
                DispatchQueue.main.async { self.onEvent?(event) }
            }
            process.waitUntilExit()
            let exit: Exit = process.terminationReason == .uncaughtSignal
                ? .signal(process.terminationStatus)
                : .status(process.terminationStatus)
            DispatchQueue.main.async { self.onExit?(exit) }
        }
    }

    /// Eine Anweisung an das Werkzeug (siehe hotsync-session.c).
    func send(_ command: String) {
        guard process.isRunning, let data = (command + "\n").data(using: .utf8) else { return }
        do {
            try input.fileHandleForWriting.write(contentsOf: data)
        } catch {
            // Das Werkzeug hat sich gerade beendet - sein Ende kommt über onExit.
            DebugLog.shared.log(L10n.logSessionWriteFailed(error.localizedDescription), source: "Session")
        }
    }

    /// Bricht ab: Solange kein Palm verbunden ist, wartet das Werkzeug nur -
    /// beenden ist dann folgenlos. Während einer Übertragung lässt nur der
    /// Kill den Palm aus dem Sync heraus (wie bei pilot-xfer).
    func kill() {
        guard process.isRunning else { return }
        Darwin.kill(process.processIdentifier, SIGKILL)
    }

    private static func readLines(_ handle: FileHandle, _ onLine: (String) -> Void) {
        var buffer = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                    onLine(line)
                }
            }
        }
        if let rest = String(data: buffer, encoding: .utf8), !rest.isEmpty {
            onLine(rest)
        }
    }
}
