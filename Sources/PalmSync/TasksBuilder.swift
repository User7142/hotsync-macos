import Foundation

/// A reminder as the Mac has it, without EventKit.
public struct MacReminder: Equatable, Sendable {
    public var id: String
    public var listID: String
    public var title: String
    public var notes: String?
    public var url: URL?
    /// The due day, when the reminder has one.
    public var dueDate: PalmDate?
    /// The due time of day, when the reminder has one.
    public var dueTime: PalmTime?
    /// EventKit's 0 (none), 1-4 high, 5 medium, 6-9 low.
    public var priority: Int
    public var completionDate: PalmDate?
    /// The first alarm, as the day and time it fires.
    public var alarmDate: PalmDate?
    public var alarmTime: PalmTime?
    public var recurrence: MacRecurrence?
    public var recurrenceEnd: PalmDate?

    public init(id: String, listID: String, title: String, notes: String? = nil, url: URL? = nil,
                dueDate: PalmDate? = nil, dueTime: PalmTime? = nil, priority: Int = 0, completionDate: PalmDate? = nil,
                alarmDate: PalmDate? = nil, alarmTime: PalmTime? = nil, recurrence: MacRecurrence? = nil,
                recurrenceEnd: PalmDate? = nil) {
        self.id = id
        self.listID = listID
        self.title = title
        self.notes = notes
        self.url = url
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.priority = priority
        self.completionDate = completionDate
        self.alarmDate = alarmDate
        self.alarmTime = alarmTime
        self.recurrence = recurrence
        self.recurrenceEnd = recurrenceEnd
    }
}

/// Builds a complete TasksDB-PTod from the Mac's reminders: the one-way
/// sync where the database is installed whole.
///
/// - Each Reminders list is a Palm category; past 15 they fold into "Other".
/// - Priority: none and 1-4 become 1 (the Palm's default), 5 becomes 3,
///   6-9 become 5; 2-4 and 6-8 the steps between.
/// - A reminder's alarm becomes the Palm's "N days earlier at HH:MM";
///   without an alarm, a due time becomes an alarm at that time.
/// - Rules the Palm can express are kept; others go on as single tasks.
/// - Completed reminders older than `keepCompletedDays` stay on the Mac.
public struct TasksBuilder {
    public struct MacList: Equatable, Sendable {
        public var id: String
        public var title: String
        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    public struct Options: Sendable {
        public var lists: [MacList]
        public var keepCompletedDays: Int
        public var today: PalmDate
        public var startOfWeek: UInt8
        /// DateFix on the Palm: years taken away from every date on encoding.
        public var dateShift: Int

        public init(lists: [MacList], keepCompletedDays: Int = 30, today: PalmDate, startOfWeek: UInt8 = 0, dateShift: Int = 0) {
            self.lists = lists
            self.keepCompletedDays = keepCompletedDays
            self.today = today
            self.startOfWeek = startOfWeek
            self.dateShift = dateShift
        }
    }

    public struct Report: Equatable, Sendable {
        public var records = 0
        public var completedSkipped = 0
        public var rulesDropped = 0
        public var categories: [String] = []
        public var warnings: [String] = []
    }

    public static let databaseName = "TasksDB-PTod"
    public static let maxCategories = 16
    public static let overflowCategory = "Other"

    public let options: Options

    public init(options: Options) {
        self.options = options
    }

    public static func palmPriority(_ priority: Int) -> UInt8 {
        switch priority {
        case ...1: return 1
        case 2...4: return 2
        case 5: return 3
        case 6...8: return 4
        default: return 5
        }
    }

    public func build(_ reminders: [MacReminder]) -> (database: PalmDatabase, report: Report) {
        var report = Report()

        var names = ["Unfiled"]
        var categoryOf: [String: Int] = [:]
        var overflow = false
        for list in options.lists {
            let name = String(list.title.prefix(CategoryAppInfo.nameWidth - 1))
            if let i = names.firstIndex(of: name) {
                categoryOf[list.id] = i
            } else if names.count < Self.maxCategories - 1 {
                names.append(name)
                categoryOf[list.id] = names.count - 1
            } else {
                if !overflow {
                    names.append(Self.overflowCategory)
                    overflow = true
                    report.warnings.append("more than \(Self.maxCategories - 2) lists: the rest go into \"\(Self.overflowCategory)\"")
                }
                categoryOf[list.id] = names.firstIndex(of: Self.overflowCategory)!
            }
        }

        let cutoff = options.today.adding(days: -options.keepCompletedDays)
        var tasks: [(PalmTask, Int)] = []
        for reminder in reminders {
            if let done = reminder.completionDate, done < cutoff {
                report.completedSkipped += 1
                continue
            }
            tasks.append((convert(reminder, &report), categoryOf[reminder.listID] ?? 0))
        }
        // due ones first, by date, then by priority; the Palm sorts on its own as well
        tasks.sort { a, b in
            switch (a.0.dueDate, b.0.dueDate) {
            case let (x?, y?) where x != y: return x < y
            case (nil, .some): return false
            case (.some, nil): return true
            default: return a.0.priority < b.0.priority
            }
        }

        var db = PalmDatabase(name: Self.databaseName, type: "DATA", creator: "PTod", attributes: 0, version: 1,
                              appInfo: TaskAppInfo(categories: CategoryAppInfo(names: names)).encode())
        db.records = tasks.enumerated().map { i, t in
            PalmDatabase.Record(category: t.1, uniqueID: UInt32(i + 1), data: DateFix.shift(t.0, years: -options.dateShift).encode())
        }
        db.uniqueIDSeed = UInt32(tasks.count + 1)
        report.records = tasks.count
        report.categories = names
        return (db, report)
    }

    func convert(_ reminder: MacReminder, _ report: inout Report) -> PalmTask {
        let title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var note = reminder.notes ?? ""
        if let url = reminder.url { note += note.isEmpty ? url.absoluteString : "\n\(url.absoluteString)" }
        var task = PalmTask(title: title.isEmpty ? "(untitled)" : title, note: note,
                            priority: Self.palmPriority(reminder.priority), dueDate: reminder.dueDate,
                            completedDate: reminder.completionDate)

        if let due = reminder.dueDate {
            if let alarmDate = reminder.alarmDate, let alarmTime = reminder.alarmTime, alarmDate <= due {
                task.alarm = .init(time: alarmTime, daysEarlier: UInt16(clamping: due.days(since: alarmDate)))
            } else if let time = reminder.dueTime {
                task.alarm = .init(time: time, daysEarlier: 0)
            }
            if let rule = reminder.recurrence {
                if let palmRule = CalendarBuilder.palmRule(rule, startDate: due, endDate: reminder.recurrenceEnd,
                                                           defaultWeekStart: options.startOfWeek) {
                    task.repeatRule = (due, palmRule)
                } else {
                    report.rulesDropped += 1
                }
            }
        }
        return task
    }
}
