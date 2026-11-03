import Foundation
import Testing
@testable import PalmSync

/// CalendarDB-PDat.pdb is written by Fixtures/generate-calendar.c with
/// pilot-link's own pack code; every record in it must come back byte for
/// byte from decode + encode.
private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func calendarFixture() throws -> PalmDatabase {
    try PalmDatabase(data: try fixture("CalendarDB-PDat.pdb"))
}

// MARK: - PalmDatabase container

@Test func containerHeader() throws {
    let db = try calendarFixture()
    #expect(db.name == "CalendarDB-PDat")
    #expect(db.type == "DATA")
    #expect(db.creator == "PDat")
    #expect(db.attributes == 0x0008)
    #expect(db.records.count == 13)
    #expect(db.appInfo?.count == 298)   // pilot-link writes 298, a T|X 300
    #expect(db.sortInfo == nil)
    #expect(PalmDatabase.date(fromPalmSeconds: db.creationDate) == Date(timeIntervalSince1970: 1_792_368_000))
    #expect(PalmDatabase.date(fromPalmSeconds: db.lastBackupDate) == nil)
}

@Test func containerRoundTripsByteForByte() throws {
    let data = try fixture("CalendarDB-PDat.pdb")
    let db = try PalmDatabase(data: data)
    #expect(db.encode() == data)
}

@Test func recordAttributes() throws {
    let db = try calendarFixture()
    #expect(db.records[0].uniqueID == 0x1001)
    #expect(db.records[0].category == 1)
    #expect(!db.records[0].isDeleted)
    #expect(db.records[9].isDeleted && db.records[9].isDirty)
    #expect(db.records[10].isSecret)
    #expect(db.records[11].category == 3)
}

@Test func containerRefusesResourceDatabases() throws {
    var bytes = [UInt8](repeating: 0, count: 78)
    bytes[33] = 0x01
    #expect(throws: PalmDatabase.Problem.resourceDatabase) {
        try PalmDatabase(data: Data(bytes))
    }
}

@Test func newDatabaseEncodesAndParses() throws {
    let record = CalendarEvent(date: PalmDate(year: 2026, month: 10, day: 20), title: "x").encode()
    var db = PalmDatabase(name: "CalendarDB-PDat", type: "DATA", creator: "PDat",
                          appInfo: CalendarAppInfo().encode(),
                          records: [PalmDatabase.Record(category: 2, uniqueID: 7, data: record)])
    db.records[0].attributes |= PalmDatabase.Record.dirty
    let back = try PalmDatabase(data: db.encode())
    #expect(back == db)
    #expect(back.records[0].category == 2 && back.records[0].isDirty)
}

// MARK: - Calendar records

@Test func everyRecordRoundTripsByteForByte() throws {
    let db = try calendarFixture()
    for (i, record) in db.records.enumerated() {
        let event = try CalendarEvent(data: record.data)
        #expect(event.encode() == record.data, "record \(i)")
    }
}

@Test func timedEvent() throws {
    let event = try CalendarEvent(data: try calendarFixture().records[0].data)
    #expect(event.date == PalmDate(year: 2026, month: 10, day: 20))
    #expect(event.time == .init(start: PalmTime(hour: 9, minute: 0), end: PalmTime(hour: 10, minute: 0)))
    #expect(event.title == "Standup")
    #expect(event.note == nil && event.location == nil && event.alarm == nil && event.repeatRule == nil)
    #expect(event.blobs.isEmpty)
}

@Test func timelessEventWithNote() throws {
    let event = try CalendarEvent(data: try calendarFixture().records[1].data)
    #expect(event.time == nil)
    #expect(event.date == PalmDate(year: 2026, month: 11, day: 1))
    #expect(event.title == "Clocks stay")
    #expect(event.note == "No fall back in BC")
}

@Test func alarmAndLocation() throws {
    let event = try CalendarEvent(data: try calendarFixture().records[2].data)
    #expect(event.alarm == .init(advance: 15, unit: .minutes))
    #expect(event.location == "Downtown")
    #expect(event.time?.start == PalmTime(hour: 14, minute: 30))
}

@Test func repeatRules() throws {
    let records = try calendarFixture().records

    let daily = try CalendarEvent(data: records[3].data).repeatRule
    #expect(daily == .init(type: .daily, endDate: nil, frequency: 1, on: 0, weekStart: 0))

    let weekly = try CalendarEvent(data: records[4].data)
    #expect(weekly.repeatRule?.type == .weekly)
    #expect(weekly.repeatRule?.weekdays == [.monday, .wednesday, .friday])
    #expect(weekly.repeatRule?.endDate == PalmDate(year: 2027, month: 3, day: 31))
    #expect(weekly.exceptions == [PalmDate(year: 2026, month: 10, day: 23), PalmDate(year: 2026, month: 10, day: 28)])

    let monthlyByDay = try CalendarEvent(data: records[5].data).repeatRule
    #expect(monthlyByDay?.type == .monthlyByDay)
    #expect(monthlyByDay?.nthWeekday?.week == 1 && monthlyByDay?.nthWeekday?.weekday == 2)  // second Tuesday

    let monthlyByDate = try CalendarEvent(data: records[6].data).repeatRule
    #expect(monthlyByDate == .init(type: .monthlyByDate, endDate: PalmDate(year: 2027, month: 12, day: 15),
                                   frequency: 2, on: 0, weekStart: 0))

    let yearly = try CalendarEvent(data: records[7].data)
    #expect(yearly.repeatRule?.type == .yearly)
    #expect(yearly.alarm == .init(advance: 1, unit: .days))
}

