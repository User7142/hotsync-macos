import Foundation
import HotSyncCore

/// The line protocol of hotsync-session from the Mac's side: commands go
/// in, events come out. The bridge does not care what carries them.
public protocol RecordTransport: AnyObject, Sendable {
    func send(_ command: String) async throws
    /// The next event; nil once the tool has ended.
    func receive() async throws -> SessionEvent?
}

public enum BridgeError: Error, Equatable, Sendable {
    /// hotsync-session answered the command with an error event.
    case command(stage: String, message: String)
    /// The tool ended before it answered.
    case ended
    /// An answer that does not fit the command.
    case unexpected(String)
}

/// Drives the record-level commands of hotsync-session: one call per
/// command, returning when the tool has answered. Events that are not
/// answers (connected, syncInfo, progress, the backup's) are kept in
/// `sidelined` for whoever is interested.
public actor RecordBridge {
    private let transport: RecordTransport
    public private(set) var sidelined: [SessionEvent] = []

    public init(transport: RecordTransport) {
        self.transport = transport
    }

    public func takeSidelined() -> [SessionEvent] {
        defer { sidelined = [] }
        return sidelined
    }

    // MARK: Session

    /// Reads events until a Palm has connected; returns its user and the
    /// sync info that follows (nil if the tool reported none).
    public func waitForPalm() async throws -> (user: PalmUser, romVersion: UInt32, lastSyncPC: UInt32, lastSyncDate: Date?) {
        let (user, rom) = try await expect("connect") { event -> (PalmUser, UInt32)? in
            if case .connected(let user, let rom, _) = event { return (user, rom) }
            return nil
        }
        // syncInfo comes right behind connected
        let info = try await expect("connect") { event -> (UInt32, Date?)? in
            if case .syncInfo(let pc, let date) = event { return (pc, date) }
            return nil
        }
        return (user, rom, info.0, info.1)
    }

    public func log(_ text: String) async throws {
        try await transport.send("log \(text)")
    }

    public func end() async throws {
        try await transport.send("end")
        while let event = try await transport.receive() {
            if case .finished = event { return }
            sidelined.append(event)
        }
    }

    // MARK: Databases

    /// Opens the database and returns its record count (-1 if unknown).
    @discardableResult
    public func openDatabase(_ name: String, writable: Bool = false) async throws -> Int {
        try await transport.send("opendb \(writable ? "rw" : "r") \(name)")
        return try await expect("opendb") { event -> Int? in
            if case .dbOpened(_, let records) = event { return records }
            return nil
        }
    }

    public func closeDatabase() async throws {
        try await transport.send("closedb")
        try await expect("closedb") { event -> Bool? in
            if case .dbClosed = event { return true }
            return nil
        }
    }

    public func readAppInfo() async throws -> Data {
        try await transport.send("readappinfo")
        return try await expect("readappinfo") { event -> Data? in
            if case .appInfo(let data) = event { return data }
            return nil
        }
    }

    public func writeAppInfo(_ data: Data) async throws {
        try await transport.send("writeappinfo \(data.base64EncodedString())")
        try await expect("writeappinfo") { event -> Bool? in
            if case .appInfoWritten = event { return true }
            return nil
        }
    }

    // MARK: Records

    public func readAllRecords() async throws -> [PalmRecordIn] {
        try await transport.send("readall")
        return try await collectRecords(stage: "readall")
    }

    /// The records changed since the last sync, deleted ones included
    /// (without data).
    public func readModifiedRecords() async throws -> [PalmRecordIn] {
        try await transport.send("readmodified")
        return try await collectRecords(stage: "readmodified")
    }

    public func readRecord(id: UInt32) async throws -> PalmRecordIn {
        try await transport.send("readrec \(id)")
        return try await expect("readrec") { event -> PalmRecordIn? in
            if case .record(let id, _, let attrs, let category, let data) = event {
                return PalmRecordIn(id: id, attributes: attrs, category: category, data: data)
            }
            return nil
        }
    }

    /// Writes a record; `id` nil lets the Palm assign one. Returns the ID
    /// the record has on the Palm.
    public func writeRecord(id: UInt32?, attributes: UInt8 = 0, category: Int, data: Data) async throws -> UInt32 {
        try await transport.send("writerec \(id ?? 0) \(attributes) \(category) \(data.base64EncodedString())")
        return try await expect("writerec") { event -> UInt32? in
            if case .recordWritten(let id, _) = event { return id }
            return nil
        }
    }

    public func deleteRecord(id: UInt32) async throws {
        try await transport.send("deleterec \(id)")
        try await expect("deleterec") { event -> Bool? in
            if case .recordDeleted = event { return true }
            return nil
        }
    }

    public func resetSyncFlags() async throws {
        try await transport.send("resetflags")
        try await expect("resetflags") { event -> Bool? in
            if case .flagsReset = event { return true }
            return nil
        }
    }

    public func cleanUp() async throws {
        try await transport.send("cleanup")
        try await expect("cleanup") { event -> Bool? in
            if case .cleanedUp = event { return true }
            return nil
        }
    }

    /// Marks this Mac as the last PC that synced; returns the time the Palm
    /// was given.
    @discardableResult
    public func writeSyncInfo(pcID: UInt32) async throws -> Date {
        try await transport.send("syncinfo \(pcID)")
        return try await expect("syncinfo") { event -> Date? in
            if case .syncInfoWritten(_, let date) = event { return date }
            return nil
        }
    }

    // MARK: Answers

    private func collectRecords(stage: String) async throws -> [PalmRecordIn] {
        var records: [PalmRecordIn] = []
        _ = try await expect(stage) { event -> Int? in
            switch event {
            case .record(let id, _, let attrs, let category, let data):
                records.append(PalmRecordIn(id: id, attributes: attrs, category: category, data: data))
                return nil
            case .recordsDone(let count, _):
                return count
            default:
                return nil
            }
        }
        return records
    }

    /// Reads events until `answer` accepts one. An error event of the
    /// command's stage is the command failing; anything else is sidelined.
    @discardableResult
    private func expect<T>(_ stage: String, _ answer: (SessionEvent) -> T?) async throws -> T {
        while let event = try await transport.receive() {
            if let value = answer(event) { return value }
            if case .error(let errorStage, let message) = event, errorStage == stage {
                throw BridgeError.command(stage: stage, message: message)
            }
            sidelined.append(event)
        }
        throw BridgeError.ended
    }
}

