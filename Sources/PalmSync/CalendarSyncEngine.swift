import Foundation

extension SyncedEvent: SyncedItem {
    public typealias PalmRecord = CalendarEvent

    public static func palmRecord(from data: Data) throws -> CalendarEvent { try CalendarEvent(data: data) }
    public static func encode(_ record: CalendarEvent) -> Data { record.encode() }
    public func newPalmRecord() -> CalendarEvent { CalendarEvent(date: date) }

    /// Slow sync: the same day, time and title.
    public func matches(_ other: SyncedEvent) -> Bool {
        date == other.date && time == other.time && title == other.title
    }

    public func shiftingDates(by years: Int) -> SyncedEvent {
        guard years != 0 else { return self }
        var s = self
        s.date = DateFix.shift(date, years: years)
        if let end = s.repeatRule?.endDate { s.repeatRule?.endDate = DateFix.shift(end, years: years) }
        s.exceptions = exceptions.map { DateFix.shift($0, years: years) }
        return s
    }
}

public typealias CalendarSyncPlan = SyncPlan<SyncedEvent>
public typealias CalendarMirror = SyncMirror<SyncedEvent>

/// The calendar's three-way merge: `SyncEngine` with the window the Mac was
/// asked for, so an event that left it is dropped from the Palm and the
/// mirror rather than taken for deleted on the Mac. The Mac's items come
/// from CalendarBuilder, with the occurrences it owns.
public struct CalendarSyncEngine {
    public var windowStart: PalmDate
    public var windowEnd: PalmDate
    public var conflictPolicy: ConflictPolicy
    public var palmDeletesTrusted: Bool
    /// With `.ask`: the answer per conflict (see `SyncEngine.resolve`).
    public var resolve: (@Sendable (Int, SyncConflict) -> ConflictPolicy)?

    public init(windowStart: PalmDate, windowEnd: PalmDate, conflictPolicy: ConflictPolicy = .macWins, palmDeletesTrusted: Bool = true) {
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.conflictPolicy = conflictPolicy
        self.palmDeletesTrusted = palmDeletesTrusted
    }

    public func plan(palm snapshot: PalmSnapshot, palmCategories: [String], mac items: [CalendarBuilder.MacItem],
                     mirror: CalendarMirror) throws -> CalendarSyncPlan {
        let (start, end) = (windowStart, windowEnd)
        var engine = SyncEngine<SyncedEvent>(conflictPolicy: conflictPolicy, palmDeletesTrusted: palmDeletesTrusted) { $0.date >= start && $0.date <= end }
        engine.resolve = resolve
        let mac = items.map {
            MacSyncItem(key: $0.key, item: SyncedEvent($0.event, category: $0.category), macOwned: $0.macOwned,
                        palmRecord: $0.event.encode())
        }
        return try engine.plan(palm: snapshot, palmCategories: palmCategories, mac: mac, mirror: mirror)
    }
}
