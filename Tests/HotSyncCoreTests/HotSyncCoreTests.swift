import Foundation
import Testing
@testable import HotSyncCore

// MARK: - PalmDatabaseFile

/// A minimal database image: header, record list, one byte of data.
private func image(name: String = "DateFix", resource: Bool, records: Int = 1,
                   type: String = "appl", creator: String = "DtFx",
                   truncate: Bool = false) -> Data {
    var bytes = [UInt8](repeating: 0, count: 78)
    for (i, b) in name.utf8.prefix(31).enumerated() { bytes[i] = b }
    bytes[33] = resource ? 0x01 : 0x00
    for (i, b) in type.utf8.prefix(4).enumerated() { bytes[60 + i] = b }
    for (i, b) in creator.utf8.prefix(4).enumerated() { bytes[64 + i] = b }
    bytes[76] = UInt8(records >> 8)
    bytes[77] = UInt8(records & 0xFF)
    let list = records * (resource ? 10 : 8)
    bytes += [UInt8](repeating: 0, count: truncate ? list / 2 : list + 1)
    return Data(bytes)
}

/// An application image with a 'tver' resource behind a 'code' resource.
private func imageWithVersion(_ version: String?) -> Data {
    let resources = version == nil ? 1 : 2
    var bytes = [UInt8](repeating: 0, count: 78)
    for (i, b) in "DateFix".utf8.enumerated() { bytes[i] = b }
    bytes[33] = 0x01
    for (i, b) in "applDtFx".utf8.enumerated() { bytes[60 + i] = b }
    bytes[77] = UInt8(resources)
    let dataStart = 78 + resources * 10 + 2
    func entry(_ type: String, _ id: Int, _ offset: Int) -> [UInt8] {
        Array(type.utf8) + [UInt8(id >> 8), UInt8(id & 0xFF)]
            + [UInt8(offset >> 24), UInt8((offset >> 16) & 0xFF), UInt8((offset >> 8) & 0xFF), UInt8(offset & 0xFF)]
    }
    bytes += entry("code", 1, dataStart)
    if version != nil { bytes += entry("tver", 1, dataStart + 4) }
    bytes += [0, 0]
    bytes += [1, 2, 3, 4]                         // the code resource
    if let version { bytes += Array(version.utf8) + [0] }
    return Data(bytes)
}

@Test func versionOfApplication() throws {
    let file = try PalmDatabaseFile.inspect(data: imageWithVersion("2.0d11"), fileExtension: "prc").get()
    #expect(file.version == "2.0d11")
    let none = try PalmDatabaseFile.inspect(data: imageWithVersion(nil), fileExtension: "prc").get()
    #expect(none.version == nil)
}

@Test func validApplication() throws {
    let file = try PalmDatabaseFile.inspect(data: image(resource: true), fileExtension: "prc").get()
    #expect(file.name == "DateFix")
    #expect(file.type == "appl")
    #expect(file.creator == "DtFx")
    #expect(file.isResourceDatabase)
}

@Test func validRecordDatabase() throws {
    let file = try PalmDatabaseFile.inspect(
        data: image(name: "MemoDB", resource: false, records: 3, type: "DATA", creator: "memo"),
        fileExtension: "PDB").get()
    #expect(file.recordCount == 3)
    #expect(!file.isResourceDatabase)
}

@Test func headerDecidesKindNotExtension() throws {
    let pack = try PalmDatabaseFile.inspect(
        data: image(name: "LEMM_CLASSIC_FUN", resource: true, records: 2, type: "levl", creator: "LEMM"),
        fileExtension: "pdb").get()
    #expect(pack.isResourceDatabase)
    let records = try PalmDatabaseFile.inspect(data: image(resource: false), fileExtension: "prc").get()
    #expect(!records.isResourceDatabase)
}

@Test func rejectsWrongFiles() {
    #expect(PalmDatabaseFile.inspect(data: Data("hello".utf8), fileExtension: "txt")
            == .failure(.unsupportedExtension("txt")))
    #expect(PalmDatabaseFile.inspect(data: Data(count: 40), fileExtension: "prc")
            == .failure(.tooSmall))
    #expect(PalmDatabaseFile.inspect(data: image(name: "", resource: true), fileExtension: "prc")
            == .failure(.invalidName))
    #expect(PalmDatabaseFile.inspect(data: image(resource: true, records: 4, truncate: true),
                                     fileExtension: "prc")
            == .failure(.truncated))
}

