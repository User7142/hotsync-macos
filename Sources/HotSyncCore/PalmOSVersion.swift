import Foundation

/// A Palm OS version as the Palm reports it (SysInfo.romVersion, feature
/// 'psys' 1): sysMakeROMVersion - major in the top byte (BCD), then minor
/// and bugfix nibbles.
public struct PalmOSVersion: Equatable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let bugfix: Int

    public init(rom: UInt32) {
        major = Int((rom >> 28) & 0xF) * 10 + Int((rom >> 24) & 0xF)
        minor = Int((rom >> 20) & 0xF)
        bugfix = Int((rom >> 16) & 0xF)
    }

    public var description: String { "\(major).\(minor).\(bugfix)" }

    /// The ROM can be read over HotSync (DLP RPC) only up to Palm OS 4
    public var canDumpROM: Bool { major < 5 }

    /// Palm OS 5.2 (Tungsten T3) and later have the Garnet PIM applications
    /// with the CalendarDB-PDat, ContactsDB-PAdd and TasksDB-PTod databases
    /// and the locL* location databases; earlier devices use Datebook,
    /// Address and ToDo and have no time-zone tables.
    public var hasGarnetPIM: Bool { major > 5 || (major == 5 && minor >= 2) }
}
