import Foundation

/// A record of the Palm OS 5 location databases: locLDefLocationDB (the
/// built-in cities of Prefs > Date & Time) and locLCusLocationDB (the ones
/// the user adds), creator locL. The same time zone block a Calendar event
/// carries, followed by the coordinates and a note.
///
/// Layout (big-endian):
///
///      0  timezone       PalmTimezone, ends with the NUL of the name
///         unknown        one byte some devices put here (seen as 0x01);
///                        present when the latitude would otherwise be
///                        out of range, which is how pilot-link tells
///         latitude       degrees[2] minutes[2], Int16, negative = north
///         longitude      degrees[2] minutes[2], Int16, negative = east
///         note           NUL-terminated, a lone NUL when empty
public struct PalmLocation: Equatable, Sendable {
    public var timezone: PalmTimezone
    public var unknown: UInt8?
    /// As stored: degrees and minutes, negative for north.
    public var latitudeDegrees: Int16
    public var latitudeMinutes: Int16
    /// As stored: degrees and minutes, negative for east.
    public var longitudeDegrees: Int16
    public var longitudeMinutes: Int16
    public var note: String

    public init(timezone: PalmTimezone, latitude: Double, longitude: Double, note: String = "") {
        self.timezone = timezone
        unknown = nil
        // the Palm's sign convention is the opposite of the usual one
        (latitudeDegrees, latitudeMinutes) = Self.stored(-latitude)
        (longitudeDegrees, longitudeMinutes) = Self.stored(-longitude)
        self.note = note
    }

    public var name: String {
        get { timezone.name }
        set { timezone.name = newValue }
    }

    /// Decimal degrees, north positive.
    public var latitude: Double { -Self.decimal(latitudeDegrees, latitudeMinutes) }
    /// Decimal degrees, east positive.
    public var longitude: Double { -Self.decimal(longitudeDegrees, longitudeMinutes) }

    private static func decimal(_ degrees: Int16, _ minutes: Int16) -> Double {
        Double(degrees) + Double(minutes) / 60
    }

    private static func stored(_ value: Double) -> (Int16, Int16) {
        let degrees = value.rounded(.towardZero)
        let minutes = ((value - degrees) * 60).rounded()
        return (Int16(clamping: Int(degrees)), Int16(clamping: Int(minutes)))
    }

    private static func inRange(_ degrees: Int16, _ minutes: Int16) -> Bool {
        (-90...90).contains(degrees) && (-60...60).contains(minutes)
    }

    // MARK: Decoding

    public init(data: Data) throws {
        var r = ByteReader(data)
        timezone = try PalmTimezone.decode(&r)

        var degrees = Int16(bitPattern: try r.u16())
        var minutes = Int16(bitPattern: try r.u16())
        if Self.inRange(degrees, minutes) {
            unknown = nil
        } else {
            // an extra byte sits in front of the coordinates: re-read them
            var again = ByteReader(r.bytes, at: r.offset - 4)
            unknown = try again.u8()
            degrees = Int16(bitPattern: try again.u16())
            minutes = Int16(bitPattern: try again.u16())
            r = again
        }
        latitudeDegrees = degrees
        latitudeMinutes = minutes
        longitudeDegrees = Int16(bitPattern: try r.u16())
        longitudeMinutes = Int16(bitPattern: try r.u16())
        note = try r.cString()
        guard r.isAtEnd else { throw PalmFormatError.trailingBytes(count: r.remaining) }
    }

    // MARK: Encoding

    public func encode() -> Data {
        var w = ByteWriter()
        timezone.write(&w)
        if let unknown { w.u8(unknown) }
        w.u16(UInt16(bitPattern: latitudeDegrees))
        w.u16(UInt16(bitPattern: latitudeMinutes))
        w.u16(UInt16(bitPattern: longitudeDegrees))
        w.u16(UInt16(bitPattern: longitudeMinutes))
        w.cString(note)
        return w.data
    }
}
