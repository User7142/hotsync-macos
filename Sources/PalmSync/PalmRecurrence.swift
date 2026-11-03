import Foundation

/// Calendar arithmetic on PalmDates, proleptic Gregorian, no time zone.
extension PalmDate {
    public static let gregorian: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    var foundationDate: Date {
        Self.gregorian.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public init(_ date: Date, in calendar: Calendar = PalmDate.gregorian) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// 0 = Sunday … 6 = Saturday
    public var weekday: Int {
        Self.gregorian.component(.weekday, from: foundationDate) - 1
    }

    public var daysInMonth: Int {
        Self.gregorian.range(of: .day, in: .month, for: foundationDate)!.count
    }

    public func adding(days: Int) -> PalmDate {
        PalmDate(Self.gregorian.date(byAdding: .day, value: days, to: foundationDate)!)
    }

    public func adding(months: Int) -> PalmDate {
        PalmDate(Self.gregorian.date(byAdding: .month, value: months, to: foundationDate)!)
    }

    public func days(since other: PalmDate) -> Int {
        Self.gregorian.dateComponents([.day], from: other.foundationDate, to: foundationDate).day!
    }

    /// The first day of this date's week, with `weekStart` 0 = Sunday, 1 = Monday.
    func startOfWeek(weekStart: Int) -> PalmDate {
        adding(days: -((weekday - weekStart + 7) % 7))
    }
}

/// The dates on which a Palm Calendar repeat rule fires, for the window
/// bookkeeping of a one-way sync (which generated dates have no occurrence
/// on the Mac, so they become exceptions) and for a two-way sync later.
///
/// The rules follow the Datebook: a monthly-by-date rule on the 31st fires
/// on the last day of shorter months, likewise Feb 29 for a yearly rule.
/// (To be confirmed against the T|X in Phase 0.)
public enum PalmRecurrence {
    public static func occurrences(of rule: CalendarEvent.Repeat, startingOn start: PalmDate,
                                   through windowEnd: PalmDate, limit: Int = 10_000) -> [PalmDate] {
        let end = rule.endDate.map { min($0, windowEnd) } ?? windowEnd
        guard start <= end, rule.frequency > 0 else { return [] }
        let step = Int(rule.frequency)
        var dates: [PalmDate] = []

        switch rule.type {
        case .daily:
            var d = start
            while d <= end, dates.count < limit {
                dates.append(d)
                d = d.adding(days: step)
            }

        case .weekly:
            let weekStart = Int(rule.weekStart & 1)
            let mask = rule.weekdays.isEmpty ? CalendarEvent.Weekdays(rawValue: 1 << UInt8(start.weekday)) : rule.weekdays
            let firstWeek = start.startOfWeek(weekStart: weekStart)
            var d = start
            while d <= end, dates.count < limit {
                let weeks = d.startOfWeek(weekStart: weekStart).days(since: firstWeek) / 7
                if weeks % step == 0, mask.contains(CalendarEvent.Weekdays(rawValue: 1 << UInt8(d.weekday))) {
                    dates.append(d)
                }
                d = d.adding(days: 1)
            }

        case .monthlyByDate:
            var month = PalmDate(year: start.year, month: start.month, day: 1)
            while dates.count < limit {
                let d = PalmDate(year: month.year, month: month.month, day: min(start.day, month.daysInMonth))
                if d > end { break }
                if d >= start { dates.append(d) }
                month = month.adding(months: step)
            }

        case .monthlyByDay:
            let week = Int(rule.on) / 7
            let weekday = Int(rule.on) % 7
            var month = PalmDate(year: start.year, month: start.month, day: 1)
            while dates.count < limit {
                let d = nthWeekday(week: week, weekday: weekday, in: month)
                if d > end { break }
                if d >= start { dates.append(d) }
                month = month.adding(months: step)
            }

        case .yearly:
            var year = start.year
            while dates.count < limit {
                let first = PalmDate(year: year, month: start.month, day: 1)
                let d = PalmDate(year: year, month: start.month, day: min(start.day, first.daysInMonth))
                if d > end { break }
                if d >= start { dates.append(d) }
                year += step
            }
        }
        return dates
    }

    /// The `week`-th (0-3, 4 = last) `weekday` (0 = Sunday) of the month.
    static func nthWeekday(week: Int, weekday: Int, in month: PalmDate) -> PalmDate {
        let first = PalmDate(year: month.year, month: month.month, day: 1)
        if week >= 4 {
            let last = PalmDate(year: month.year, month: month.month, day: first.daysInMonth)
            return last.adding(days: -((last.weekday - weekday + 7) % 7))
        }
        return first.adding(days: (weekday - first.weekday + 7) % 7 + week * 7)
    }
}
