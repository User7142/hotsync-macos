import Foundation

/// A calendar date as the Palm packs it into 16 bits:
/// `(year - 1904) << 9 | month << 5 | day`, month 1-12, day 1-31.
/// 0xFFFF means "no date" and is represented by nil where it can occur.
public struct PalmDate: Equatable, Hashable, Comparable, Codable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public static let none: UInt16 = 0xFFFF

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(packed: UInt16) {
        year = 1904 + Int(packed >> 9)
        month = Int((packed >> 5) & 0x0F)
        day = Int(packed & 0x1F)
    }

    /// The 16-bit form. A year outside 1904…2031 cannot be stored: it is
    /// clamped to the window's edge (2031-12-31 or 1904-01-01), never to
    /// 0xFFFF, which would mean "no date".
    public var packed: UInt16 {
        if year > 2031 { return UInt16((2031 - 1904) << 9 | 12 << 5 | 31) }
        if year < 1904 { return UInt16(1 << 5 | 1) }
        return UInt16((year - 1904) << 9 | month << 5 | day)
    }
    /// The last day a Palm record can hold.
    public static let maxRepresentable = PalmDate(year: 2031, month: 12, day: 31)

    public static func < (a: PalmDate, b: PalmDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    public var dateComponents: DateComponents {
        DateComponents(year: year, month: month, day: day)
    }
}

/// A time of day, minute resolution, as the Palm stores it: hour, minute.
public struct PalmTime: Equatable, Hashable, Comparable, Codable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public static func < (a: PalmTime, b: PalmTime) -> Bool {
        (a.hour, a.minute) < (b.hour, b.minute)
    }
}
