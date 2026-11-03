import Foundation
import Testing
@testable import PalmSync

/// Databases backed up from a Palm T|X (Palm OS 5.4.9) on 2026-10-24: the
/// codecs must take what a real device writes, byte for byte.
private func device(_ name: String) throws -> PalmDatabase {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "pdb", subdirectory: "Fixtures/device"))
    return try PalmDatabase(data: try Data(contentsOf: url))
}

@Test func deviceLocationDatabasesRoundTrip() throws {
    for name in ["locLDefLocationDB", "locLCusLocationDB"] {
        let db = try device(name)
        #expect(db.creator == "locL", "\(name)")
        var failures: [String] = []
        for record in db.records where !record.isDeleted && !record.data.isEmpty {
            do {
                let location = try PalmLocation(data: record.data)
                if location.encode() != record.data {
                    failures.append("\(name) \(record.uniqueID) \(location.name): re-encodes differently")
                }
            } catch {
                failures.append("\(name) \(record.uniqueID): \(error) — \(record.data.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " "))")
            }
        }
        #expect(failures.isEmpty, "\(failures.prefix(8))")
        #expect(db.records.count > 0)
    }
}

@Test func deviceDatabasesParseAsContainers() throws {
    let tz = try device("locLTimeZoneDB")
    #expect(tz.encode().count > 0)
    let tasks = try device("TasksDB-PTod")
    #expect(tasks.creator == "PTod" && tasks.version == 1)
    #expect(tasks.appInfo?.count == 300)
}