// MARK: - InstallFailure

@Test func palmErrorCodes() {
    #expect(InstallFailure.fromPalmOSError(0x09) == .protectedOnPalm)
    #expect(InstallFailure.fromPalmOSError(0x10) == .notEnoughSpace)
    #expect(InstallFailure.fromPalmOSError(0x07) == .openOnPalm)
    #expect(InstallFailure.fromPalmOSError(0x0F) == .readOnly)
    #expect(InstallFailure.fromPalmOSError(0x11) == .tooLarge)
    #expect(InstallFailure.fromPalmOSError(0x02) == .palmError(code: 2))
}

// MARK: - SessionEvent

@Test func sessionEvents() {
    #expect(SessionEvent.parse(#"{"event":"listening","port":"usb:"}"#) == .listening(port: "usb:"))
    #expect(SessionEvent.parse(#"{"event":"timeout"}"#) == .timeout)
    #expect(SessionEvent.parse(#"{"event":"connected","user":"m5152","userId":41981,"romVersion":68169728}"#)
            == .connected(PalmUser(name: "m5152", userId: 41981), romVersion: 0x0410_3000))
    #expect(SessionEvent.parse(#"{"event":"installed","file":"a.prc","bytes":1234}"#)
            == .installed(file: "a.prc", bytes: 1234))
    #expect(SessionEvent.parse(#"{"event":"finished"}"#) == .finished)
    #expect(SessionEvent.parse(#"{"event":"error","stage":"bind","message":"unable"}"#)
            == .error(stage: "bind", message: "unable"))
    #expect(SessionEvent.parse(#"{"event":"userWritten","user":"Palm User","userId":4711}"#)
            == .userWritten(PalmUser(name: "Palm User", userId: 4711)))
}

@Test func sessionFailures() {
    #expect(SessionEvent.parse(#"{"event":"failed","file":"a.prc","reason":"palmError","error":-301,"palmOSError":9}"#)
            == .failed(file: "a.prc", .protectedOnPalm))
    #expect(SessionEvent.parse(#"{"event":"failed","file":"b.prc","reason":"unreadableFile"}"#)
            == .failed(file: "b.prc", .unreadableFile))
    #expect(SessionEvent.parse(#"{"event":"failed","file":"c.pdb","reason":"notEnoughSpace","needed":9,"available":1}"#)
            == .failed(file: "c.pdb", .notEnoughSpace))
}

@Test func backupEvents() {
    #expect(SessionEvent.parse(#"{"event":"backupStarted","directory":"/tmp/b","total":257}"#)
            == .backupStarted(directory: "/tmp/b", total: 257))
    #expect(SessionEvent.parse(#"{"event":"backingUp","file":"MemoDB.pdb","index":3,"total":257}"#)
            == .backingUp(file: "MemoDB.pdb", index: 3, total: 257))
    #expect(SessionEvent.parse(#"{"event":"backupUnchanged","file":"AddressDB.pdb","index":4}"#)
            == .backupUnchanged(file: "AddressDB.pdb", index: 4))
    #expect(SessionEvent.parse(#"{"event":"backedUp","file":"MemoDB.pdb","bytes":2048}"#)
            == .backedUp(file: "MemoDB.pdb", bytes: 2048))
    #expect(SessionEvent.parse(#"{"event":"backupFailed","file":"x.prc","reason":"palmError","error":-301,"palmOSError":5}"#)
            == .backupFailed(file: "x.prc", palmOSError: 5))
    #expect(SessionEvent.parse(#"{"event":"backupFinished","saved":12,"unchanged":244,"failed":1}"#)
            == .backupFinished(saved: 12, unchanged: 244, failed: 1))
    // without the fields that identify the database: not a known event
    #expect(SessionEvent.parse(#"{"event":"backingUp","file":"MemoDB.pdb"}"#) == nil)
    #expect(SessionEvent.parse(#"{"event":"backupStarted"}"#) == nil)
}

