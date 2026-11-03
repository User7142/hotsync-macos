import Foundation
import Testing
@testable import PalmSync

// DateFix shifts the Palm's dates by (start year − 1904); the engine shifts
// items it reads and writes, the builders shift on encoding. Record bytes
// never hold a year past 2031.

@Test func offsetDaysAreWholeLeapBlocks() {
    #expect(DateFix.offsetDays(startYear: 1932) == 10_227)   // 28 years = 7 × 1461 days
    #expect(DateFix.offsetDays(startYear: 1904) == 0)
}

@Test func recordShiftsEveryDateAndRoundTrips() throws {
    var event = CalendarEvent(date: PalmDate(year: 1998, month: 10, day: 26))
    event.title = "Standup"
    event.repeatRule = .init(type: .weekly, endDate: PalmDate(year: 1999, month: 1, day: 4), frequency: 1)
    event.exceptions = [PalmDate(year: 1998, month: 11, day: 2)]
    let real = DateFix.shift(event, years: 28)
    #expect(real.date.year == 2026 && real.repeatRule?.endDate?.year == 2027 && real.exceptions[0].year == 2026)
    #expect(DateFix.shift(real, years: -28).encode() == event.encode())

    var task = PalmTask(title: "Milk", dueDate: PalmDate(year: 1998, month: 10, day: 27), completedDate: PalmDate(year: 1998, month: 10, day: 26))
    task.repeatRule = (PalmDate(year: 1998, month: 10, day: 27), .init(type: .daily, endDate: PalmDate(year: 1998, month: 12, day: 31), frequency: 1))
    let realTask = DateFix.shift(task, years: 28)
    #expect(realTask.dueDate?.year == 2026 && realTask.completedDate?.year == 2026)
    #expect(realTask.repeatRule?.start.year == 2026 && realTask.repeatRule?.rule.endDate?.year == 2026)

    var contact = Contact(fields: [.lastName: "Leto"])
    contact.birthday = .init(date: PalmDate(year: 1962, month: 5, day: 6), reminderAdvance: nil, advanceUnits: 0)
    let anniversary = PalmDate(year: 1990, month: 6, day: 7).packed
    contact.blobs = [PalmBlob(type: "Bd01", data: Data([0, 0, UInt8(anniversary >> 8), UInt8(anniversary & 0xFF), 0]))]
    let realContact = DateFix.shift(contact, years: 28)
    #expect(realContact.birthday?.date.year == 1990)
    #expect(PalmDate(packed: UInt16(realContact.blobs[0].data[2]) << 8 | UInt16(realContact.blobs[0].data[3])).year == 2018)
    #expect(DateFix.shift(realContact, years: -28).encode() == contact.encode())
}

@Test func datesBeforeTheWindowBecomeItsFirstDay() {
    #expect(DateFix.shift(PalmDate(year: 1920, month: 3, day: 4), years: -28) == PalmDate(year: 1904, month: 1, day: 1))
}

@Test func aYearPast2031IsClampedNotLost() {
    // a record cannot hold 2040; it must not turn into "no date" either
    #expect(PalmDate(year: 2040, month: 5, day: 6).packed == PalmDate.maxRepresentable.packed)
    #expect(PalmDate(year: 2040, month: 5, day: 6).packed != PalmDate.none)
    #expect(PalmDate(year: 1899, month: 5, day: 6).packed == PalmDate(year: 1904, month: 1, day: 1).packed)
}

