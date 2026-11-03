import Foundation
import Testing
import HotSyncCore
@testable import PalmSync

// Everything here runs in Vancouver time after the 2026-11-01 change: UTC-7
// all year on a Mac with tzdata 2026b or later; the window spans the change.
private let vancouver = TimeZone(identifier: "America/Vancouver")!
private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = vancouver
    return c
}()

private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

private let work = CalendarBuilder.MacCalendar(id: "ical-work", title: "Work")
private let family = CalendarBuilder.MacCalendar(id: "ical-family", title: "Family")
private let google = CalendarBuilder.MacCalendar(id: "g-work", title: "zoe@gmail.com", category: "Work")

private func builder(calendars: [CalendarBuilder.MacCalendar] = [work, family, google]) -> CalendarBuilder {
    CalendarBuilder(options: .init(homeZone: vancouver, windowStart: at(2026, 7, 21), windowEnd: at(2027, 10, 19),
                                   calendars: calendars))
}

private func event(_ title: String, _ start: Date, minutes: Int = 60, calendar: String = "ical-work",
                   series: String? = nil, rule: MacRecurrence? = nil, external: String? = nil,
                   allDay: Bool = false, occurrence: Date? = nil, detached: Bool = false) -> MacEvent {
    MacEvent(externalID: external, seriesID: series ?? title, calendarID: calendar, title: title,
             start: start, end: start.addingTimeInterval(TimeInterval(minutes * 60)), isAllDay: allDay,
             recurrence: rule, occurrenceDate: occurrence, isDetached: detached)
}

private func decoded(_ db: PalmDatabase) -> [CalendarEvent] {
    db.records.map { try! CalendarEvent(data: $0.data) }
}

// MARK: - PalmRecurrence

@Test func dailyAndWeeklyOccurrences() {
    let start = PalmDate(year: 2026, month: 10, day: 19)   // a Monday
    let daily = PalmRecurrence.occurrences(of: .init(type: .daily, frequency: 3), startingOn: start,
                                           through: PalmDate(year: 2026, month: 10, day: 31))
    #expect(daily.map(\.day) == [19, 22, 25, 28, 31])

    var weekly = CalendarEvent.Repeat(type: .weekly, frequency: 2, on: 0, weekStart: 0)
    weekly.weekdays = [.monday, .wednesday, .friday]
    let dates = PalmRecurrence.occurrences(of: weekly, startingOn: start, through: PalmDate(year: 2026, month: 11, day: 8))
    #expect(dates.map(\.day) == [19, 21, 23, 2, 4, 6])   // week of Oct 19, skip Oct 26, week of Nov 2
    #expect(dates.allSatisfy { [1, 3, 5].contains($0.weekday) })

    let ended = PalmRecurrence.occurrences(of: .init(type: .daily, endDate: PalmDate(year: 2026, month: 10, day: 20), frequency: 1),
                                           startingOn: start, through: PalmDate(year: 2027, month: 1, day: 1))
    #expect(ended.count == 2)
}

@Test func monthlyAndYearlyOccurrences() {
    let jan31 = PalmDate(year: 2026, month: 1, day: 31)
    let byDate = PalmRecurrence.occurrences(of: .init(type: .monthlyByDate, frequency: 1), startingOn: jan31,
                                            through: PalmDate(year: 2026, month: 4, day: 30))
    #expect(byDate == [jan31, PalmDate(year: 2026, month: 2, day: 28), PalmDate(year: 2026, month: 3, day: 31),
                       PalmDate(year: 2026, month: 4, day: 30)])

    // second Tuesday (on = 1 * 7 + 2) and last Friday (on = 4 * 7 + 5)
    let secondTuesday = PalmRecurrence.occurrences(of: .init(type: .monthlyByDay, frequency: 1, on: 9),
                                                   startingOn: PalmDate(year: 2026, month: 10, day: 13),
                                                   through: PalmDate(year: 2026, month: 12, day: 31))
    #expect(secondTuesday == [PalmDate(year: 2026, month: 10, day: 13), PalmDate(year: 2026, month: 11, day: 10),
                              PalmDate(year: 2026, month: 12, day: 8)])
    let lastFriday = PalmRecurrence.occurrences(of: .init(type: .monthlyByDay, frequency: 1, on: 33),
                                                startingOn: PalmDate(year: 2026, month: 10, day: 30),
                                                through: PalmDate(year: 2026, month: 12, day: 31))
    #expect(lastFriday.map(\.day) == [30, 27, 25])

    let leap = PalmRecurrence.occurrences(of: .init(type: .yearly, frequency: 1), startingOn: PalmDate(year: 2024, month: 2, day: 29),
                                          through: PalmDate(year: 2028, month: 12, day: 31))
    #expect(leap.map { ($0.year, $0.day) }.map { "\($0.0)-\($0.1)" } == ["2024-29", "2025-28", "2026-28", "2027-28", "2028-29"])
}