/// hotsync-session as a child process: commands down its stdin, events
/// from its stdout, stderr to a callback.
public final class ProcessTransport: RecordTransport, @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let lines: AsyncStream<String>
    private var iterator: AsyncStream<String>.AsyncIterator
    private let onStderr: @Sendable (String) -> Void

    public init(tool: URL, port: String, timeout: Int = 0, baudRate: Int = 57600,
                onStderr: @escaping @Sendable (String) -> Void = { _ in }) {
        process.executableURL = tool
        process.arguments = ["--port", port, "--timeout", String(timeout)]
        var environment = ProcessInfo.processInfo.environment
        environment["PILOTRATE"] = String(baudRate)
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        self.onStderr = onStderr

        let (stream, continuation) = AsyncStream<String>.makeStream()
        lines = stream
        iterator = stream.makeAsyncIterator()
        let output = self.output
        Thread.detachNewThread {
            Self.readLines(output.fileHandleForReading) { continuation.yield($0) }
            continuation.finish()
        }
        let errors = self.errors
        Thread.detachNewThread {
            Self.readLines(errors.fileHandleForReading) { onStderr($0) }
        }
    }

    public func start() throws {
        try process.run()
    }

    public var isRunning: Bool { process.isRunning }

    public func send(_ command: String) async throws {
        guard let data = (command + "\n").data(using: .utf8) else { return }
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    public func receive() async throws -> SessionEvent? {
        while let line = await iterator.next() {
            if let event = SessionEvent.parse(line) { return event }
            onStderr("not an event: \(line)")
        }
        return nil
    }

    public func kill() {
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
                if let line = String(data: lineData, encoding: .utf8), !line.isEmpty { onLine(line) }
            }
        }
        if let rest = String(data: buffer, encoding: .utf8), !rest.isEmpty { onLine(rest) }
    }
}
