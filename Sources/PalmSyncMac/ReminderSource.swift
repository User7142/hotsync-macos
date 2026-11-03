import EventKit
import Foundation
import PalmSync

/// Reminders.app through EventKit, as the sync sees it: the lists to choose
/// from and their reminders as MacReminders. Reminders have their own
/// access grant, so this is a store of its own.
public final class ReminderSource: @unchecked Sendable {
    public struct List: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let source: String

        public init(id: String, title: String, source: String) {
            self.id = id
            self.title = title
            self.source = source
        }
    }

    public let store = EKEventStore()

    public init() {}

    public var accessStatus: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .reminder) }
    public var hasAccess: Bool { accessStatus == .fullAccess }

    public func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }

    public func lists() -> [List] {
        store.calendars(for: .reminder)
            .map { List(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title) }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
    }

    /// Every reminder of the given lists, open and completed alike (the
    /// builder decides how long completed ones stay). A list that no longer
    /// exists, or a fetch that returns nothing at all, is an error: the sync
    /// must not take it for "everything deleted".
    public func reminders(in listIDs: [String], homeZone: TimeZone = .current) async throws -> [MacReminder] {
        var lists: [EKCalendar] = []
        for id in listIDs {
            guard let list = store.calendar(withIdentifier: id) else { throw CalendarSource.Failure.calendarMissing(id) }
            lists.append(list)
        }
        guard !lists.isEmpty else { return [] }
        let predicate = store.predicateForReminders(in: lists)
        let fetched: [EKReminder]? = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: $0) }
        }
        guard let found = fetched else { throw CalendarSource.Failure.fetchFailed }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = homeZone
        return found.map { Self.macReminder($0, calendar: calendar) }
    }

    static func palmDate(_ c: DateComponents?) -> PalmDate? {
        guard let c, let y = c.year, let m = c.month, let d = c.day, y >= 1904 else { return nil }
        return PalmDate(year: y, month: m, day: d)
    }

    public static func macReminder(_ r: EKReminder, calendar: Calendar) -> MacReminder {
        let due = r.dueDateComponents
        var dueTime: PalmTime?
        if let h = due?.hour, let m = due?.minute { dueTime = PalmTime(hour: h, minute: m) }

        // the first alarm, as the day and time it fires in the home zone
        var alarmDate: PalmDate?
        var alarmTime: PalmTime?
        let dueInstant = due.flatMap { calendar.date(from: $0) }
        if let alarm = r.alarms?.first {
            var fire = alarm.absoluteDate
            if fire == nil, let dueInstant { fire = dueInstant.addingTimeInterval(alarm.relativeOffset) }
            if let fire {
                let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                alarmDate = PalmDate(year: c.year!, month: c.month!, day: c.day!)
                alarmTime = PalmTime(hour: c.hour!, minute: c.minute!)
            }
        }

        var recurrenceEnd: PalmDate?
        if let end = r.recurrenceRules?.first?.recurrenceEnd?.endDate {
            let c = calendar.dateComponents([.year, .month, .day], from: end)
            recurrenceEnd = PalmDate(year: c.year!, month: c.month!, day: c.day!)
        }
        var completion: PalmDate?
        if let date = r.completionDate {
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            completion = PalmDate(year: c.year!, month: c.month!, day: c.day!)
        } else if r.isCompleted, let dueDate = palmDate(due) {
            completion = dueDate
        }

        return MacReminder(
            id: r.calendarItemIdentifier,
            listID: r.calendar?.calendarIdentifier ?? "",   // nil on a reminder not yet in a list
            title: r.title ?? "",
            notes: r.notes,
            url: r.url,
            dueDate: palmDate(due),
            dueTime: dueTime,
            priority: r.priority,
            completionDate: completion,
            alarmDate: alarmDate,
            alarmTime: alarmTime,
            recurrence: r.hasRecurrenceRules ? CalendarSource.macRecurrence(r.recurrenceRules ?? []) : nil,
            recurrenceEnd: recurrenceEnd)
    }
}

/// What the user chose for a Palm: which Reminders lists go on it, each
/// its own category. Stored with the device profile.
public struct TaskSyncSettings: Codable, Equatable, Sendable {
    public struct Choice: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var title: String
        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    public var enabled: Bool
    public var lists: [Choice]
    public var keepCompletedDays: Int
    /// nil (profiles from before the setting): the Mac wins
    public var conflictPolicy: ConflictPolicy?

    public init(enabled: Bool = false, lists: [Choice] = [], keepCompletedDays: Int = 30, conflictPolicy: ConflictPolicy? = nil) {
        self.enabled = enabled
        self.lists = lists
        self.keepCompletedDays = keepCompletedDays
        self.conflictPolicy = conflictPolicy
    }

    public var conflicts: ConflictPolicy { conflictPolicy ?? .macWins }
}

/// One run of the one-way tasks sync, checked by reading it back.
public struct TaskSyncRun {
    public let reminders: Int
    public let database: PalmDatabase
    public let report: TasksBuilder.Report

    public enum Failure: Error {
        case noAccess
        case doesNotReadBack
    }

    public init(settings: TaskSyncSettings, source: ReminderSource, homeZone: TimeZone = .current, now: Date = Date(),
                dateShift: Int = 0) async throws {
        guard source.hasAccess else { throw Failure.noAccess }
        let found = try await source.reminders(in: settings.lists.map(\.id), homeZone: homeZone)
        reminders = found.count
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = homeZone
        let today = PalmDate(now, in: calendar)
        let builder = TasksBuilder(options: .init(lists: settings.lists.map { .init(id: $0.id, title: $0.title) },
                                                  keepCompletedDays: settings.keepCompletedDays, today: today,
                                                  startOfWeek: Foundation.Calendar.current.firstWeekday == 2 ? 1 : 0,
                                                  dateShift: dateShift))
        (database, report) = builder.build(found)

        let image = database.encode()
        guard let check = try? PalmDatabase(data: image), check == database,
              check.records.allSatisfy({ (try? PalmTask(data: $0.data))?.encode() == $0.data }),
              let appInfo = check.appInfo, (try? TaskAppInfo(data: appInfo)) != nil else {
            throw Failure.doesNotReadBack
        }
    }

    @discardableResult
    public func write(to url: URL) throws -> Int {
        let image = database.encode()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try image.write(to: url, options: .atomic)
        return image.count
    }
}
