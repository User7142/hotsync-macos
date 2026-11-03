import Foundation
import Testing
import HotSyncCore
@testable import PalmSync

/// hotsync-session replaced by a script: the lines it would print, in
/// order, and a record of the commands it was sent.
private final class ScriptedTransport: RecordTransport, @unchecked Sendable {
    private var lines: [String]
    private(set) var sent: [String] = []

    init(_ lines: [String]) { self.lines = lines }

    func send(_ command: String) async throws { sent.append(command) }

    func receive() async throws -> SessionEvent? {
        guard !lines.isEmpty else { return nil }
        let line = lines.removeFirst()
        return SessionEvent.parse(line) ?? { Issue.record("script line is not an event: \(line)"); return nil }()
    }
}

@Test func waitsForThePalmAndItsSyncInfo() async throws {
    let script = ScriptedTransport([
        #"{"event":"listening","port":"usb:"}"#,
        #"{"event":"connected","user":"Zoë Leto","userId":4242,"romVersion":84017152}"#,
        #"{"event":"syncInfo","lastSyncPC":7,"lastSyncDate":1792368000,"successfulSyncDate":1792368000}"#,
    ])
    let bridge = RecordBridge(transport: script)
    let palm = try await bridge.waitForPalm()
    #expect(palm.user == PalmUser(name: "Zoë Leto", userId: 4242))
    #expect(palm.lastSyncPC == 7 && palm.lastSyncDate == Date(timeIntervalSince1970: 1_792_368_000))
    #expect(await bridge.takeSidelined() == [.listening(port: "usb:")])
}

@Test func readsADatabase() async throws {
    let script = ScriptedTransport([
        #"{"event":"dbOpened","name":"CalendarDB-PDat","records":2}"#,
        #"{"event":"appInfo","data":"AAEC"}"#,
        #"{"event":"record","id":4097,"index":0,"attrs":0,"category":1,"data":"CQAKAPVUBABTdGFuZHVwAA=="}"#,
        #"{"event":"record","id":4098,"index":1,"attrs":192,"category":0,"data":""}"#,
        #"{"event":"recordsDone","count":2,"modifiedOnly":0}"#,
        #"{"event":"dbClosed"}"#,
    ])
    let bridge = RecordBridge(transport: script)
    #expect(try await bridge.openDatabase("CalendarDB-PDat") == 2)
    #expect(try await bridge.readAppInfo() == Data([0, 1, 2]))
    let records = try await bridge.readAllRecords()
    #expect(records.count == 2)
    #expect(records[0].id == 0x1001 && records[0].category == 1)
    #expect(try CalendarEvent(data: records[0].data).title == "Standup")
    #expect(records[1].isDeleted && records[1].data.isEmpty)
    try await bridge.closeDatabase()
    #expect(script.sent == ["opendb r CalendarDB-PDat", "readappinfo", "readall", "closedb"])
}

@Test func writesAndDeletesRecords() async throws {
    let script = ScriptedTransport([
        #"{"event":"dbOpened","name":"CalendarDB-PDat","records":0}"#,
        #"{"event":"recordWritten","id":5000,"bytes":4}"#,
        #"{"event":"record","id":5000,"index":0,"attrs":64,"category":2,"data":"AQIDBA=="}"#,
        #"{"event":"recordDeleted","id":5000}"#,
        #"{"event":"flagsReset"}"#,
        #"{"event":"cleanedUp"}"#,
        #"{"event":"syncInfoWritten","pcId":7,"date":1792368000}"#,
    ])
    let bridge = RecordBridge(transport: script)
    try await bridge.openDatabase("CalendarDB-PDat", writable: true)
    let id = try await bridge.writeRecord(id: nil, attributes: 0x40, category: 2, data: Data([1, 2, 3, 4]))
    #expect(id == 5000)
    let back = try await bridge.readRecord(id: id)
    #expect(back.data == Data([1, 2, 3, 4]) && back.category == 2)
    try await bridge.deleteRecord(id: id)
    try await bridge.resetSyncFlags()
    try await bridge.cleanUp()
    #expect(try await bridge.writeSyncInfo(pcID: 7) == Date(timeIntervalSince1970: 1_792_368_000))
    #expect(script.sent == ["opendb rw CalendarDB-PDat", "writerec 0 64 2 AQIDBA==", "readrec 5000", "deleterec 5000",
                            "resetflags", "cleanup", "syncinfo 7"])
}

@Test func commandErrorsAreThrown() async throws {
    let script = ScriptedTransport([
        #"{"event":"error","stage":"opendb","message":"cannot open the database","error":-301,"palmOSError":519}"#,
        #"{"event":"progress","bytes":10}"#,
        #"{"event":"error","stage":"backup","message":"unrelated"}"#,
        #"{"event":"dbOpened","name":"MemoDB","records":3}"#,
    ])
    let bridge = RecordBridge(transport: script)
    await #expect(throws: BridgeError.command(stage: "opendb", message: "cannot open the database")) {
        try await bridge.openDatabase("NoSuchDB")
    }
    // other events, even other errors, are set aside until the answer comes
    #expect(try await bridge.openDatabase("MemoDB") == 3)
    #expect(await bridge.takeSidelined() == [.progress(bytes: 10), .error(stage: "backup", message: "unrelated")])
}

@Test func toolEndingMidCommandIsAnError() async throws {
    let bridge = RecordBridge(transport: ScriptedTransport([#"{"event":"record","id":1,"index":0,"attrs":0,"category":0,"data":""}"#]))
    await #expect(throws: BridgeError.ended) {
        try await bridge.readModifiedRecords()
    }
}

@Test func endWaitsForFinished() async throws {
    let script = ScriptedTransport([#"{"event":"backupFinished","saved":1,"unchanged":2,"failed":0}"#, #"{"event":"finished"}"#])
    let bridge = RecordBridge(transport: script)
    try await bridge.end()
    #expect(script.sent == ["end"])
    #expect(await bridge.takeSidelined() == [.backupFinished(saved: 1, unchanged: 2, failed: 0)])
}
