import Foundation

/// The part of a task both sides can hold: title, note, due date, when it
/// was completed, the Palm's priority (1-5), the alarm, the repeat rule and
/// the category. The Palm's unknown header bytes stay in the record.
public struct SyncedTask: Equatable, Hashable, Codable, Sendable {
    public struct Alarm: Equatable, Hashable, Codable, Sendable {
        public var time: PalmTime
        public var daysEarlier: UInt16
        public init(time: PalmTime, daysEarlier: UInt16 = 0) {
            self.time = time
            self.daysEarlier = daysEarlier
        }
    }

    public struct Repeat: Equatable, Hashable, Codable, Sendable {
        public var start: PalmDate
        public var rule: CalendarEvent.Repeat
        public init(start: PalmDate, rule: CalendarEvent.Repeat) {
            self.start = start
            self.rule = rule
        }
    }

    public var title: String?
    public var note: String?
    public var dueDate: PalmDate?
    public var completedDate: PalmDate?
    public var priority: UInt8
    public var alarm: Alarm?
    public var repeatRule: Repeat?
    public var category: String

    public enum Field: String, CaseIterable, Codable, Sendable {
        case title, note, dueDate, completedDate, priority, alarm, repeatRule, category
    }

    public init(title: String? = nil, note: String? = nil, dueDate: PalmDate? = nil, completedDate: PalmDate? = nil,
                priority: UInt8 = 1, alarm: Alarm? = nil, repeatRule: Repeat? = nil, category: String) {
        self.title = title
        self.note = note
        self.dueDate = dueDate
        self.completedDate = completedDate
        self.priority = priority
        self.alarm = alarm
        self.repeatRule = repeatRule
        self.category = category
    }

    public init(_ record: PalmTask, category: String) {
        title = record.title
        note = record.note.isEmpty ? nil : record.note
        dueDate = record.dueDate
        completedDate = record.completedDate
        priority = record.priority
        alarm = record.alarm.map { Alarm(time: $0.time, daysEarlier: $0.daysEarlier) }
        repeatRule = record.repeatRule.map { Repeat(start: $0.start, rule: $0.rule) }
        self.category = category
    }

    public var isCompleted: Bool { completedDate != nil }
}

extension SyncedTask: SyncedItem {
    public typealias PalmRecord = PalmTask

    public static func palmRecord(from data: Data) throws -> PalmTask { try PalmTask(data: data) }
    public static func encode(_ record: PalmTask) -> Data { record.encode() }
    public func newPalmRecord() -> PalmTask { PalmTask(title: title ?? "") }

    public func apply(to record: inout PalmTask) {
        record.title = title ?? ""
        record.note = note ?? ""
        record.dueDate = dueDate
        record.completedDate = completedDate
        record.priority = priority
        record.alarm = alarm.map { PalmTask.Alarm(time: $0.time, daysEarlier: $0.daysEarlier) }
        record.repeatRule = repeatRule.map { ($0.start, $0.rule) }
    }

    public func value(of field: Field) -> AnyHashable {
        switch field {
        case .title: return title
        case .note: return note
        case .dueDate: return dueDate
        case .completedDate: return completedDate
        case .priority: return priority
        case .alarm: return alarm
        case .repeatRule: return repeatRule
        case .category: return category
        }
    }

    public mutating func set(_ field: Field, from other: SyncedTask) {
        switch field {
        case .title: title = other.title
        case .note: note = other.note
        case .dueDate: dueDate = other.dueDate
        case .completedDate: completedDate = other.completedDate
        case .priority: priority = other.priority
        case .alarm: alarm = other.alarm
        case .repeatRule: repeatRule = other.repeatRule
        case .category: category = other.category
        }
    }

    public func differs(from other: SyncedTask, in field: Field) -> Bool {
        value(of: field) != other.value(of: field)
    }

