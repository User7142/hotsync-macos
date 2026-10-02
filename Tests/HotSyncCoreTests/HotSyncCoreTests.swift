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

@Test func rejectsWrongFiles() {
    #expect(PalmDatabaseFile.inspect(data: Data("hello".utf8), fileExtension: "txt")
            == .failure(.unsupportedExtension("txt")))
    #expect(PalmDatabaseFile.inspect(data: Data(count: 40), fileExtension: "prc")
            == .failure(.tooSmall))
    #expect(PalmDatabaseFile.inspect(data: image(name: "", resource: true), fileExtension: "prc")
            == .failure(.invalidName))
    #expect(PalmDatabaseFile.inspect(data: image(resource: false), fileExtension: "prc")
            == .failure(.kindMismatch(expectedResource: true)))
    #expect(PalmDatabaseFile.inspect(data: image(resource: true), fileExtension: "pdb")
            == .failure(.kindMismatch(expectedResource: false)))
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

@Test func brokenLines() {
    #expect(SessionEvent.parse("Thank you for using pilot-link.") == nil)
    #expect(SessionEvent.parse(#"{"event":"connected"}"#) == nil)
    #expect(SessionEvent.parse(#"{"event":"somethingNew"}"#) == nil)
}

@Test func palmUserNames() {
    // Windows-1252 from the Palm arrives as UTF-8 escaped by the tool
    #expect(SessionEvent.parse(#"{"event":"connected","user":"M\u00fcller \u20ac","userId":7}"#)
            == .connected(PalmUser(name: "Müller €", userId: 7), romVersion: 0))
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