@Test func recordEvents() {
    #expect(SessionEvent.parse(#"{"event":"syncInfo","lastSyncPC":305419896,"lastSyncDate":1792368000,"successfulSyncDate":1792368000}"#)
            == .syncInfo(lastSyncPC: 0x12345678, lastSyncDate: Date(timeIntervalSince1970: 1_792_368_000)))
    // never synced: the Palm reports 0 and the 1904 epoch
    #expect(SessionEvent.parse(#"{"event":"syncInfo","lastSyncPC":0,"lastSyncDate":-2082844800}"#)
            == .syncInfo(lastSyncPC: 0, lastSyncDate: nil))
    #expect(SessionEvent.parse(#"{"event":"dbOpened","name":"CalendarDB-PDat","records":72}"#)
            == .dbOpened(name: "CalendarDB-PDat", records: 72))
    #expect(SessionEvent.parse(#"{"event":"dbClosed"}"#) == .dbClosed)
    #expect(SessionEvent.parse(#"{"event":"appInfo","data":"AAEC"}"#) == .appInfo(Data([0, 1, 2])))
    #expect(SessionEvent.parse(#"{"event":"appInfoWritten","bytes":298}"#) == .appInfoWritten(bytes: 298))
    // attrs come with the flags only; a deleted record has no data
    #expect(SessionEvent.parse(#"{"event":"record","id":4097,"index":0,"attrs":64,"category":2,"data":"CQAKAA=="}"#)
            == .record(id: 0x1001, index: 0, attributes: 0x40, category: 2, data: Data([9, 0, 10, 0])))
    #expect(SessionEvent.parse(#"{"event":"record","id":4098,"index":1,"attrs":192,"category":0,"data":""}"#)
            == .record(id: 0x1002, index: 1, attributes: 0xC0, category: 0, data: Data()))
    // archived (0x08) is a flag on the wire, not part of the category
    #expect(SessionEvent.parse(#"{"event":"record","id":4100,"index":2,"attrs":136,"category":3,"data":""}"#)
            == .record(id: 0x1004, index: 2, attributes: 0x88, category: 3, data: Data()))
    #expect(SessionEvent.parse(#"{"event":"recordsDone","count":2,"modifiedOnly":1}"#)
            == .recordsDone(count: 2, modifiedOnly: true))
    #expect(SessionEvent.parse(#"{"event":"recordWritten","id":4099,"bytes":16}"#) == .recordWritten(id: 4099, bytes: 16))
    #expect(SessionEvent.parse(#"{"event":"recordDeleted","id":4099}"#) == .recordDeleted(id: 4099))
    #expect(SessionEvent.parse(#"{"event":"flagsReset"}"#) == .flagsReset)
    #expect(SessionEvent.parse(#"{"event":"cleanedUp"}"#) == .cleanedUp)
    #expect(SessionEvent.parse(#"{"event":"syncInfoWritten","pcId":305419896,"date":1792368000}"#)
            == .syncInfoWritten(pcId: 0x12345678, date: Date(timeIntervalSince1970: 1_792_368_000)))
    #expect(SessionEvent.parse(#"{"event":"timeSet","date":1792368000}"#) == .timeSet(Date(timeIntervalSince1970: 1_792_368_000)))
    #expect(SessionEvent.parse(#"{"event":"netSyncSet","address":"192.168.0.101","name":"Zoë’s Mac"}"#)
            == .netSyncSet(address: "192.168.0.101", name: "Zoë’s Mac"))
    // a record without its data or id, or with broken base64, is not a record
    #expect(SessionEvent.parse(#"{"event":"record","id":1,"attrs":0}"#) == nil)
    #expect(SessionEvent.parse(#"{"event":"record","id":1,"data":"@@"}"#) == nil)
    #expect(SessionEvent.parse(#"{"event":"recordWritten","bytes":3}"#) == nil)
    // a DLP failure keeps the raw codes next to the stage
    #expect(SessionEvent.parse(#"{"event":"error","stage":"writerec","message":"cannot write the record","error":-301,"palmOSError":5}"#)
            == .error(stage: "writerec", message: "cannot write the record"))
}

@Test func brokenLines() {
    #expect(SessionEvent.parse("Thank you for using pilot-link.") == nil)
    #expect(SessionEvent.parse(#"{"event":"connected"}"#) == nil)
    #expect(SessionEvent.parse(#"{"event":"somethingNew"}"#) == nil)
}