// MARK: - Single events

@Test func timedEventInHomeZone() {
    let (db, report) = builder().build([event("Standup", at(2026, 10, 20, 9, 0), external: "uid-1")])
    #expect(report.records == 1 && report.seriesMapped == 0)
    let e = decoded(db)[0]
    #expect(e.date == PalmDate(year: 2026, month: 10, day: 20))
    #expect(e.time == .init(start: PalmTime(hour: 9, minute: 0), end: PalmTime(hour: 10, minute: 0)))
    #expect(e.title == "Standup" && e.timezone == nil && e.blobs.isEmpty)
    #expect(db.records[0].category == 1)   // Work
    #expect(db.records[0].uniqueID == 1 && db.uniqueIDSeed == 2)
}

@Test func torontoMeetingLandsAtVancouverTime() {
    // 14:00 in Toronto on Nov 5, 2026 (EST, UTC-5) is 12:00 in Vancouver (UTC-7)
    var toronto = Calendar(identifier: .gregorian)
    toronto.timeZone = TimeZone(identifier: "America/Toronto")!
    let start = toronto.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 14))!
    let e = decoded(builder().build([event("Call", start)]).database)[0]
    #expect(e.time?.start == PalmTime(hour: 12, minute: 0))
    #expect(e.timezone == nil)
}

@Test func allDayMultiDayAlarmNoteAndURL() {
    var e = event("Trip", at(2026, 12, 24), minutes: 60 * 24 * 3, allDay: true)
    e.notes = "Pack"
    e.url = URL(string: "https://meet.example/x")
    e.location = ""
    e.alarmOffset = -2 * 24 * 3600
    var late = event("Party", at(2026, 12, 31, 22, 0), minutes: 240)
    late.alarmOffset = -90 * 60
    late.location = "Downtown"
    let untitled = event("   ", at(2027, 1, 1, 9, 0))
    let records = decoded(builder().build([e, late, untitled]).database)
    #expect(records[2].title == "(untitled)")
    #expect(records[0].time == nil)
    #expect(records[0].note == "Pack\nhttps://meet.example/x")
    #expect(records[0].location == nil)
    #expect(records[0].alarm == .init(advance: 2, unit: .days))
    #expect(records[1].time == .init(start: PalmTime(hour: 22, minute: 0), end: PalmTime(hour: 23, minute: 59)))
    #expect(records[1].alarm == .init(advance: 90, unit: .minutes))
    #expect(records[1].location == "Downtown")
}

@Test func alarmUnits() {
    let b = builder()
    #expect(b.alarm(for: -15 * 60) == .init(advance: 15, unit: .minutes))
    #expect(b.alarm(for: -3 * 3600) == .init(advance: 3, unit: .hours))
    #expect(b.alarm(for: -7 * 86400) == .init(advance: 7, unit: .days))
    #expect(b.alarm(for: -150 * 60) == .init(advance: 2, unit: .hours))   // 150 min: too many minutes, rounded down to hours
    #expect(b.alarm(for: 600) == nil)
    #expect(b.alarm(for: -200 * 86400) == nil)
}

// MARK: - Series