    public func describe(_ field: Field) -> String {
        func day(_ d: PalmDate?) -> String { d.map { String(format: "%d-%02d-%02d", $0.year, $0.month, $0.day) } ?? "none" }
        switch field {
        case .title: return title ?? ""
        case .note: return note ?? ""
        case .dueDate: return day(dueDate)
        case .completedDate: return completedDate == nil ? "open" : "done " + day(completedDate)
        case .priority: return String(priority)
        case .alarm:
            guard let alarm else { return "none" }
            return String(format: "%02d:%02d, %d days earlier", alarm.time.hour, alarm.time.minute, alarm.daysEarlier)
        case .repeatRule:
            guard let r = repeatRule else { return "none" }
            return "\(r.rule.type) every \(r.rule.frequency) from \(day(r.start))"
        case .category: return category
        }
    }

    public func shiftingDates(by years: Int) -> SyncedTask {
        guard years != 0 else { return self }
        var s = self
        s.dueDate = dueDate.map { DateFix.shift($0, years: years) }
        s.completedDate = completedDate.map { DateFix.shift($0, years: years) }
        if let r = repeatRule {
            s.repeatRule = Repeat(start: DateFix.shift(r.start, years: years),
                                  rule: { var x = r.rule; x.endDate = x.endDate.map { DateFix.shift($0, years: years) }; return x }())
        }
        return s
    }

    /// Slow sync: the same title and due date.
    public func matches(_ other: SyncedTask) -> Bool {
        title == other.title && dueDate == other.dueDate
    }
}

public typealias TaskSyncPlan = SyncPlan<SyncedTask>
public typealias TaskMirror = SyncMirror<SyncedTask>

extension TasksBuilder {
    /// The Mac's reminders as the sync engine takes them: each list a
    /// category, each keyed by its Reminders identifier. Completed ones
    /// older than the option are left out, as in the one-way build; the
    /// engine's window rule drops them from the Palm.
    public func syncItems(_ reminders: [MacReminder]) -> [MacSyncItem<SyncedTask>] {
        var report = Report()
        let categoryOf = Dictionary(options.lists.map { ($0.id, String($0.title.prefix(CategoryAppInfo.nameWidth - 1))) },
                                    uniquingKeysWith: { a, _ in a })
        let cutoff = options.today.adding(days: -options.keepCompletedDays)
        return reminders.compactMap { reminder in
            if let done = reminder.completionDate, done < cutoff { return nil }
            let record = convert(reminder, &report)
            return MacSyncItem(key: MacKey(seriesID: reminder.id), item: SyncedTask(record, category: categoryOf[reminder.listID] ?? "Unfiled"),
                               palmRecord: record.encode())
        }
    }

    /// Still worth keeping on the Palm: open, or completed recently.
    public func inWindow(_ task: SyncedTask) -> Bool {
        guard let done = task.completedDate else { return true }
        return done >= options.today.adding(days: -options.keepCompletedDays)
    }
}

extension SyncPlan where Item == SyncedTask {
    /// The Palm's side of the plan as a whole TasksDB-PTod to install, due
    /// ones first by date then priority. The Palm's own AppInfo bytes are
    /// kept; only the categories change.
    public func palmDatabase(appInfo existing: TaskAppInfo)
        -> (database: PalmDatabase, palmIDs: [Int: UInt32], categories: CategoryAppInfo) {
        let (records, palmIDs, categories, nextID) = palmRecords(categories: existing.categories) { a, b in
            switch (a.dueDate, b.dueDate) {
            case let (x?, y?) where x != y: return x < y
            case (nil, .some): return false
            case (.some, nil): return true
            default: return a.priority < b.priority
            }
        }
        var appInfo = existing
        appInfo.categories = categories
        var db = PalmDatabase(name: TasksBuilder.databaseName, type: "DATA", creator: "PTod", attributes: 0, version: 1,
                              appInfo: appInfo.encode())
        db.records = records
        db.uniqueIDSeed = nextID
        return (db, palmIDs, categories)
    }
}

extension TasksBuilder {
    /// One reminder as a Palm record, nothing reported.
    public func palmTask(_ reminder: MacReminder) -> PalmTask {
        var report = Report()
        return convert(reminder, &report)
    }
}