@Test func palmUserNames() {
    // Windows-1252 from the Palm arrives as UTF-8 escaped by the tool
    #expect(SessionEvent.parse(#"{"event":"connected","user":"M\u00fcller \u20ac","userId":7}"#)
            == .connected(PalmUser(name: "Müller €", userId: 7), romVersion: 0))
    #expect(SessionEvent.parse(#"{"event":"connected","user":"Z","userId":1,"romVersion":0,"dateFixStartYear":1932}"#)
            == .connected(PalmUser(name: "Z", userId: 1), romVersion: 0, dateFixStartYear: 1932))
}

// MARK: - PalmAdmission

private let m515 = ProfileIdentity(id: UUID(), userId: 41981)
private let t3 = ProfileIdentity(id: UUID(), userId: 88143)

@Test func tabSessionAdmission() {
    let all = [m515, t3]
    #expect(PalmAdmission.decide(user: PalmUser(name: "m5152", userId: 41981),
                                 expected: m515.id, candidates: [m515], profiles: all)
            == .install(profile: m515.id))
    #expect(PalmAdmission.decide(user: PalmUser(name: "T3", userId: 88143),
                                 expected: m515.id, candidates: [m515], profiles: all)
            == .wrongPalm(expected: m515.id, found: t3.id))
    #expect(PalmAdmission.decide(user: PalmUser(name: "other", userId: 5),
                                 expected: m515.id, candidates: [m515], profiles: all)
            == .unknown)
    #expect(PalmAdmission.decide(user: PalmUser(name: "", userId: 0),
                                 expected: m515.id, candidates: [m515], profiles: all)
            == .adopt(profile: m515.id))
}

@Test func portListenerAdmission() {
    let all = [m515, t3]
    // the listener serves every profile with a tab on its port
    #expect(PalmAdmission.decide(user: PalmUser(name: "T3", userId: 88143),
                                 expected: nil, candidates: [m515, t3], profiles: all)
            == .install(profile: t3.id))
    // a known Palm whose profile has no tab on this port
    #expect(PalmAdmission.decide(user: PalmUser(name: "T3", userId: 88143),
                                 expected: nil, candidates: [m515], profiles: all)
            == .unknown)
    // a blank Palm: not clear which profile it should become
    #expect(PalmAdmission.decide(user: PalmUser(name: "", userId: 0),
                                 expected: nil, candidates: [m515, t3], profiles: all)
            == .blank)
    // a renamed Palm is still the same Palm
    #expect(PalmAdmission.decide(user: PalmUser(name: "renamed", userId: 41981),
                                 expected: nil, candidates: [m515], profiles: all)
            == .install(profile: m515.id))
}

// MARK: - ChainRun

@Test func chainRunsThrough() {
    let a = UUID(), b = UUID(), c = UUID()
    var run = ChainRun(steps: [a, b, c])
    #expect(run.currentTab == a)
    run.stepSucceeded()
    #expect(run.currentTab == b)
    run.stepSucceeded()
    run.stepSucceeded()
    #expect(run.state == .finished)
    #expect(run.currentTab == nil)
    #expect(!run.isActive)
}

@Test func chainPausesOnFailure() {
    let a = UUID(), b = UUID(), c = UUID()
    var run = ChainRun(steps: [a, b, c])
    run.stepSucceeded()
    run.stepFailed(reason: "timeout")
    #expect(run.state == .paused(step: 1, reason: "timeout"))
    #expect(run.currentTab == b)
    // a paused chain ignores the end of other sessions
    run.stepSucceeded()
    #expect(run.state == .paused(step: 1, reason: "timeout"))

    run.retry()
    #expect(run.state == .running(step: 1))
    run.stepFailed(reason: "wrong Palm")
    run.skip()
    #expect(run.state == .running(step: 2))
    #expect(run.skipped == [1])
    run.stepSucceeded()
    #expect(run.state == .finished)
}

@Test func chainCancel() {
    var run = ChainRun(steps: [UUID(), UUID()])
    run.cancel()
    #expect(run.state == .cancelled)
    run.stepSucceeded()
    #expect(run.state == .cancelled)
    #expect(ChainRun(steps: []).state == .finished)
}

// MARK: - ListSelection

