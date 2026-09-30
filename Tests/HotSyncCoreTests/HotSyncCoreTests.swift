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
    #expect(InstallFailure.parse("ERROR: pi_file_install failed (-301, PalmOS 0x0009).")
            == .protectedOnPalm)
    #expect(InstallFailure.parse("ERROR: pi_file_install failed (-301, PalmOS 0x0010).")
            == .notEnoughSpace)
    #expect(InstallFailure.parse("ERROR: pi_file_install failed (-301, PalmOS 0x0007).")
            == .openOnPalm)
    #expect(InstallFailure.parse("ERROR: something else") == .other("ERROR: something else"))
}

// MARK: - InstallTranscript

/// The order seen on 2026-09-30: stderr before the buffered stdout.
@Test func errorBeforeItsFile() {
    let t = InstallTranscript(expected: ["DateFix.prc"])
    t.consume("ERROR: pi_file_install failed (-301, PalmOS 0x0009).", fromStderr: true)
    #expect(t.isComplete)
    t.consume("Installing 'DateFix.prc'...", fromStderr: false)
    t.consume("Thank you for using pilot-link.", fromStderr: false)
    #expect(t.confirmed.isEmpty)
    #expect(t.failures == ["DateFix.prc": .protectedOnPalm])
}

@Test func mixedSession() {
    let t = InstallTranscript(expected: ["a.prc", "b.prc", "c.pdb", "d.prc"])
    t.consume("ERROR: Unable to open '/Users/x/HotSync/T3/Install/b.prc'!", fromStderr: true)
    t.consume("ERROR: pi_file_install failed (-301, PalmOS 0x0010).", fromStderr: true)
    t.consume("Installing 'a.prc'... Installing 'a.prc' ... (1234 bytes)   1 KiB total.",
              fromStderr: false)
    t.consume("Installing 'c.pdb'... Installing 'd.prc'... Installing 'd.prc' ... (99 bytes)   1 KiB total.",
              fromStderr: false)
    #expect(t.isComplete)
    #expect(t.confirmed == ["a.prc", "d.prc"])
    #expect(t.failures == ["b.prc": .unreadableFile, "c.pdb": .notEnoughSpace])
}

@Test func connectionLost() {
    let t = InstallTranscript(expected: ["a.prc", "b.prc"])
    t.consume("Installing 'a.prc'... Installing 'a.prc' ... (1234 bytes)   1 KiB total.",
              fromStderr: false)
    #expect(!t.isComplete)
    #expect(t.failures == ["b.prc": .notConfirmed])
}
