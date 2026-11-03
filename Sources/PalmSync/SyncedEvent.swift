import Foundation

/// The part of a calendar event both sides can hold: what the sync compares,
/// merges field by field, and keeps in the mirror as the last agreed state.
/// Palm-only data (blobs) and Mac-only data (attendees, URLs, anything the
/// Palm has no field for) stay on their side and are never part of a merge.
public struct SyncedEvent: Equatable, Hashable, Codable, Sendable {
    public var date: PalmDate
    public var time: CalendarEvent.TimeSpan?
    public var title: String?
    public var note: String?
    public var location: String?
    public var alarm: CalendarEvent.Alarm?
    public var repeatRule: CalendarEvent.Repeat?
    public var exceptions: [PalmDate]
    /// The Palm category name, which is also the Mac calendar's mapping.
    public var category: String

    public enum Field: String, CaseIterable, Codable, Sendable {
        case date, time, title, note, location, alarm, repeatRule, exceptions, category
    }

    public init(date: PalmDate, time: CalendarEvent.TimeSpan? = nil, title: String? = nil, note: String? = nil,
                location: String? = nil, alarm: CalendarEvent.Alarm? = nil, repeatRule: CalendarEvent.Repeat? = nil,
                exceptions: [PalmDate] = [], category: String) {
        self.date = date
        self.time = time
        self.title = title
        self.note = note
        self.location = location
        self.alarm = alarm
        self.repeatRule = repeatRule
        self.exceptions = exceptions
        self.category = category
    }

    public init(_ record: CalendarEvent, category: String) {
        self.init(date: record.date, time: record.time, title: record.title, note: record.note,
                  location: record.location, alarm: record.alarm, repeatRule: record.repeatRule,
                  exceptions: record.exceptions, category: category)
    }

    /// Writes the shared fields into a Palm record, keeping what the record
    /// has besides them (its blobs).
    public func apply(to record: inout CalendarEvent) {
        record.date = date
        record.time = time
        record.title = title
        record.note = note
        record.location = location
        record.alarm = alarm
        record.repeatRule = repeatRule
        record.exceptions = exceptions
    }

    public func value(of field: Field) -> AnyHashable {
        switch field {
        case .date: return date
        case .time: return time
        case .title: return title
        case .note: return note
        case .location: return location
        case .alarm: return alarm
        case .repeatRule: return repeatRule
        case .exceptions: return exceptions
        case .category: return category
        }
    }

    public mutating func set(_ field: Field, from other: SyncedEvent) {
        switch field {
        case .date: date = other.date
        case .time: time = other.time
        case .title: title = other.title
        case .note: note = other.note
        case .location: location = other.location
        case .alarm: alarm = other.alarm
        case .repeatRule: repeatRule = other.repeatRule
        case .exceptions: exceptions = other.exceptions
        case .category: category = other.category
        }
    }

    public func differs(from other: SyncedEvent, in field: Field) -> Bool {
        value(of: field) != other.value(of: field)
    }

    /// Readable value of a field for the conflict log.
    public func describe(_ field: Field) -> String {
        switch field {
        case .date: return String(format: "%d-%02d-%02d", date.year, date.month, date.day)
        case .time:
            guard let time else { return "all day" }
            return String(format: "%02d:%02d-%02d:%02d", time.start.hour, time.start.minute, time.end.hour, time.end.minute)
        case .title: return title ?? ""
        case .note: return note ?? ""
        case .location: return location ?? ""
        case .alarm:
            guard let alarm else { return "none" }
            return "\(alarm.advance) \(alarm.unit) before"
        case .repeatRule:
            guard let rule = repeatRule else { return "none" }
            return "\(rule.type) every \(rule.frequency)" + (rule.endDate.map { String(format: " until %d-%02d-%02d", $0.year, $0.month, $0.day) } ?? "")
        case .exceptions: return exceptions.map { String(format: "%d-%02d-%02d", $0.year, $0.month, $0.day) }.joined(separator: " ")
        case .category: return category
        }
    }
}