@Test func selectionClickShiftCommand() {
    let order = ["a", "b", "c", "d", "e"]
    var selection = ListSelection<String>()
    selection.click("b", modifier: .none, order: order)
    #expect(selection.selected == ["b"])
    selection.click("d", modifier: .extend, order: order)
    #expect(selection.selected == ["b", "c", "d"])
    // a new shift-click replaces the range from the same anchor
    selection.click("a", modifier: .extend, order: order)
    #expect(selection.selected == ["a", "b"])
    selection.click("e", modifier: .toggle, order: order)
    #expect(selection.selected == ["a", "b", "e"])
    selection.click("a", modifier: .toggle, order: order)
    #expect(selection.selected == ["b", "e"])
    selection.click("c", modifier: .none, order: order)
    #expect(selection.selected == ["c"])
}

@Test func selectionShiftWithoutAnchorSelectsOne() {
    var selection = ListSelection<String>()
    selection.click("c", modifier: .extend, order: ["a", "b", "c"])
    #expect(selection.selected == ["c"])
}

@Test func selectionTargets() {
    let order = ["a", "b", "c", "d"]
    var selection = ListSelection<String>()
    selection.click("d", modifier: .none, order: order)
    selection.click("b", modifier: .toggle, order: order)
    #expect(selection.targets(for: "d", order: order) == ["b", "d"])
    #expect(selection.targets(for: "a", order: order) == ["a"])
}

@Test func selectionRetain() {
    let order = ["a", "b", "c"]
    var selection = ListSelection<String>()
    selection.click("a", modifier: .none, order: order)
    selection.click("c", modifier: .extend, order: order)
    selection.retain(["b", "c"])
    #expect(selection.selected == ["b", "c"])
    #expect(selection.anchor == nil)
}

// MARK: - RestoreOrder

@Test func restoreDataBeforeApplication() {
    let items = [
        RestoreOrder.Item(name: "Lemmings", type: "appl", creator: "LEMM", size: 260_000),
        RestoreOrder.Item(name: "LEMM_FUN", type: "levl", creator: "LEMM", size: 250_000),
        RestoreOrder.Item(name: "MemoDB", type: "DATA", creator: "memo", size: 2_000),
        RestoreOrder.Item(name: "BigData", type: "DATA", creator: "BIGD", size: 900_000),
    ]
    #expect(RestoreOrder.sorted(items).map(\.name) == ["BigData", "LEMM_FUN", "Lemmings", "MemoDB"])
}

@Test func restoreLargerFirstWithinCreator() {
    let items = [
        RestoreOrder.Item(name: "a", type: "DATA", creator: "X", size: 10),
        RestoreOrder.Item(name: "b", type: "DATA", creator: "X", size: 30),
        RestoreOrder.Item(name: "app", type: "appl", creator: "X", size: 99),
    ]
    #expect(RestoreOrder.sorted(items).map(\.name) == ["b", "a", "app"])
}

@Test func romEvents() {
    #expect(SessionEvent.parse(#"{"event":"romStarted","file":"PalmOS-4.1.0.rom","version":"4.1.0","total":4194304}"#)
            == .romStarted(file: "PalmOS-4.1.0.rom", version: "4.1.0", total: 4_194_304))
    #expect(SessionEvent.parse(#"{"event":"romProgress","bytes":4096}"#) == .romProgress(bytes: 4096))
    #expect(SessionEvent.parse(#"{"event":"romFinished","file":"PalmOS-4.1.0.rom","bytes":4194304}"#)
            == .romFinished(file: "PalmOS-4.1.0.rom", bytes: 4_194_304))
    #expect(SessionEvent.parse(#"{"event":"romUnsupported","version":"5.2.1"}"#)
            == .romUnsupported(version: "5.2.1"))
    #expect(SessionEvent.parse(#"{"event":"romStarted","file":"x.rom"}"#) == nil)
}

@Test func palmOSMajorVersion() {
    // sysMakeROMVersion: major in the top byte, BCD-coded tens and units
    #expect(PalmOSVersion(rom: 0x0410_3000).major == 4)
    #expect(PalmOSVersion(rom: 0x0521_3000).major == 5)
    #expect(PalmOSVersion(rom: 0x0410_3000).description == "4.1.0")
}