@Test func weeklySeriesWithDeletedAndDetachedOccurrences() {
    let rule = MacRecurrence(frequency: .weekly, daysOfTheWeek: [.init(2), .init(4)],   // Mon, Wed
                             end: .date(at(2026, 11, 30)))
    var occurrences: [MacEvent] = []
    var day = at(2026, 10, 19, 18, 0)   // Monday
    while day < at(2026, 12, 1) {
        let weekday = cal.component(.weekday, from: day)
        if weekday == 2 || weekday == 4 {
            occurrences.append(event("Gym", day, series: "gym", rule: rule, occurrence: day))
        }
        day = day.addingTimeInterval(86400)
    }
    // Oct 28 deleted on the Mac, Nov 4 moved to Nov 5 at 19:00
    occurrences.removeAll { cal.component(.day, from: $0.start) == 28 && cal.component(.month, from: $0.start) == 10 }
    if let i = occurrences.firstIndex(where: { $0.start == at(2026, 11, 4, 18, 0) }) {
        occurrences[i].start = at(2026, 11, 5, 19, 0)
        occurrences[i].end = at(2026, 11, 5, 20, 0)
        occurrences[i].isDetached = true
    }

    let (db, report) = builder().build(occurrences)
    #expect(report.seriesMapped == 1 && report.seriesExpanded == 0)
    #expect(report.detachedOccurrences == 1 && report.exceptions == 2)
    #expect(report.records == 2)
    let records = decoded(db)
    let series = try! #require(records.first { $0.repeatRule != nil })
    #expect(series.date == PalmDate(year: 2026, month: 10, day: 19))
    #expect(series.repeatRule?.type == .weekly)
    #expect(series.repeatRule?.weekdays == [.monday, .wednesday])
    #expect(series.repeatRule?.endDate == PalmDate(year: 2026, month: 11, day: 30))
    #expect(series.exceptions == [PalmDate(year: 2026, month: 10, day: 28), PalmDate(year: 2026, month: 11, day: 4)])
    let moved = try! #require(records.first { $0.repeatRule == nil })
    #expect(moved.date == PalmDate(year: 2026, month: 11, day: 5) && moved.time?.start == PalmTime(hour: 19, minute: 0))
    // sorted by date: the series (Oct 19) before the moved occurrence (Nov 5)
    #expect(records[0].repeatRule != nil)
}

@Test func rulesThePalmCanExpress() {
    let b = builder()
    let start = at(2026, 10, 13, 19, 0)   // second Tuesday of October
    #expect(b.palmRule(.init(frequency: .daily, interval: 2), start: start) == .init(type: .daily, frequency: 2))
    #expect(b.palmRule(.init(frequency: .monthly), start: start) == .init(type: .monthlyByDate, frequency: 1))
    #expect(b.palmRule(.init(frequency: .monthly, daysOfTheMonth: [13]), start: start)?.type == .monthlyByDate)
    #expect(b.palmRule(.init(frequency: .monthly, daysOfTheWeek: [.init(3, weekNumber: 2)]), start: start)
            == .init(type: .monthlyByDay, frequency: 1, on: 9))
    #expect(b.palmRule(.init(frequency: .monthly, daysOfTheWeek: [.init(6, weekNumber: -1)]), start: start)?.on == 33)
    #expect(b.palmRule(.init(frequency: .yearly), start: start)?.type == .yearly)
    #expect(b.palmRule(.init(frequency: .weekly, interval: 2, firstDayOfTheWeek: 2), start: start)
            == .init(type: .weekly, frequency: 2, on: 1 << 2, weekStart: 1))
}

@Test func rulesThePalmCannotExpressAreExpanded() {
    let b = builder()
    let start = at(2026, 10, 13, 19, 0)
    #expect(b.palmRule(.init(frequency: .weekly, end: .count(5)), start: start) == nil)
    #expect(b.palmRule(.init(frequency: .monthly, daysOfTheMonth: [1, 15]), start: start) == nil)
    #expect(b.palmRule(.init(frequency: .monthly, daysOfTheWeek: [.init(2), .init(4)], setPositions: [-1]), start: start) == nil)
    #expect(b.palmRule(.init(frequency: .yearly, monthsOfTheYear: [1, 7]), start: start) == nil)
    #expect(b.palmRule(.init(frequency: .daily, interval: 300), start: start) == nil)

    let counted = MacRecurrence(frequency: .daily, end: .count(3))
    let days = (0..<3).map { event("Pills", at(2026, 10, 20, 8, 0).addingTimeInterval(Double($0) * 86400), series: "pills", rule: counted) }
    let (db, report) = b.build(days)
    #expect(report.seriesExpanded == 1 && report.records == 3)
    #expect(decoded(db).allSatisfy { $0.repeatRule == nil })
    #expect(decoded(db).map(\.date.day) == [20, 21, 22])
}

// MARK: - Calendars, categories, duplicates

@Test func categoriesFollowTheCalendars() {
    let (db, report) = builder().build([
        event("A", at(2026, 10, 20, 9, 0), calendar: "ical-work"),
        event("B", at(2026, 10, 20, 10, 0), calendar: "ical-family"),
        event("C", at(2026, 10, 20, 11, 0), calendar: "g-work"),
        event("D", at(2026, 10, 20, 12, 0), calendar: "unknown"),
    ])
    #expect(report.categories == ["Unfiled", "Work", "Family"])
    #expect(db.records.map(\.category) == [1, 2, 1, 0])
    let info = try! CalendarAppInfo(data: db.appInfo!)
    #expect(info.categories.names[1] == "Work" && info.categories.names[3] == "")
}

