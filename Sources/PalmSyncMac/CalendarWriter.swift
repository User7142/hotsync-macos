import EventKit
import Foundation
import PalmSync

/// Applies the Mac side of a calendar sync plan to Calendar.app. A new
/// event gets every shared field; an update gets only the fields the Palm
/// changed, so a multi-day event keeps its length, a second alarm stays,
/// the time zone stays, and a series keeps its start unless the Palm
/// moved it. The mapping is a set of static functions, tested without
/// saving; `apply` does the saving and returns the keys of what it created.
public struct CalendarWriter {
    public struct Result: Equatable, Sendable {
        /// Entry index of each create in the plan → the key the Mac gave it.
        public var createdKeys: [Int: MacKey] = [:]
        public var updated = 0
        public var deleted = 0
        public var failures: [String] = []
        /// Entry indices of creates and updates that did not happen, so the
        /// mirror keeps the old base for them and they are retried.
        public var failedEntries: [Int] = []
    }

    public let store: EKEventStore
    public let homeZone: TimeZone
    /// Which Mac calendar a Palm category name goes to (the chosen calendar
    /// whose category, cut to the Palm's 15 characters, is that name).
    public let calendarForCategory: (String) -> EKCalendar?
    /// Where a new event goes when no calendar matches its category.
    public let fallback: EKCalendar?
    private let calendar: Calendar

    public init(store: EKEventStore, homeZone: TimeZone = .current, fallback: EKCalendar? = nil,
                calendarForCategory: @escaping (String) -> EKCalendar?) {
        self.store = store
        self.homeZone = homeZone
        self.fallback = fallback
        self.calendarForCategory = calendarForCategory
        var c = Calendar(identifier: .gregorian)
        c.timeZone = homeZone
        calendar = c
    }

    // MARK: Mapping

