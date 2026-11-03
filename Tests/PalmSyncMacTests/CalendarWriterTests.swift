import EventKit
import Foundation
import Testing
import PalmSync
@testable import PalmSyncMac

// The mapping only: EKEvents are made and filled, never saved, so no
// Calendar access is needed.
private let store = EKEventStore()
private let vancouver: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Vancouver")!
    return c
}()

@Test func timedEventFields() {
    let event = SyncedEvent(date: PalmDate(year: 2026, month: 10, day: 20),
                            time: .init(start: PalmTime(hour: 9, minute: 0), end: PalmTime(hour: 10, minute: 30)),
                            title: "Standup", note: "bring coffee", location: "Room 4",
                            alarm: .init(advance: 15, unit: .minutes), category: "Work")
    let ek = EKEvent(eventStore: store)
    CalendarWriter.fill(ek, from: event, in: vancouver)
    #expect(ek.title == "Standup" && ek.notes == "bring coffee" && ek.location == "Room 4")
    #expect(!ek.isAllDay)
    #expect(vancouver.dateComponents([.hour, .minute], from: ek.startDate).hour == 9)
    #expect(ek.endDate.timeIntervalSince(ek.startDate) == 90 * 60)
    #expect(ek.alarms?.first?.relativeOffset == -900)
    #expect(ek.timeZone?.identifier == "America/Vancouver")
    #expect(ek.recurrenceRules?.isEmpty ?? true)
}

@Test func allDayEvent() {
    let event = SyncedEvent(date: PalmDate(year: 2026, month: 11, day: 1), title: "Clocks stay", category: "Personal")
    let ek = EKEvent(eventStore: store)
    CalendarWriter.fill(ek, from: event, in: vancouver)
    #expect(ek.isAllDay)
    // an all-day event lives on the Mac's local day, whatever zone the Mac is in
    #expect(Calendar.current.component(.day, from: ek.startDate) == 1 && Calendar.current.component(.day, from: ek.endDate) == 1)
    #expect(ek.alarms == nil || ek.alarms?.isEmpty == true)
}

@Test func rulesBecomeRecurrenceRules() {
    let start = PalmDate(year: 2026, month: 10, day: 19)   // a Monday
    var weekly = CalendarEvent.Repeat(type: .weekly, endDate: PalmDate(year: 2026, month: 11, day: 30), frequency: 2)
    weekly.weekdays = [.monday, .wednesday]
    let w = CalendarWriter.recurrenceRule(weekly, start: start, in: vancouver)
    #expect(w.frequency == .weekly && w.interval == 2)
    #expect(w.daysOfTheWeek?.map(\.dayOfTheWeek.rawValue) == [2, 4])
    #expect(w.recurrenceEnd?.endDate.map { vancouver.component(.day, from: $0) } == 30)

    let byDate = CalendarWriter.recurrenceRule(.init(type: .monthlyByDate, frequency: 1), start: start, in: vancouver)
    #expect(byDate.frequency == .monthly && byDate.daysOfTheMonth?.first?.intValue == 19)

    let secondTuesday = CalendarWriter.recurrenceRule(.init(type: .monthlyByDay, frequency: 1, on: 9), start: start, in: vancouver)
    #expect(secondTuesday.daysOfTheWeek?.first?.dayOfTheWeek == .tuesday && secondTuesday.daysOfTheWeek?.first?.weekNumber == 2)
    let lastFriday = CalendarWriter.recurrenceRule(.init(type: .monthlyByDay, frequency: 1, on: 33), start: start, in: vancouver)
    #expect(lastFriday.daysOfTheWeek?.first?.weekNumber == -1)

    let yearly = CalendarWriter.recurrenceRule(.init(type: .yearly, frequency: 1), start: start, in: vancouver)
    #expect(yearly.frequency == .yearly && yearly.recurrenceEnd == nil)

    // the weekly rule without a day mask repeats on the start's weekday
    let bare = CalendarWriter.recurrenceRule(.init(type: .weekly, frequency: 1), start: start, in: vancouver)
    #expect(bare.daysOfTheWeek?.map(\.dayOfTheWeek) == [.monday])
}

@Test func fillReplacesRulesAndAlarms() {
    var event = SyncedEvent(date: PalmDate(year: 2026, month: 10, day: 19),
                            time: .init(start: PalmTime(hour: 8, minute: 0), end: PalmTime(hour: 8, minute: 15)),
                            title: "Meds", alarm: .init(advance: 1, unit: .hours),
                            repeatRule: .init(type: .daily, frequency: 1), category: "Medicine")
    let ek = EKEvent(eventStore: store)
    CalendarWriter.fill(ek, from: event, in: vancouver)
    #expect(ek.recurrenceRules?.count == 1 && ek.alarms?.count == 1)
    event.repeatRule = nil
    event.alarm = nil
    CalendarWriter.fill(ek, from: event, in: vancouver)
    #expect(ek.recurrenceRules?.isEmpty ?? true)
    #expect(ek.alarms?.isEmpty ?? true)
}

