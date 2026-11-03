import Foundation

/// A record of the Palm OS 5 Calendar (database CalendarDB-PDat, creator
/// PDat), the Garnet successor of the Datebook. Decoded from and encoded to
/// the record bytes without loss: the order and the presence of every field
/// follow the flags, and blobs the codec does not know are carried through.
///
/// Layout (big-endian):
///
///      0  startHour, startMinute, endHour, endMinute   all 0xFF: no time
///      4  date             PalmDate
///      6  flags            0x40 alarm, 0x20 repeat, 0x10 note,
///                          0x08 exceptions, 0x04 description, 0x02 location
///      7  padding
///      8  alarm            advance[1] unit[1]                  if 0x40
///         repeat           type[1] pad[1] endDate[2] frequency[1]
///                          on[1] weekStart[1] pad[1]           if 0x20
///         exceptions       count[2] date[2]×count             if 0x08
///         description      NUL-terminated                      if 0x04
///         note             NUL-terminated                      if 0x10
///         location         NUL-terminated                      if 0x02
///         blobs            type[4] length[2] data              to the end
public struct CalendarEvent: Equatable, Sendable {
    public struct TimeSpan: Equatable, Hashable, Codable, Sendable {
        public var start: PalmTime
        public var end: PalmTime
        public init(start: PalmTime, end: PalmTime) {
            self.start = start
            self.end = end
        }
    }

    public enum AlarmUnit: UInt8, Codable, Sendable {
        case minutes = 0, hours = 1, days = 2
    }

    public struct Alarm: Equatable, Hashable, Codable, Sendable {
        public var advance: UInt8
        public var unit: AlarmUnit
        public init(advance: UInt8, unit: AlarmUnit) {
            self.advance = advance
            self.unit = unit
        }
    }

    public enum RepeatType: UInt8, Codable, Sendable {
        case daily = 1, weekly = 2, monthlyByDay = 3, monthlyByDate = 4, yearly = 5
    }

