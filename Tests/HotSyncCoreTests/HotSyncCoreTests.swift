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