@Test func palmRoundTripThroughTheMacModel() {
    // what the writer puts into EventKit, CalendarSource reads back as the same Palm rule
    let start = PalmDate(year: 2026, month: 10, day: 13)
    let ek = EKEvent(eventStore: store)
    var rule = CalendarEvent.Repeat(type: .weekly, frequency: 1)
    rule.weekdays = [.tuesday, .thursday]
    CalendarWriter.fill(ek, from: SyncedEvent(date: start, title: "x", repeatRule: rule, category: "c"), in: vancouver)
    let mac = CalendarSource.macRecurrence(ek.recurrenceRules ?? [])
    #expect(mac?.frequency == .weekly && mac?.daysOfTheWeek.map(\.weekday) == [3, 5])
    let back = CalendarBuilder.palmRule(mac!, startDate: start, endDate: nil, defaultWeekStart: 0)
    #expect(back?.type == .weekly && back?.weekdays == [.tuesday, .thursday])
}

@Test func updateTouchesOnlyTheChangedFields() {
    // a three-day timed event with two alarms and a URL on the Mac
    let ek = EKEvent(eventStore: store)
    ek.title = "Conference"
    ek.startDate = vancouver.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9, minute: 0))!
    ek.endDate = vancouver.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 17, minute: 0))!
    ek.timeZone = TimeZone(identifier: "Europe/Berlin")
    ek.addAlarm(EKAlarm(relativeOffset: -900))
    ek.addAlarm(EKAlarm(relativeOffset: -3600))
    ek.url = URL(string: "https://example.com/conf")
    ek.notes = "bring the badge"

    // the Palm changed the title and moved it a day later; its note still ends in the URL
    let event = SyncedEvent(date: PalmDate(year: 2026, month: 10, day: 21),
                            time: .init(start: PalmTime(hour: 9, minute: 0), end: PalmTime(hour: 17, minute: 0)),
                            title: "Conference 2026", note: "bring the badge\nhttps://example.com/conf", category: "Work")
    CalendarWriter.fill(ek, from: event, in: vancouver, fields: [.title, .date])
    #expect(ek.title == "Conference 2026")
    #expect(vancouver.component(.day, from: ek.startDate) == 21)
    #expect(ek.endDate.timeIntervalSince(ek.startDate) == 2 * 86400 + 8 * 3600)   // still three days long
    #expect(ek.alarms?.count == 2)                                                  // both alarms kept
    #expect(ek.timeZone?.identifier == "Europe/Berlin")                              // zone kept
    #expect(ek.notes == "bring the badge")                                           // untouched

    // the note alone: the URL line is stripped, nothing else moves
    CalendarWriter.fill(ek, from: event, in: vancouver, fields: [.note])
    #expect(ek.notes == "bring the badge" && ek.url?.absoluteString == "https://example.com/conf")
}

@Test func palmDailyUntilBecomesAMultiDayAllDayEvent() {
    let palm = SyncedEvent(date: PalmDate(year: 2026, month: 10, day: 20), title: "Conference",
                           repeatRule: .init(type: .daily, endDate: PalmDate(year: 2026, month: 10, day: 22), frequency: 1), category: "Work")
    #expect(CalendarWriter.multiDayEnd(of: palm) == PalmDate(year: 2026, month: 10, day: 22))
    let ek = EKEvent(eventStore: store)
    CalendarWriter.fill(ek, from: palm, in: vancouver)
    #expect(ek.isAllDay && (ek.recurrenceRules?.isEmpty ?? true))
    #expect(Calendar.current.component(.day, from: ek.startDate) == 20 && Calendar.current.component(.day, from: ek.endDate) == 22)

    // the Palm extends it by a day: only the end moves, still no rule
    var longer = palm
    longer.repeatRule?.endDate = PalmDate(year: 2026, month: 10, day: 23)
    CalendarWriter.fill(ek, from: longer, in: vancouver, fields: [.repeatRule])
    #expect(Calendar.current.component(.day, from: ek.endDate) == 23 && (ek.recurrenceRules?.isEmpty ?? true))

    // a daily rule with a skipped day is a real recurrence
    var skipping = palm
    skipping.exceptions = [PalmDate(year: 2026, month: 10, day: 21)]
    #expect(CalendarWriter.multiDayEnd(of: skipping) == nil)
}
