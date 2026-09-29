import Foundation
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
    }

    func log(_ message: String, source: String = "App") {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(source)] \(message)"

        // os.Logger für Console.app
        logger.info("\(line, privacy: .public)")

        // File
        writeToFile(line)
    }

    /// Liest die letzten N Zeilen aus der Log-Datei.
    func readLastLines(_ count: Int = 200) -> [String] {
        guard let content = try? String(contentsOf: logFileURL, encoding: .utf8) else {
            return []
        }
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return Array(lines.suffix(count))
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