    /// Days of the week for a weekly repeat; bit 0 = Sunday.
    public struct Weekdays: OptionSet, Equatable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let sunday = Weekdays(rawValue: 1 << 0)
        public static let monday = Weekdays(rawValue: 1 << 1)
        public static let tuesday = Weekdays(rawValue: 1 << 2)
        public static let wednesday = Weekdays(rawValue: 1 << 3)
        public static let thursday = Weekdays(rawValue: 1 << 4)
        public static let friday = Weekdays(rawValue: 1 << 5)
        public static let saturday = Weekdays(rawValue: 1 << 6)
    }

    public struct Repeat: Equatable, Hashable, Codable, Sendable {
        public var type: RepeatType
        /// nil: repeats forever
        public var endDate: PalmDate?
        /// Every n-th day, week, month or year.
        public var frequency: UInt8
        /// The "on" byte: the day mask for weekly, the n-th weekday for
        /// monthly by day (week * 7 + weekday, week 4 = last), 0 otherwise.
        public var on: UInt8
        /// 0 = Sunday, 1 = Monday
        public var weekStart: UInt8

        public init(type: RepeatType, endDate: PalmDate? = nil, frequency: UInt8 = 1,
                    on: UInt8 = 0, weekStart: UInt8 = 0) {
            self.type = type
            self.endDate = endDate
            self.frequency = frequency
            self.on = on
            self.weekStart = weekStart
        }

        public var weekdays: Weekdays {
            get { type == .weekly ? Weekdays(rawValue: on) : [] }
            set { on = newValue.rawValue }
        }

        /// For monthly by day: (week 0-4 with 4 = last, weekday 0 = Sunday).
        public var nthWeekday: (week: Int, weekday: Int)? {
            type == .monthlyByDay ? (Int(on) / 7, Int(on) % 7) : nil
        }
    }

    /// A trailing type-tagged block; "Bd00" is the time zone.
    public typealias Blob = PalmBlob

    public var date: PalmDate
    /// nil: an event without a time ("timeless")
    public var time: TimeSpan?
    public var alarm: Alarm?
    public var repeatRule: Repeat?
    public var exceptions: [PalmDate]
    /// What the Palm calls the description: the text shown in the day view.
    public var title: String?
    public var note: String?
    public var location: String?
    public var blobs: [Blob]

    static let alarmFlag: UInt8 = 0x40
    static let repeatFlag: UInt8 = 0x20
    static let noteFlag: UInt8 = 0x10
    static let exceptionsFlag: UInt8 = 0x08
    static let descriptionFlag: UInt8 = 0x04
    static let locationFlag: UInt8 = 0x02

    public init(date: PalmDate, time: TimeSpan? = nil, title: String? = nil, note: String? = nil,
                location: String? = nil, alarm: Alarm? = nil, repeatRule: Repeat? = nil,
                exceptions: [PalmDate] = [], blobs: [Blob] = []) {
        self.date = date
        self.time = time
        self.title = title
        self.note = note
        self.location = location
        self.alarm = alarm
        self.repeatRule = repeatRule
        self.exceptions = exceptions
        self.blobs = blobs
    }

    /// The time zone of the event, from its "Bd00" blob; nil means the event
    /// is in the device's local time. Setting it replaces (or removes) that blob.
    public var timezone: PalmTimezone? {
        get {
            guard let blob = blobs.first(where: { $0.type == PalmTimezone.blobType }) else { return nil }
            return try? PalmTimezone(data: blob.data)
        }
        set {
            blobs.removeAll { $0.type == PalmTimezone.blobType }
            if let newValue {
                blobs.insert(Blob(type: PalmTimezone.blobType, data: newValue.encode()), at: 0)
            }
        }
    }

    // MARK: Decoding

    public init(data: Data) throws {
        var r = ByteReader(data)
        let startHour = try r.u8()
        let startMinute = try r.u8()
        let endHour = try r.u8()
        let endMinute = try r.u8()
        date = PalmDate(packed: try r.u16())
        let flags = try r.u8()
        _ = try r.u8()  // padding

        if startHour == 0xFF && startMinute == 0xFF {
            time = nil
        } else {
            time = TimeSpan(start: PalmTime(hour: Int(startHour), minute: Int(startMinute)),
                            end: PalmTime(hour: Int(endHour), minute: Int(endMinute)))
        }

        if flags & Self.alarmFlag != 0 {
            let advance = try r.u8()
            let unitByte = try r.u8()
            guard let unit = AlarmUnit(rawValue: unitByte) else {
                throw PalmFormatError.invalidValue(field: "alarm.unit", value: Int(unitByte))
            }
            alarm = Alarm(advance: advance, unit: unit)
        } else {
            alarm = nil
        }

        if flags & Self.repeatFlag != 0 {
            let typeByte = try r.u8()
            guard let type = RepeatType(rawValue: typeByte) else {
                throw PalmFormatError.invalidValue(field: "repeat.type", value: Int(typeByte))
            }
            _ = try r.u8()  // padding
            let end = try r.u16()
            let frequency = try r.u8()
            let on = try r.u8()
            let weekStart = try r.u8()
            _ = try r.u8()  // padding
            repeatRule = Repeat(type: type, endDate: end == PalmDate.none ? nil : PalmDate(packed: end),
                                frequency: frequency, on: on, weekStart: weekStart)
        } else {
            repeatRule = nil
        }

        if flags & Self.exceptionsFlag != 0 {
            let count = Int(try r.u16())
            exceptions = try (0..<count).map { _ in PalmDate(packed: try r.u16()) }
        } else {
            exceptions = []
        }

        title = flags & Self.descriptionFlag != 0 ? try r.cString() : nil
        note = flags & Self.noteFlag != 0 ? try r.cString() : nil
        location = flags & Self.locationFlag != 0 ? try r.cString() : nil

        blobs = try PalmBlob.readAll(&r)
    }

    // MARK: Encoding

    public func encode() -> Data {
        var w = ByteWriter()
        if let time {
            w.u8(UInt8(clamping: time.start.hour))
            w.u8(UInt8(clamping: time.start.minute))
            w.u8(UInt8(clamping: time.end.hour))
            w.u8(UInt8(clamping: time.end.minute))
        } else {
            w.append([0xFF, 0xFF, 0xFF, 0xFF])
        }
        w.u16(date.packed)
        var flags: UInt8 = 0
        w.u8(0)  // flags, set below
        w.u8(0)  // padding

        if let alarm {
            flags |= Self.alarmFlag
            w.u8(alarm.advance)
            w.u8(alarm.unit.rawValue)
        }
        if let rule = repeatRule {
            flags |= Self.repeatFlag
            w.u8(rule.type.rawValue)
            w.u8(0)
            w.u16(rule.endDate?.packed ?? PalmDate.none)
            w.u8(rule.frequency)
            w.u8(rule.on)
            w.u8(rule.weekStart)
            w.u8(0)
        }
        if !exceptions.isEmpty {
            flags |= Self.exceptionsFlag
            w.u16(UInt16(exceptions.count))
            for e in exceptions { w.u16(e.packed) }
        }
        if let title {
            flags |= Self.descriptionFlag
            w.cString(title)
        }
        if let note {
            flags |= Self.noteFlag
            w.cString(note)
        }
        if let location {
            flags |= Self.locationFlag
            w.cString(location)
        }
        for blob in blobs { blob.write(&w) }
        w.set(flags, at: 6)
        return w.data
    }
}

/// The AppInfo block of CalendarDB-PDat: the category block, the first day
/// of the week, and bytes nobody has documented (kept as they are). A
/// T|X writes 300 bytes for its PIM databases (278 + 2 + 20); pilot-link
/// knows 298. Either is read; new blocks are written the T|X's size.
public struct CalendarAppInfo: Equatable, Sendable {
    public var categories: CategoryAppInfo
    /// 0 = Sunday, 1 = Monday
    public var startOfWeek: UInt8
    public var padding: UInt8
    public var internalBytes: Data

    /// The size a Palm OS 5.4 device writes.
    public static let size = CategoryAppInfo.size + 2 + 20

    public init(categories: CategoryAppInfo = CategoryAppInfo(), startOfWeek: UInt8 = 0) {
        self.categories = categories
        self.startOfWeek = startOfWeek
        padding = 0
        internalBytes = Data(count: 20)
    }

    public init(data: Data) throws {
        var r = ByteReader(data)
        categories = try CategoryAppInfo(bytes: try r.slice(CategoryAppInfo.size))
        startOfWeek = try r.u8()
        padding = try r.u8()
        internalBytes = Data(r.rest())
    }

    public func encode() -> Data {
        var w = ByteWriter()
        w.append(categories.encode())
        w.u8(startOfWeek)
        w.u8(padding)
        w.append(internalBytes)
        return w.data
    }
}