    public static func date(_ d: PalmDate, _ t: PalmTime?, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: t?.hour ?? 0, minute: t?.minute ?? 0))!
    }

    /// Writes the shared fields into the event: all of them for a new
    /// event (`fields` nil), otherwise only the named ones. Fields the Palm
    /// has no say in (attendees, URL, travel time, a second alarm, the
    /// zone of an existing event, the length of a multi-day event) are
    /// left alone.
    /// An untimed event repeating daily through an end date, with no day
    /// skipped, is how the Palm holds a multi-day all-day event: its last
    /// day, or nil for anything else.
    public static func multiDayEnd(of event: SyncedEvent) -> PalmDate? {
        guard event.time == nil, let rule = event.repeatRule, rule.type == .daily, rule.frequency == 1,
              let end = rule.endDate, event.exceptions.isEmpty else { return nil }
        return end
    }

    public static func fill(_ ek: EKEvent, from event: SyncedEvent, in calendar: Calendar, fields: Set<SyncedEvent.Field>? = nil) {
        let isNew = fields == nil
        func wanted(_ f: SyncedEvent.Field) -> Bool { fields?.contains(f) ?? true }
        let multiDayEnd = multiDayEnd(of: event)

        if wanted(.title) { ek.title = event.title ?? "" }
        if wanted(.note) {
            // the builder puts the URL on the note's last line; it lives in ek.url
            var note = event.note ?? ""
            if let url = ek.url?.absoluteString, note.hasSuffix(url) {
                note = String(note.dropLast(url.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            ek.notes = note.isEmpty ? nil : note
        }
        if wanted(.location) { ek.location = event.location }

        if isNew {
            ek.timeZone = calendar.timeZone
        }
        if wanted(.date) || wanted(.time) {
            if let time = event.time {
                let start = date(event.date, time.start, in: calendar)
                var end = date(event.date, time.end, in: calendar)
                if end < start { end = start }
                if !isNew, let oldStart = ek.startDate, let oldEnd = ek.endDate,
                   calendar.startOfDay(for: oldEnd) > calendar.startOfDay(for: oldStart) {
                    // a multi-day event: the Palm shows one day of it; keep its length
                    end = start.addingTimeInterval(oldEnd.timeIntervalSince(oldStart))
                }
                ek.isAllDay = false
                ek.startDate = start
                ek.endDate = end
            } else {
                // EventKit keeps an all-day event on the device's local day
                let start = date(event.date, nil, in: Calendar.current)
                var end = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: start)!
                if let lastDay = multiDayEnd {
                    end = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: date(lastDay, nil, in: Calendar.current))!
                } else if !isNew, ek.isAllDay, let oldStart = ek.startDate, let oldEnd = ek.endDate {
                    end = start.addingTimeInterval(oldEnd.timeIntervalSince(oldStart))
                }
                ek.isAllDay = true
                if isNew { ek.timeZone = nil }
                ek.startDate = start
                ek.endDate = end
            }
        }

        if wanted(.alarm) {
            ek.alarms = nil
            if let alarm = event.alarm {
                let seconds: TimeInterval
                switch alarm.unit {
                case .minutes: seconds = TimeInterval(alarm.advance) * 60
                case .hours: seconds = TimeInterval(alarm.advance) * 3600
                case .days: seconds = TimeInterval(alarm.advance) * 86400
                }
                ek.addAlarm(EKAlarm(relativeOffset: -seconds))
            }
        }

        if wanted(.repeatRule) {
            if let existing = ek.recurrenceRules { for rule in existing { ek.removeRecurrenceRule(rule) } }
            if let lastDay = multiDayEnd {
                // the Palm's daily-until is the Mac's multi-day event: its end moves, no rule
                if !(wanted(.date) || wanted(.time)), ek.isAllDay, ek.startDate != nil {
                    ek.endDate = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: date(lastDay, nil, in: Calendar.current))!
                }
            } else if let rule = event.repeatRule {
                ek.addRecurrenceRule(recurrenceRule(rule, start: event.date, in: calendar))
            }
        }
    }

    /// The EventKit rule for a Palm rule.
    public static func recurrenceRule(_ rule: CalendarEvent.Repeat, start: PalmDate, in calendar: Calendar) -> EKRecurrenceRule {
        let end = rule.endDate.map { EKRecurrenceEnd(end: date($0, PalmTime(hour: 23, minute: 59), in: calendar)) }
        let interval = max(1, Int(rule.frequency))
        switch rule.type {
        case .daily:
            return EKRecurrenceRule(recurrenceWith: .daily, interval: interval, end: end)
        case .weekly:
            let mask = rule.weekdays.isEmpty ? CalendarEvent.Weekdays(rawValue: 1 << UInt8(start.weekday)) : rule.weekdays
            let days = (0..<7).filter { mask.rawValue & (1 << $0) != 0 }
                .map { EKRecurrenceDayOfWeek(EKWeekday(rawValue: $0 + 1)!) }
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: interval, daysOfTheWeek: days, daysOfTheMonth: nil,
                                    monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: end)
        case .monthlyByDate:
            return EKRecurrenceRule(recurrenceWith: .monthly, interval: interval, daysOfTheWeek: nil,
                                    daysOfTheMonth: [NSNumber(value: start.day)], monthsOfTheYear: nil, weeksOfTheYear: nil,
                                    daysOfTheYear: nil, setPositions: nil, end: end)
        case .monthlyByDay:
            let week = Int(rule.on) / 7, weekday = Int(rule.on) % 7
            let day = EKRecurrenceDayOfWeek(EKWeekday(rawValue: weekday + 1)!, weekNumber: week >= 4 ? -1 : week + 1)
            return EKRecurrenceRule(recurrenceWith: .monthly, interval: interval, daysOfTheWeek: [day], daysOfTheMonth: nil,
                                    monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: end)
        case .yearly:
            return EKRecurrenceRule(recurrenceWith: .yearly, interval: interval, end: end)
        }
    }

    // MARK: Applying

    /// Applies the plan's Mac changes: creates, updates, deletes, in that
    /// order. A failure is recorded and the rest goes on.
    public func apply(_ plan: CalendarSyncPlan) -> Result {
        var result = Result()

        for change in plan.macCreates {
            guard let target = calendarForCategory(change.item.category) ?? fallback ?? store.defaultCalendarForNewEvents else {
                result.failures.append("\(change.item.title ?? "?"): no calendar for category \(change.item.category)")
                result.failedEntries.append(change.entry)
                continue
            }
            let ek = EKEvent(eventStore: store)
            ek.calendar = target
            Self.fill(ek, from: change.item, in: calendar)
            do {
                try store.save(ek, span: .futureEvents, commit: true)
                removeExceptions(of: ek, change.item.exceptions)
                result.createdKeys[change.entry] = MacKey(seriesID: ek.calendarItemIdentifier)
            } catch {
                result.failures.append("\(change.item.title ?? "?"): \(error.localizedDescription)")
                result.failedEntries.append(change.entry)
            }
        }

        for change in plan.macUpdates {
            guard let key = change.key, let ek = find(key) else {
                result.failures.append("\(change.item.title ?? "?"): not found on the Mac any more")
                result.failedEntries.append(change.entry)
                continue
            }
            let fields = Set(change.changed)
            Self.fill(ek, from: change.item, in: calendar, fields: fields)
            // an event moves calendars only when the Palm changed its category
            if fields.contains(.category), let target = calendarForCategory(change.item.category), target != ek.calendar {
                ek.calendar = target
            }
            do {
                try store.save(ek, span: key.occurrence == nil ? .futureEvents : .thisEvent, commit: true)
                if key.occurrence == nil, fields.contains(.exceptions) { removeExceptions(of: ek, change.item.exceptions) }
                result.updated += 1
            } catch {
                result.failures.append("\(change.item.title ?? "?"): \(error.localizedDescription)")
                result.failedEntries.append(change.entry)
            }
        }

        for key in plan.macDeletes {
            guard let ek = find(key) else { continue }   // already gone: fine
            do {
                try store.remove(ek, span: key.occurrence == nil ? .futureEvents : .thisEvent, commit: true)
                result.deleted += 1
            } catch {
                result.failures.append("\(ek.title ?? "?"): \(error.localizedDescription)")
            }
        }
        return result
    }

    /// The event (or the one occurrence) a key names.
    public func find(_ key: MacKey) -> EKEvent? {
        guard let item = store.calendarItem(withIdentifier: key.seriesID) as? EKEvent else { return nil }
        guard let occurrence = key.occurrence else { return item }
        let day = calendar.startOfDay(for: occurrence)
        let predicate = store.predicateForEvents(withStart: day.addingTimeInterval(-86400), end: day.addingTimeInterval(2 * 86400),
                                                 calendars: [item.calendar])
        return store.events(matching: predicate).first {
            $0.calendarItemIdentifier == key.seriesID && $0.occurrenceDate == occurrence
        }
    }

    /// The Palm's exception dates: those plain occurrences disappear from
    /// the Mac. An occurrence the Mac detached (edited or moved on its own)
    /// is an item of its own in the plan and stays.
    private func removeExceptions(of master: EKEvent, _ exceptions: [PalmDate]) {
        guard !exceptions.isEmpty else { return }
        for date in exceptions {
            let day = Self.date(date, nil, in: calendar)
            let predicate = store.predicateForEvents(withStart: day, end: calendar.date(byAdding: .day, value: 1, to: day)!,
                                                     calendars: [master.calendar])
            for occurrence in store.events(matching: predicate)
            where occurrence.calendarItemIdentifier == master.calendarItemIdentifier && !occurrence.isDetached {
                try? store.remove(occurrence, span: .thisEvent, commit: true)
            }
        }
    }
}