@Test func sixteenthCalendarFoldsIntoOther() {
    let many = (1...17).map { CalendarBuilder.MacCalendar(id: "c\($0)", title: "Calendar \($0)") }
    let events = many.map { event($0.title, at(2026, 10, 20, 9, 0), calendar: $0.id) }
    let (db, report) = builder(calendars: many).build(events)
    #expect(report.categories.count == 16)
    #expect(report.categories.last == "Other")
    #expect(report.warnings.count == 1)
    #expect(db.records[13].category == 14)    // Calendar 14: its own
    #expect(db.records[14].category == 15)    // Calendar 15, 16, 17: Other
    #expect(db.records[16].category == 15)
}

@Test func sameInviteInTwoAccountsIsKeptOnce() {
    let (db, report) = builder().build([
        event("Review", at(2026, 10, 21, 15, 0), calendar: "g-work", external: "uid-9"),
        event("Review", at(2026, 10, 21, 15, 0), calendar: "ical-work", external: "uid-9"),
        event("Other", at(2026, 10, 21, 16, 0), calendar: "g-work", external: "uid-10"),
    ])
    #expect(report.duplicatesDropped == 1 && report.records == 2)
    #expect(db.records[0].category == 1)
}

@Test func recordsAreSortedByDateThenTime() {
    let (db, _) = builder().build([
        event("Late", at(2026, 10, 22, 20, 0)),
        event("Early", at(2026, 10, 21, 8, 0)),
        event("Day", at(2026, 10, 22), allDay: true),
        event("Noon", at(2026, 10, 22, 12, 0)),
    ])
    #expect(decoded(db).map(\.title) == ["Early", "Day", "Noon", "Late"])
}

@Test func builtDatabaseIsAValidInstallFile() {
    let (db, _) = builder().build([event("X", at(2026, 10, 20, 9, 0))])
    let data = db.encode()
    let file = try! PalmDatabaseFile.inspect(data: data, fileExtension: "pdb").get()
    #expect(file.name == "CalendarDB-PDat" && file.creator == "PDat" && file.recordCount == 1)
    // what a Palm OS 5.4 device writes for its own PIM databases
    #expect(db.version == 1 && db.attributes == 0 && db.appInfo?.count == 300)
    let info = try! CalendarAppInfo(data: db.appInfo!)
    #expect(info.categories.lastUniqueID == 15 && info.categories.ids == Array(0...15))
    #expect(try! PalmDatabase(data: data) == db)
}

@Test func noExceptionOnTheWindowsLastDay() {
    // a daily series fetched up to (not including) windowEnd: the window's
    // last day is not an occurrence the Mac returned, and must not become
    // an exception that changes with every sync
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = vancouver
    let windowEnd = at(2027, 10, 19)
    let rule = MacRecurrence(frequency: .daily)
    var occurrences: [MacEvent] = []
    var day = at(2026, 10, 20, 9, 0)
    while day < windowEnd {
        occurrences.append(MacEvent(seriesID: "daily", calendarID: "ical-work", title: "Daily", start: day,
                                    end: day.addingTimeInterval(1800), isAllDay: false, recurrence: rule,
                                    occurrenceDate: day))
        day = cal.date(byAdding: .day, value: 1, to: day)!
    }
    let (items, report) = builder().items(occurrences)
    #expect(items.count == 1 && report.exceptions == 0)
    #expect(items[0].event.exceptions.isEmpty)
}

@Test func multiDayAllDayEventRepeatsDailyThroughItsLastDay() {
    // Oct 20-22 all day on the Mac (EventKit's end: the last day, 23:59:59)
    let start = at(2026, 10, 20)
    let end = at(2026, 10, 22, 23, 59)
    let trip = MacEvent(seriesID: "trip", calendarID: "ical-work", title: "Conference", start: start, end: end, isAllDay: true)
    let (items, _) = builder().items([trip])
    let record = items[0].event
    #expect(record.time == nil && record.date == PalmDate(year: 2026, month: 10, day: 20))
    #expect(record.repeatRule == .init(type: .daily, endDate: PalmDate(year: 2026, month: 10, day: 22), frequency: 1))
    // one day stays plain
    let day = MacEvent(seriesID: "day", calendarID: "ical-work", title: "Holiday", start: start, end: at(2026, 10, 20, 23, 59), isAllDay: true)
    #expect(builder().items([day]).items[0].event.repeatRule == nil)
}
