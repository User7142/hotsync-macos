import EventKit
import Foundation
import PalmSync

/// Applies the Mac side of a tasks sync plan to Reminders.app. Only the
/// fields the Palm changed are rewritten: the reminder's URL, its due time
/// of day, its extra alarms stay unless the Palm touched the field they
/// belong to.
public struct TaskWriter {
    public struct Result: Equatable, Sendable {
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
    /// Which Reminders list a Palm category goes to.
    public let listForCategory: (String) -> EKCalendar?
    /// Where a new reminder goes when no list matches its category.
    public let fallback: EKCalendar?
    private let calendar: Calendar
    private let builder: TasksBuilder

    public init(store: EKEventStore, homeZone: TimeZone = .current, today: PalmDate, startOfWeek: UInt8 = 0,
                fallback: EKCalendar? = nil, listForCategory: @escaping (String) -> EKCalendar?) {
        self.store = store
        self.homeZone = homeZone
        self.listForCategory = listForCategory
        self.fallback = fallback
        var c = Calendar(identifier: .gregorian)
        c.timeZone = homeZone
        calendar = c
        builder = TasksBuilder(options: .init(lists: [], keepCompletedDays: Int.max / 2, today: today, startOfWeek: startOfWeek))
    }

    // MARK: Mapping

    /// EventKit's priority for the Palm's, the inverse of the builder's.
    public static func macPriority(_ palm: UInt8) -> Int {
        switch palm {
        case ...1: return 0
        case 2: return 3
        case 3: return 5
        case 4: return 7
        default: return 9
        }
    }

    /// Writes the fields in which `item` differs from what the reminder
    /// holds now, seen through the builder.
    public func fill(_ r: EKReminder, from item: SyncedTask) {
        let now = SyncedTask(builder.palmTask(ReminderSource.macReminder(r, calendar: calendar)), category: item.category)

        if item.differs(from: now, in: .title) { r.title = item.title ?? "" }
        if item.differs(from: now, in: .note) {
            // the builder put the URL at the end of the note; it lives in r.url
            var note = item.note ?? ""
            if let url = r.url?.absoluteString, note.hasSuffix(url) {
                note = String(note.dropLast(url.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            r.notes = note.isEmpty ? nil : note
        }
        if item.differs(from: now, in: .dueDate) {
            if let due = item.dueDate {
                var c = DateComponents(year: due.year, month: due.month, day: due.day)
                c.hour = r.dueDateComponents?.hour
                c.minute = r.dueDateComponents?.minute
                r.dueDateComponents = c
            } else {
                r.dueDateComponents = nil
            }
        }
        if item.differs(from: now, in: .completedDate) {
            if let done = item.completedDate {
                r.isCompleted = true
                r.completionDate = CalendarWriter.date(done, nil, in: calendar)
            } else {
                r.isCompleted = false
                r.completionDate = nil
            }
        }
        if item.differs(from: now, in: .priority) { r.priority = Self.macPriority(item.priority) }
        if item.differs(from: now, in: .alarm) {
            for alarm in r.alarms ?? [] { r.removeAlarm(alarm) }
            if let alarm = item.alarm, let due = item.dueDate ?? now.dueDate {
                let day = due.adding(days: -Int(alarm.daysEarlier))
                r.addAlarm(EKAlarm(absoluteDate: CalendarWriter.date(day, alarm.time, in: calendar)))
            }
        }
        if item.differs(from: now, in: .repeatRule) {
            for rule in r.recurrenceRules ?? [] { r.removeRecurrenceRule(rule) }
            if let repeatRule = item.repeatRule {
                r.addRecurrenceRule(CalendarWriter.recurrenceRule(repeatRule.rule, start: repeatRule.start, in: calendar))
            }
        }
    }

    // MARK: Applying

    public func apply(_ plan: TaskSyncPlan) -> Result {
        var result = Result()

        for change in plan.macCreates {
            guard let list = listForCategory(change.item.category) ?? fallback ?? store.defaultCalendarForNewReminders() else {
                result.failures.append("\(change.item.title ?? "?"): no list for category \(change.item.category)")
                result.failedEntries.append(change.entry)
                continue
            }
            let r = EKReminder(eventStore: store)
            r.calendar = list
            fill(r, from: change.item)
            do {
                try store.save(r, commit: true)
                result.createdKeys[change.entry] = MacKey(seriesID: r.calendarItemIdentifier)
            } catch {
                result.failures.append("\(change.item.title ?? "?"): \(error.localizedDescription)")
                result.failedEntries.append(change.entry)
            }
        }

        for change in plan.macUpdates {
            guard let key = change.key, let r = find(key) else {
                result.failures.append("\(change.item.title ?? "?"): not found on the Mac any more")
                result.failedEntries.append(change.entry)
                continue
            }
            fill(r, from: change.item)
            // a reminder moves lists only when the Palm changed its category
            if change.changed.contains(.category), let list = listForCategory(change.item.category), list != r.calendar { r.calendar = list }
            do {
                try store.save(r, commit: true)
                result.updated += 1
            } catch {
                result.failures.append("\(change.item.title ?? "?"): \(error.localizedDescription)")
                result.failedEntries.append(change.entry)
            }
        }

        for key in plan.macDeletes {
            guard let r = find(key) else { continue }
            do {
                try store.remove(r, commit: true)
                result.deleted += 1
            } catch {
                result.failures.append("\(r.title ?? "?"): \(error.localizedDescription)")
            }
        }
        return result
    }

    public func find(_ key: MacKey) -> EKReminder? {
        store.calendarItem(withIdentifier: key.seriesID) as? EKReminder
    }
}
