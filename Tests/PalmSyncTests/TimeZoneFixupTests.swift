import Foundation
import Testing
@testable import PalmSync

/// The fixups run against the T|X's own location records (device fixtures)
/// and this Mac's tzdata. Zones whose rules changed in 2026 are checked by
/// what tzdata on the build machine says, so the tests hold on a Mac with
/// older data too.
private func deviceLocations() throws -> [String: PalmLocation] {
    let url = try #require(Bundle.module.url(forResource: "locLDefLocationDB", withExtension: "pdb", subdirectory: "Fixtures/device"))
    let db = try PalmDatabase(data: try Data(contentsOf: url))
    var byName: [String: PalmLocation] = [:]
    for record in db.records {
        let location = try PalmLocation(data: record.data)
        byName[location.name] = location
    }
    return byName
}

private let now = ISO8601DateFormatter().date(from: "2026-10-24T12:00:00Z")!

@Test func deviceRulesArePre2007() throws {
    let toronto = try #require(try deviceLocations()["Toronto"])
    #expect(toronto.timezone.offsetMinutes == -300 && toronto.timezone.observesDST)
    #expect(toronto.timezone.dstStart == DSTRule(weekday: 0, week: 0, month: 4, unknown: 1))   // first Sunday of April
    #expect(toronto.timezone.dstEnd == DSTRule(weekday: 0, week: 4, month: 10, unknown: 0))    // last Sunday of October
}

@Test func torontoGetsThe2007Rules() throws {
    let toronto = try #require(try deviceLocations()["Toronto"])
    let (fixed, change) = try #require(TimeZoneFixups.fix(toronto, now: now))
    #expect(fixed.timezone.offsetMinutes == -300 && fixed.timezone.observesDST)
    #expect(fixed.timezone.dstStart == DSTRule(weekday: 0, week: 1, month: 3, unknown: 1))   // second Sunday of March; byte 4 as the device had it
    #expect(fixed.timezone.dstEnd == DSTRule(weekday: 0, week: 0, month: 11, unknown: 0))    // first Sunday of November
    #expect(change.contains("Toronto") && change.contains("America/Toronto"))
    // the rest of the record is untouched
    #expect(fixed.timezone.country == toronto.timezone.country && fixed.latitudeDegrees == toronto.latitudeDegrees)
    #expect(fixed.encode().count == toronto.encode().count)
}

@Test func vancouverFollowsTzdata() throws {
    let vancouver = try #require(try deviceLocations()["Vancouver"])
    let zone = TimeZone(identifier: "America/Vancouver")!
    let expected = TimeZoneFixups.rule(of: zone, now: now)
    let (fixed, _) = try #require(TimeZoneFixups.fix(vancouver, now: now))
    #expect(fixed.timezone.offsetMinutes == expected.offsetMinutes)
    #expect(fixed.timezone.observesDST == expected.observesDST)
    // tzdata 2026b or later: permanent UTC-7 from Nov 1, 2026
    if zone.secondsFromGMT(for: ISO8601DateFormatter().date(from: "2027-01-15T12:00:00Z")!) == -7 * 3600 {
        #expect(fixed.timezone.offsetMinutes == -420 && !fixed.timezone.observesDST)
    }
}

@Test func reginaIsAlreadyRight() throws {
    let regina = try #require(try deviceLocations()["Regina"])
    #expect(TimeZoneFixups.fix(regina, now: now) == nil)
}

@Test func namesResolveToZones() throws {
    let locations = try deviceLocations()
    for (name, id) in [("Vancouver", "America/Vancouver"), ("Toronto", "America/Toronto"), ("Halifax", "America/Halifax"),
                       ("Winnipeg", "America/Winnipeg"), ("Edmonton", "America/Edmonton")] {
        #expect(TimeZoneFixups.zone(for: try #require(locations[name]))?.identifier == id, "\(name)")
    }
    var unknown = 0
    for location in locations.values where TimeZoneFixups.zone(for: location) == nil { unknown += 1 }
    #expect(unknown <= 3, "\(unknown) of \(locations.count) device locations have no zone")

    // a city of the same name elsewhere is not a match
    var victoria = PalmLocation(timezone: PalmTimezone(offsetMinutes: 600, name: "Victoria"), latitude: -37.8, longitude: 144.9)
    #expect(TimeZoneFixups.zone(for: victoria) == nil)   // the alias says BC, the offset says Australia
    victoria.timezone.offsetMinutes = -480
    #expect(TimeZoneFixups.zone(for: victoria)?.identifier == "America/Vancouver")
}

