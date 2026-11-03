import Foundation

/// A type-tagged block at the end of a Palm OS 5 PIM record:
/// type[4] length[2] data. Calendar keeps its time zone in "Bd00",
/// Contacts the picture in "Bd00" and the anniversary in "Bd01". Blobs a
/// codec does not know are carried through unchanged.
public struct PalmBlob: Equatable, Sendable {
    public var type: String
    public var data: Data

    public init(type: String, data: Data) {
        self.type = type
        self.data = data
    }

    /// Every blob up to the end of the data. Fewer than six bytes left
    /// cannot be a blob and are an error.
    static func readAll(_ r: inout ByteReader) throws -> [PalmBlob] {
        var blobs: [PalmBlob] = []
        while r.remaining >= 6 {
            let type = PalmText.string(try r.slice(4))
            let length = Int(try r.u16())
            blobs.append(PalmBlob(type: type, data: Data(try r.slice(length))))
        }
        guard r.isAtEnd else { throw PalmFormatError.trailingBytes(count: r.remaining) }
        return blobs
    }

    func write(_ w: inout ByteWriter) {
        var tag = PalmText.bytes(type)
        if tag.count > 4 { tag = Array(tag.prefix(4)) }
        w.append(tag + [UInt8](repeating: 0, count: 4 - tag.count))
        w.u16(UInt16(data.count))
        w.append(data)
    }
}
