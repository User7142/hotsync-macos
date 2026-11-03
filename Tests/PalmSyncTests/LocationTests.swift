import Foundation
import Testing
@testable import PalmSync

/// locLCusLocationDB.pdb is packed by hand in Fixtures/generate-locations.c
/// and checked there against pilot-link's unpack_Location.
private func locationsFixture() throws -> PalmDatabase {
    let url = try #require(Bundle.module.url(forResource: "locLCusLocationDB.pdb", withExtension: nil, subdirectory: "Fixtures"))
    return try PalmDatabase(data: try Data(contentsOf: url))
}

@Test func everyLocationRoundTripsByteForByte() throws {
    let db = try locationsFixture()
    #expect(db.name == "locLCusLocationDB" && db.creator == "locL")
    #expect(db.records.count == 5)
    for (i, record) in db.records.enumerated() {
        let location = try PalmLocation(data: record.data)
        #expect(location.encode() == record.data, "record \(i)")
    }
}

@Test func vancouverWithoutDST() throws {
    let loc = try PalmLocation(data: try locationsFixture().records[0].data)
    #expect(loc.name == "Vancouver")
    #expect(loc.timezone.offsetMinutes == -420)
    #expect(!loc.timezone.observesDST)
    #expect(loc.timezone.dstStart == DSTRule(weekday: 0, week: 0, month: 0))
    #expect(loc.unknown == nil)
    #expect(loc.latitudeDegrees == -49 && loc.latitudeMinutes == -17)
    #expect(abs(loc.latitude - 49.2833) < 0.001)
    #expect(abs(loc.longitude + 123.1167) < 0.001)
    #expect(loc.note == "")
}

@Test func torontoWithDST() throws {
    let loc = try PalmLocation(data: try locationsFixture().records[1].data)
    #expect(loc.timezone.offsetMinutes == -300)
    #expect(loc.timezone.observesDST)
    #expect(loc.timezone.dstStart == DSTRule(weekday: 0, week: 1, month: 3))
    #expect(loc.timezone.dstEnd == DSTRule(weekday: 0, week: 0, month: 11))
    #expect(loc.note == "Eastern")
}

@Test func unknownByteBeforeCoordinates() throws {
    let loc = try PalmLocation(data: try locationsFixture().records[2].data)
    #expect(loc.name == "Winnipeg")
    #expect(loc.unknown == 0x01)
    #expect(loc.latitudeDegrees == -49 && loc.longitudeDegrees == 97)
}

@Test func southernAndEasternHemispheres() throws {
    let records = try locationsFixture().records
    let sydney = try PalmLocation(data: records[3].data)
    #expect(sydney.timezone.offsetMinutes == 600)
    #expect(sydney.latitudeDegrees == 33 && sydney.longitudeDegrees == -151)
    #expect(sydney.latitude < 0 && sydney.longitude > 0)
    #expect(abs(sydney.longitude - 151.2) < 0.001)

    let kathmandu = try PalmLocation(data: records[4].data)
    #expect(kathmandu.timezone.offsetMinutes == 345)
    #expect(kathmandu.latitude > 0 && kathmandu.longitude > 0)
}

@Test func locationFromCoordinates() throws {
    let loc = PalmLocation(timezone: PalmTimezone(offsetMinutes: -420, name: "Vancouver"),
                           latitude: 49.2833, longitude: -123.1167)
    #expect(loc.latitudeDegrees == -49 && loc.latitudeMinutes == -17)
    #expect(loc.longitudeDegrees == 123 && loc.longitudeMinutes == 7)
    #expect(loc.encode() == (try locationsFixture().records[0].data))
    #expect(try PalmLocation(data: loc.encode()) == loc)
}