@Test func engineShiftsItemsSoRealYearsPast2031Survive() throws {
    // Palm with DateFix 1932: an appointment in 2040 is stored as 2012
    var engine = SyncEngine<SyncedEvent>()
    engine.dateShift = 28
    var stored = CalendarEvent(date: PalmDate(year: 2012, month: 3, day: 4))
    stored.title = "Far ahead"
    let palm = PalmRecordIn(id: 0x5001, category: 0, data: stored.encode())
    let plan = try engine.plan(palm: .all([palm]), palmCategories: ["Unfiled"], mac: [], mirror: SyncMirror(pcID: 1))
    // the Mac sees the real year, the mirror keeps the Palm's bytes
    #expect(plan.macCreates[0].item.date.year == 2040)
    #expect(try CalendarEvent(data: plan.entries[0].palmRecord).date.year == 2012)

    // and a Mac event in 2040 goes to the Palm as 2012, not as "no date"
    let macEvent = SyncedEvent(date: PalmDate(year: 2040, month: 3, day: 4), title: "Later", category: "Unfiled")
    let plan2 = try engine.plan(palm: .all([]), palmCategories: ["Unfiled"],
                                mac: [MacSyncItem(key: MacKey(seriesID: "m"), item: macEvent)], mirror: SyncMirror(pcID: 1))
    #expect(try CalendarEvent(data: plan2.palmWrites[0].record).date == PalmDate(year: 2012, month: 3, day: 4))
    #expect(plan2.entries[0].item.date.year == 2040)
}

@Test func aChangedStartYearRewritesEveryRecordInTheNewYears() throws {
    // synced under DateFix 1972: a 2026 appointment is stored as 1958 and mirrored as 2026
    var stored = CalendarEvent(date: PalmDate(year: 1958, month: 10, day: 29))
    stored.title = "Dentist"
    let base = SyncedEvent(stored, category: "Unfiled").shiftingDates(by: 68)
    let mirror = SyncMirror<SyncedEvent>(pcID: 1, lastSync: Date(),
                                         entries: [.init(palmID: 0x6001, mac: MacKey(seriesID: "d"), base: base, palmRecord: stored.encode())],
                                         dateFixStartYear: 1972)
    let mac = [MacSyncItem(key: MacKey(seriesID: "d"), item: base)]

    // DateFix moved to 1932: the same bytes now mean 1986 on the Palm
    var engine = SyncEngine<SyncedEvent>()
    engine.dateShift = 28
    engine.previousDateShift = 68
    let palm = PalmRecordIn(id: 0x6001, category: 0, data: stored.encode())
    let plan = try engine.plan(palm: .all([palm]), palmCategories: ["Unfiled"], mac: mac, mirror: mirror)
    // nothing changed for the Mac, the Palm gets the record back in its new years: 2026 − 28 = 1998
    #expect(plan.macUpdates.isEmpty && plan.macCreates.isEmpty && plan.conflicts.isEmpty)
    #expect(plan.palmWrites.count == 1 && plan.palmWrites[0].id == 0x6001)
    #expect(try CalendarEvent(data: plan.palmWrites[0].record).date == PalmDate(year: 1998, month: 10, day: 29))
    #expect(plan.entries[0].item.date.year == 2026)
    #expect(plan.log.contains { $0.contains("DateFix changed") })
    // a Palm record entered after the change is read with the new shift
    var fresh = CalendarEvent(date: PalmDate(year: 1999, month: 1, day: 2))
    fresh.title = "New on the Palm"
    let plan2 = try engine.plan(palm: .all([palm, PalmRecordIn(id: 0x6002, category: 0, data: fresh.encode())]),
                                palmCategories: ["Unfiled"], mac: mac, mirror: mirror)
    #expect(plan2.macCreates.count == 1 && plan2.macCreates[0].item.date.year == 2027)

    // the mirror from before the year was recorded says nothing, so nothing is rewritten
    #expect(SyncMirror<SyncedEvent>(pcID: 1).dateFixStartYear == nil)
}

@Test func clampedBirthdayKeepsTheMirrorsValue() {
    // on the Palm (start year 1972) a 1962 birthday became 1972-01-01; read back, the mirror's date stands
    var item = SyncedContact(lastName: "Leto", birthday: PalmDate(year: 1972, month: 1, day: 1), category: "Unfiled")
    var base = item
    base.birthday = PalmDate(year: 1962, month: 5, day: 6)
    #expect(DateFix.unclamp(item, startYear: 1972, base: base).birthday == PalmDate(year: 1962, month: 5, day: 6))
    // a real 1 January 1972 birthday is left alone
    base.birthday = PalmDate(year: 1980, month: 2, day: 3)
    #expect(DateFix.unclamp(item, startYear: 1972, base: base) == item)
    item.birthday = nil
    #expect(DateFix.unclamp(item, startYear: 1972, base: base) == item)
}