@Test func windows1252Text() throws {
    let event = try CalendarEvent(data: try calendarFixture().records[7].data)
    #expect(event.title == "Zoë's birthday")
    #expect(event.note == "Cake — budget 20 €")
}

@Test func timezoneBlob() throws {
    let event = try CalendarEvent(data: try calendarFixture().records[8].data)
    let tz = try #require(event.timezone)
    #expect(tz.name == "Toronto")
    #expect(tz.offsetMinutes == -300)
    #expect(tz.observesDST)
    #expect(tz.dstStart == DSTRule(weekday: 0, week: 1, month: 3))    // second Sunday of March
    #expect(tz.dstEnd == DSTRule(weekday: 0, week: 0, month: 11))     // first Sunday of November
    #expect(tz.unknown == 0x80)
    #expect(event.blobs.count == 2)
    #expect(event.blobs[1] == .init(type: "Bd01", data: Data([1, 2, 3])))

    // Replacing the zone keeps the other blob; removing it leaves only that blob
    var edited = event
    edited.timezone = PalmTimezone(offsetMinutes: -420, name: "Vancouver")
    #expect(try CalendarEvent(data: edited.encode()).timezone?.name == "Vancouver")
    #expect(edited.blobs.count == 2)
    edited.timezone = nil
    #expect(edited.blobs.map(\.type) == ["Bd01"])
}

@Test func emptyTitleAndLongNote() throws {
    let event = try CalendarEvent(data: try calendarFixture().records[12].data)
    #expect(event.title == "")
    #expect(event.note?.count == 300)
    #expect(event.time?.end == PalmTime(hour: 0, minute: 0))
}

@Test func encodesFromScratchLikePilotLink() throws {
    let event = CalendarEvent(date: PalmDate(year: 2026, month: 10, day: 20),
                              time: .init(start: PalmTime(hour: 9, minute: 0), end: PalmTime(hour: 10, minute: 0)),
                              title: "Standup")
    let standup = try calendarFixture().records[0].data
    #expect(event.encode() == standup)
    #expect(event.encode() == Data([0x09, 0x00, 0x0a, 0x00, 0xf5, 0x54, 0x04, 0x00] + Array("Standup".utf8) + [0]))
}

@Test func rejectsBadRecords() {
    #expect(throws: PalmFormatError.truncated(at: 4)) {
        try CalendarEvent(data: Data([9, 0, 10, 0]))
    }
    // description flag set, but no NUL
    #expect(throws: PalmFormatError.unterminatedString(at: 8)) {
        try CalendarEvent(data: Data([9, 0, 10, 0, 0xf5, 0x54, 0x04, 0x00, 0x41]))
    }
    // three bytes after the strings: not a blob
    #expect(throws: PalmFormatError.trailingBytes(count: 3)) {
        try CalendarEvent(data: Data([9, 0, 10, 0, 0xf5, 0x54, 0x00, 0x00, 1, 2, 3]))
    }
}

// MARK: - AppInfo

@Test func appInfoRoundTrip() throws {
    let db = try calendarFixture()
    let data = try #require(db.appInfo)
    let info = try CalendarAppInfo(data: data)
    #expect(info.categories.names.prefix(4) == ["Unfiled", "Work", "Family", "G Work"])
    #expect(info.categories.named.map(\.id) == [0, 1, 2, 3])
    #expect(info.categories.lastUniqueID == 3)
    #expect(info.startOfWeek == 0)
    #expect(info.internalBytes.count == 18)
    #expect(info.encode() == data)
}

@Test func categoryNamesAreCutToFifteen() {
    var info = CategoryAppInfo(names: ["Unfiled", "A very long category name"])
    let back = try! CategoryAppInfo(bytes: info.encode()[...])
    #expect(back.names[1] == "A very long cat")
    #expect(back.names[1].count == 15)
    info.names[1] = "Zoë"
    #expect(try! CategoryAppInfo(bytes: info.encode()[...]).names[1] == "Zoë")
}

// MARK: - Dates

@Test func packedDates() {
    let d = PalmDate(year: 2026, month: 10, day: 20)
    #expect(d.packed == 0xF554)
    #expect(PalmDate(packed: 0xF554) == d)
    #expect(PalmDate(year: 1904, month: 1, day: 1).packed == 0x0021)
    #expect(PalmDate(year: 2026, month: 5, day: 4) < PalmDate(year: 2026, month: 10, day: 20))
}
