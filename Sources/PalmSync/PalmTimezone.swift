import Foundation

/// A daylight-saving transition rule as the Palm OS 5 Calendar stores it:
/// "the <week>th <weekday> of <month>".
public struct DSTRule: Equatable, Sendable {
    /// 0 = Sunday … 6 = Saturday
    public var weekday: UInt8
    /// 0 = first, 1 = second, 2 = third, 3 = fourth, 4 = last
    public var week: UInt8
    /// 1-12, 0 = none
    public var month: UInt8
    /// Seen as 0-3 on devices; meaning unknown.
    public var unknown: UInt8

    public init(weekday: UInt8, week: UInt8, month: UInt8, unknown: UInt8 = 0) {
        self.weekday = weekday
        self.week = week
        self.month = month
        self.unknown = unknown
    }

    static func decode(_ r: inout ByteReader) throws -> DSTRule {
        let weekday = try r.u8()
        let week = try r.u8()
        let month = try r.u8()
        let unknown = try r.u8()
        guard weekday <= 6 else { throw PalmFormatError.invalidValue(field: "dst.weekday", value: Int(weekday)) }
        guard week <= 4 else { throw PalmFormatError.invalidValue(field: "dst.week", value: Int(week)) }
        guard month <= 12 else { throw PalmFormatError.invalidValue(field: "dst.month", value: Int(month)) }
        return DSTRule(weekday: weekday, week: week, month: month, unknown: unknown)
    }

    func encode(_ w: inout ByteWriter) {
        w.u8(weekday)
        w.u8(week)
        w.u8(month)
        w.u8(unknown)
    }
}

/// The time zone a Palm OS 5 Calendar event carries in its "Bd00" blob
/// (the same layout as an entry of the Location databases):
///
///      0  offset       Int16, minutes from GMT (Toronto: -300)
///      2  t2           0-3, meaning unknown
///      3  dstStart     DSTRule
///      7  dstEnd       DSTRule
///     11  dstObserved  0x3C = yes, 0 = no
///     12  country      Palm OS country code (Canada 4, France 7, Germany 8,
///                      UK 22, US 23, …), from a T|X's location databases
///     13  unknown      0x80 or 0
///     14  name         NUL-terminated, up to 21 characters
public struct PalmTimezone: Equatable, Sendable {
    public var offsetMinutes: Int16
    public var t2: UInt8
    public var dstStart: DSTRule
    public var dstEnd: DSTRule
    public var observesDST: Bool
    public var country: UInt8
    public var unknown: UInt8
    public var name: String

    public static let blobType = "Bd00"

    public init(offsetMinutes: Int16, name: String, observesDST: Bool = false,
                dstStart: DSTRule = DSTRule(weekday: 0, week: 0, month: 0),
                dstEnd: DSTRule = DSTRule(weekday: 0, week: 0, month: 0),
                t2: UInt8 = 0, country: UInt8 = 0, unknown: UInt8 = 0x80) {
        self.offsetMinutes = offsetMinutes
        self.name = name
        self.observesDST = observesDST
        self.dstStart = dstStart
        self.dstEnd = dstEnd
        self.t2 = t2
        self.country = country
        self.unknown = unknown
    }

    public init(data: Data) throws {
        var r = ByteReader(data)
        self = try Self.decode(&r)
        guard r.isAtEnd else { throw PalmFormatError.trailingBytes(count: r.remaining) }
    }

    /// Reads a time zone where the reader stands; a location record has
    /// more fields behind it.
    static func decode(_ r: inout ByteReader) throws -> PalmTimezone {
        var tz = PalmTimezone(offsetMinutes: 0, name: "")
        tz.offsetMinutes = Int16(bitPattern: try r.u16())
        tz.t2 = try r.u8()
        guard tz.t2 <= 3 else { throw PalmFormatError.invalidValue(field: "tz.t2", value: Int(tz.t2)) }
        tz.dstStart = try DSTRule.decode(&r)
        tz.dstEnd = try DSTRule.decode(&r)
        let observed = try r.u8()
        guard observed == 0x3C || observed == 0 else {
            throw PalmFormatError.invalidValue(field: "tz.dstObserved", value: Int(observed))
        }
        tz.observesDST = observed == 0x3C
        tz.country = try r.u8()
        tz.unknown = try r.u8()
        tz.name = try r.cString()
        return tz
    }

    public func encode() -> Data {
        var w = ByteWriter()
        write(&w)
        return w.data
    }

    func write(_ w: inout ByteWriter) {
        w.u16(UInt16(bitPattern: offsetMinutes))
        w.u8(t2)
        dstStart.encode(&w)
        dstEnd.encode(&w)
        w.u8(observesDST ? 0x3C : 0)
        w.u8(country)
        w.u8(unknown)
        w.cString(name)
    }
}