@Test func rulesFromTzdata() {
    let tokyo = TimeZoneFixups.rule(of: TimeZone(identifier: "Asia/Tokyo")!, now: now)
    #expect(tokyo == .init(offsetMinutes: 540, observesDST: false, dstStart: nil, dstEnd: nil))

    let berlin = TimeZoneFixups.rule(of: TimeZone(identifier: "Europe/Berlin")!, now: now)
    #expect(berlin.offsetMinutes == 60 && berlin.observesDST)
    #expect(berlin.dstStart == DSTRule(weekday: 0, week: 4, month: 3, unknown: 0))    // last Sunday of March
    #expect(berlin.dstEnd == DSTRule(weekday: 0, week: 4, month: 10, unknown: 0))     // last Sunday of October

    let sydney = TimeZoneFixups.rule(of: TimeZone(identifier: "Australia/Sydney")!, now: now)
    #expect(sydney.offsetMinutes == 600 && sydney.observesDST)
    #expect(sydney.dstStart?.month == 10 && sydney.dstStart?.week == 0 && sydney.dstEnd?.month == 4 && sydney.dstEnd?.week == 0)
}

@Test func zoneTableNamesAndPalmOrder() throws {
    let url = try #require(Bundle.module.url(forResource: "locLTimeZoneDB", withExtension: "pdb", subdirectory: "Fixtures/device"))
    let table = PalmZoneTable(records: try PalmDatabase(data: try Data(contentsOf: url)).records.map(\.data))
    #expect(table.zones.count == 102)
    #expect(table.name(country: 4, offsetMinutes: -480) == "Canada (Pacific)")
    #expect(table.name(country: 4, offsetMinutes: -420) == "Canada (Mountain)")
    #expect(table.name(country: 23, offsetMinutes: -300) == "USA (Eastern)")
    #expect(table.name(country: 175, offsetMinutes: 300) == "Pakistan")

}

@Test func canadaBlockIsReorderedThePickersWay() throws {
    let url = try #require(Bundle.module.url(forResource: "locLTimeZoneDB", withExtension: "pdb", subdirectory: "Fixtures/device"))
    let zones = PalmZoneTable(records: try PalmDatabase(data: try Data(contentsOf: url)).records.map(\.data))
    let devURL = try #require(Bundle.module.url(forResource: "locLDefLocationDB", withExtension: "pdb", subdirectory: "Fixtures/device"))
    var locations = try PalmDatabase(data: try Data(contentsOf: devURL)).records.map { try PalmLocation(data: $0.data) }

    // untouched, the device order is already the picker's order
    let same = TimeZoneFixups.reorderWithinCountries(locations, location: { $0 }, zones: zones)
    #expect(same.map(\.name) == locations.map(\.name))

    // Vancouver to Mountain, Edmonton to Central: the Canada block re-sorts, nothing else moves
    for i in locations.indices {
        if locations[i].name == "Vancouver" { locations[i].timezone.offsetMinutes = -420; locations[i].timezone.observesDST = false }
        if locations[i].name == "Edmonton" { locations[i].timezone.offsetMinutes = -360; locations[i].timezone.observesDST = false }
    }
    let sorted = TimeZoneFixups.reorderWithinCountries(locations, location: { $0 }, zones: zones)
    let canada = sorted.filter { $0.timezone.country == 4 }.map(\.name)
    #expect(canada == ["Halifax", "Edmonton", "Regina", "Winnipeg", "Montreal", "Toronto", "Vancouver", "St. John's"])
    #expect(sorted.filter { $0.timezone.country != 4 }.map(\.name) == locations.filter { $0.timezone.country != 4 }.map(\.name))
    #expect(sorted.firstIndex { $0.name == "Halifax" } == locations.firstIndex { $0.name == "Halifax" })
}
