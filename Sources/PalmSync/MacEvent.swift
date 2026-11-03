import Foundation

/// A calendar event as the Mac has it, without EventKit: the adapter in the
/// app fills these from EKEvent, the builder turns them into Palm records,
/// and the tests make them up. One value per occurrence that EventKit
/// returns for the window; occurrences of a series share `seriesID` and
/// carry the series' rule.
public struct MacEvent: Equatable, Sendable {
    /// Stable across accounts for the same meeting (the iCalendar UID):
    /// used to keep one copy of an invite that lands in iCloud and Google.
    public var externalID: String?
    /// Same for every occurrence of a series (EventKit's calendarItemIdentifier).
    public var seriesID: String
    public var calendarID: String
    public var title: String
    public var notes: String?
    public var location: String?
    public var url: URL?
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// Seconds relative to the start; negative means before. The earliest
    /// alarm, if there are several.
    public var alarmOffset: TimeInterval?
    public var recurrence: MacRecurrence?
    /// For an occurrence of a series: the date the rule put it on, even
    /// when it was moved (EventKit's occurrenceDate).
    public var occurrenceDate: Date?
    /// This occurrence was edited on its own (EventKit's isDetached).
    public var isDetached: Bool

    public init(externalID: String? = nil, seriesID: String, calendarID: String, title: String,
                notes: String? = nil, location: String? = nil, url: URL? = nil,
                start: Date, end: Date, isAllDay: Bool = false, alarmOffset: TimeInterval? = nil,
                recurrence: MacRecurrence? = nil, occurrenceDate: Date? = nil, isDetached: Bool = false) {
        self.externalID = externalID
        self.seriesID = seriesID
        self.calendarID = calendarID
        self.title = title
        self.notes = notes
        self.location = location
        self.url = url
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.alarmOffset = alarmOffset
        self.recurrence = recurrence
        self.occurrenceDate = occurrenceDate
        self.isDetached = isDetached
    }
}

/// An EKRecurrenceRule without EventKit. Weekdays are 1 = Sunday … 7 =
/// Saturday as in EventKit; weekNumber 0 means any week, -1 the last.
public struct MacRecurrence: Equatable, Sendable {
    public enum Frequency: Sendable { case daily, weekly, monthly, yearly }
    public enum End: Equatable, Sendable {
        case date(Date)
        case count(Int)
    }
    public struct DayOfWeek: Equatable, Sendable {
        public var weekday: Int
        public var weekNumber: Int
        public init(_ weekday: Int, weekNumber: Int = 0) {
            self.weekday = weekday
            self.weekNumber = weekNumber
        }
    }

    public var frequency: Frequency
    public var interval: Int
    public var daysOfTheWeek: [DayOfWeek]
    public var daysOfTheMonth: [Int]
    public var monthsOfTheYear: [Int]
    public var setPositions: [Int]
    public var end: End?
    /// 0 = not set, 1 = Sunday, 2 = Monday (EventKit's numbering)
    public var firstDayOfTheWeek: Int

    public init(frequency: Frequency, interval: Int = 1, daysOfTheWeek: [DayOfWeek] = [],
                daysOfTheMonth: [Int] = [], monthsOfTheYear: [Int] = [], setPositions: [Int] = [],
                end: End? = nil, firstDayOfTheWeek: Int = 0) {
        self.frequency = frequency
        self.interval = interval
        self.daysOfTheWeek = daysOfTheWeek
        self.daysOfTheMonth = daysOfTheMonth
        self.monthsOfTheYear = monthsOfTheYear
        self.setPositions = setPositions
        self.end = end
        self.firstDayOfTheWeek = firstDayOfTheWeek
    }
}
