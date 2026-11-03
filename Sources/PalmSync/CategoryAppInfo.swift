import Foundation

/// The standard category block at the start of every PIM database's
/// AppInfo: 16 categories of up to 15 characters, each with an ID, 278 bytes.
///
///      0  renamedCategories  UInt16, one bit per category
///      2  names[16][16]      NUL-terminated
///    258  ids[16]            unique per category; the Palm hands out 0-127,
///                            a desktop 128-255
///    274  lastUniqueID
///    275  padding[3]
public struct CategoryAppInfo: Equatable, Sendable {
    public var renamed: UInt16
    public var names: [String]
    public var ids: [UInt8]
    public var lastUniqueID: UInt8
    /// Kept so a block read from a device writes back byte for byte.
    public var padding: [UInt8]

    public static let count = 16
    public static let nameWidth = 16
    public static let size = 278

    /// A new block as a Palm OS 5 device makes one: every slot has its ID
    /// 0-15 and lastUniqueID is 15, named or not.
    public init(names: [String] = ["Unfiled"], ids: [UInt8]? = nil, lastUniqueID: UInt8 = 15) {
        renamed = 0
        self.names = names + Array(repeating: "", count: max(0, Self.count - names.count))
        self.ids = ids ?? (0..<Self.count).map { UInt8($0) }
        self.lastUniqueID = lastUniqueID
        padding = [0, 0, 0]
    }

    public init(bytes: ArraySlice<UInt8>) throws {
        var r = ByteReader(Array(bytes))
        renamed = try r.u16()
        names = try (0..<Self.count).map { _ in try r.fixedString(Self.nameWidth) }
        ids = Array(try r.slice(Self.count))
        lastUniqueID = try r.u8()
        padding = Array(try r.slice(3))
    }

    public func encode() -> [UInt8] {
        var w = ByteWriter()
        w.u16(renamed)
        for i in 0..<Self.count {
            w.fixedString(i < names.count ? names[i] : "", width: Self.nameWidth)
        }
        for i in 0..<Self.count { w.u8(i < ids.count ? ids[i] : UInt8(i)) }
        w.u8(lastUniqueID)
        w.append(padding.prefix(3))
        w.zeros(3 - min(3, padding.count))
        return w.bytes
    }

    /// The categories that have a name.
    public var named: [(index: Int, name: String, id: UInt8)] {
        names.enumerated().compactMap { i, name in
            name.isEmpty ? nil : (i, name, ids[i])
        }
    }
}
