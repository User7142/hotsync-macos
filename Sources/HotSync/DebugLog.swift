import Foundation
import Observation
import os

/// File-basierter Logger, unabhängig von SwiftUI @Observable.
/// Schreibt nach ~/HotSync/hotsync.log UND hält einen In-Memory-Buffer.
final class DebugLog: @unchecked Sendable {
    static let shared = DebugLog()

    private let logger = Logger(subsystem: "com.palm.hotsync.macos", category: "sync")
    private let logFileURL: URL
    private let queue = DispatchQueue(label: "com.palm.hotsync.debuglog")
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("HotSync")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.logFileURL = dir.appendingPathComponent("hotsync.log")

        // Log-Datei bei jedem App-Start leeren
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        writeToFile(L10n.logAppStarted)
        publish(L10n.logAppStarted)
    }

    func log(_ message: String, source: String = "App") {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(source)] \(message)"

        // os.Logger für Console.app
        logger.info("\(line, privacy: .public)")

        // File
        writeToFile(line)

        // Live-Anzeige im Hauptfenster
        publish(line)
    }

    /// Reicht eine Zeile an die Live-Anzeige weiter. LiveLog wird nur auf dem
    /// Main-Thread geändert, log() darf aber von jedem Thread kommen.
    private func publish(_ line: String) {
        DispatchQueue.main.async {
            LiveLog.shared.append(line)
        }
    }

    private func writeToFile(_ line: String) {
        queue.async { [self] in
            if let data = (line + "\n").data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                } else {
                    try? data.write(to: self.logFileURL)
                }
            }
        }
    }
}

/// Die letzten Log-Zeilen für die Live-Anzeige im Hauptfenster.
///
/// Beobachtbar, damit SwiftUI jede neue Zeile sofort zeichnet - statt die
/// komplette Log-Datei per Timer immer wieder einzulesen. Die Datei wird beim
/// App-Start geleert, der Puffer zeigt also dasselbe wie ihr Ende.
/// Nur auf dem Main-Thread ändern (siehe DebugLog.publish).
@Observable
final class LiveLog {
    struct Line: Identifiable {
        let id: Int
        let text: String
    }

    static let shared = LiveLog()

    /// So viele Zeilen zeigt das Hauptfenster.
    static let capacity = 100

    private(set) var lines: [Line] = []
    private var nextId = 0

    fileprivate func append(_ text: String) {
        lines.append(Line(id: nextId, text: text))
        nextId += 1
        if lines.count > Self.capacity {
            lines.removeFirst(lines.count - Self.capacity)
        }
    }
}
