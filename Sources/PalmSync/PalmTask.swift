import Foundation

/// A record of the Palm OS 5 Tasks application (database TasksDB-PTod,
/// creator PTod), the Garnet successor of the To Do list. No reference
/// implementation exists; this layout was read off a T|X (Palm OS 5.4.9)
/// in October 2026 and holds for every record seen so far.
///
/// Layout (big-endian):
///
///      0  flags            0x80 due date, 0x40 completed, 0x20 alarm,
///                          0x10 repeat, 0x08 always set, 0x04 note not empty
///      1  unknown[2]       0 so far
///      3  completed        1 when completed
///      4  unknown          0 so far
///      5  priority         1-5
///      6  dueDate          PalmDate                          if 0x80
///         completedDate    PalmDate                          if 0x40
///         alarm            hour[1] minute[1] daysEarlier[2]  if 0x20
///         repeatStart      PalmDate                          if 0x10
///         repeat           type[1] pad[1] endDate[2] frequency[1] on[1]
///                          weekStart[1] pad[1] — as the Calendar's
///         description      NUL-terminated
///         note             NUL-terminated, present even when empty
///
/// The order of the optional fields follows the flag bits from high to low;
/// due + completed, due + alarm and due + repeat have been seen on a device,
/// the other combinations follow the same rule.
public struct PalmTask: Equatable, Sendable {
    public struct Alarm: Equatable, Sendable {
        public var time: PalmTime
        /// Days before the due date; 0 = on the day.
        public var daysEarlier: UInt16
        public init(time: PalmTime, daysEarlier: UInt16 = 0) {
            self.time = time
            self.daysEarlier = daysEarlier
        }
    }

    public var dueDate: PalmDate?
    /// nil: not completed
    public var completedDate: PalmDate?
    public var alarm: Alarm?
    public var priority: UInt8
    public var repeatRule: (start: PalmDate, rule: CalendarEvent.Repeat)?
    public var title: String
    public var note: String
    /// Bytes 1, 2 and 4 of the header, kept as they are.
    public var unknown: (UInt8, UInt8, UInt8)
    /// The flag byte as read, for the bits this codec does not name.
    public var otherFlags: UInt8

    static let dueFlag: UInt8 = 0x80
    static let completedFlag: UInt8 = 0x40
    static let alarmFlag: UInt8 = 0x20
    static let repeatFlag: UInt8 = 0x10
    static let descriptionFlag: UInt8 = 0x08
    static let noteFlag: UInt8 = 0x04
    static let knownFlags: UInt8 = 0xFC

    public init(title: String, note: String = "", priority: UInt8 = 1, dueDate: PalmDate? = nil,
                completedDate: PalmDate? = nil, alarm: Alarm? = nil,
                repeatRule: (start: PalmDate, rule: CalendarEvent.Repeat)? = nil) {
        self.title = title
        self.note = note
        self.priority = priority
        self.dueDate = dueDate
        self.completedDate = completedDate
        self.alarm = alarm
        self.repeatRule = repeatRule
        unknown = (0, 0, 0)
        otherFlags = 0
    }

    public static func == (a: PalmTask, b: PalmTask) -> Bool {
        a.encode() == b.encode()
    }

    public var isCompleted: Bool { completedDate != nil }

    public init(data: Data) throws {
        var r = ByteReader(data)
        let flags = try r.u8()
        let u1 = try r.u8()
        let u2 = try r.u8()
        let completed = try r.u8()
        let u4 = try r.u8()
        priority = try r.u8()
        unknown = (u1, u2, u4)
        otherFlags = flags & ~Self.knownFlags

        dueDate = flags & Self.dueFlag != 0 ? PalmDate(packed: try r.u16()) : nil
        if flags & Self.completedFlag != 0 {
            completedDate = PalmDate(packed: try r.u16())
        } else {
            completedDate = nil
        }
        guard (completed != 0) == (completedDate != nil) else {
            throw PalmFormatError.invalidValue(field: "task.completed", value: Int(completed))
        }
        if flags & Self.alarmFlag != 0 {
            let hour = try r.u8()
            let minute = try r.u8()
            let days = try r.u16()
            guard hour < 24, minute < 60 else { throw PalmFormatError.invalidValue(field: "task.alarm", value: Int(hour) * 100 + Int(minute)) }
            alarm = Alarm(time: PalmTime(hour: Int(hour), minute: Int(minute)), daysEarlier: days)
        } else {
            alarm = nil
        }
        if flags & Self.repeatFlag != 0 {
            let start = PalmDate(packed: try r.u16())
            let typeByte = try r.u8()
            guard let type = CalendarEvent.RepeatType(rawValue: typeByte) else {
                throw PalmFormatError.invalidValue(field: "task.repeat.type", value: Int(typeByte))
            }
            _ = try r.u8()
            let end = try r.u16()
            let frequency = try r.u8()
            let on = try r.u8()
            let weekStart = try r.u8()
            _ = try r.u8()
            repeatRule = (start, CalendarEvent.Repeat(type: type, endDate: end == PalmDate.none ? nil : PalmDate(packed: end),
                                                       frequency: frequency, on: on, weekStart: weekStart))
        } else {
            repeatRule = nil
        }
        title = try r.cString()
        note = try r.cString()
        guard r.isAtEnd else { throw PalmFormatError.trailingBytes(count: r.remaining) }
    }

    public func encode() -> Data {
        var w = ByteWriter()
        var flags = Self.descriptionFlag | otherFlags
        if dueDate != nil { flags |= Self.dueFlag }
        if completedDate != nil { flags |= Self.completedFlag }
        if alarm != nil { flags |= Self.alarmFlag }
        if repeatRule != nil { flags |= Self.repeatFlag }
        if !note.isEmpty { flags |= Self.noteFlag }
        w.u8(flags)
        w.u8(unknown.0)
        w.u8(unknown.1)
        w.u8(completedDate != nil ? 1 : 0)
        w.u8(unknown.2)
        w.u8(priority)
        if let dueDate { w.u16(dueDate.packed) }
        if let completedDate { w.u16(completedDate.packed) }
        if let alarm {
            w.u8(UInt8(clamping: alarm.time.hour))
            w.u8(UInt8(clamping: alarm.time.minute))
            w.u16(alarm.daysEarlier)
        }
        if let (start, rule) = repeatRule {
            w.u16(start.packed)
            w.u8(rule.type.rawValue)
            w.u8(0)
            w.u16(rule.endDate?.packed ?? PalmDate.none)
            w.u8(rule.frequency)
            w.u8(rule.on)
            w.u8(rule.weekStart)
            w.u8(0)
        }
        w.cString(title)
        w.cString(note)
        return w.data
    }
}

/// The AppInfo block of TasksDB-PTod: the category block and 22 bytes the
/// T|X writes as 18 zeros, 0xFFFF, 2 zeros (kept as they are).
public struct TaskAppInfo: Equatable, Sendable {
    public var categories: CategoryAppInfo
    public var internalBytes: Data

    public static let size = CategoryAppInfo.size + 22

    public init(categories: CategoryAppInfo = CategoryAppInfo()) {
        self.categories = categories
        internalBytes = Data(count: 18) + Data([0xFF, 0xFF, 0, 0])
    }

    public init(data: Data) throws {
        var r = ByteReader(data)
        categories = try CategoryAppInfo(bytes: try r.slice(CategoryAppInfo.size))
        internalBytes = Data(r.rest())
    }

    public func encode() -> Data {
        var w = ByteWriter()
        w.append(categories.encode())
        w.append(internalBytes)
        return w.data
    }
}
