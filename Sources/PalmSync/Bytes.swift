import Foundation

/// What a codec reports when the bytes do not fit the record layout.
public enum PalmFormatError: Error, Equatable, Sendable {
    /// The data ends before the field at this offset.
    case truncated(at: Int)
    /// A NUL-terminated string has no NUL before the data ends.
    case unterminatedString(at: Int)
    /// A field holds a value the format does not allow.
    case invalidValue(field: String, value: Int)
    /// Bytes remain after the last field the layout knows about.
    case trailingBytes(count: Int)
}

/// Big-endian reads over a byte array, as the Palm stores everything.
struct ByteReader {
    let bytes: [UInt8]
    private(set) var offset: Int

    init(_ bytes: [UInt8], at offset: Int = 0) {
        self.bytes = bytes
        self.offset = offset
    }

    init(_ data: Data) {
        self.init([UInt8](data))
    }

    var remaining: Int { bytes.count - offset }
    var isAtEnd: Bool { remaining <= 0 }

    private mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
        guard remaining >= count else { throw PalmFormatError.truncated(at: offset) }
        defer { offset += count }
        return bytes[offset..<offset + count]
    }

    mutating func u8() throws -> UInt8 {
        try take(1).first!
    }

    mutating func u16() throws -> UInt16 {
        let b = try take(2)
        return UInt16(b[b.startIndex]) << 8 | UInt16(b[b.startIndex + 1])
    }

    mutating func u32() throws -> UInt32 {
        let b = try take(4)
        return UInt32(b[b.startIndex]) << 24 | UInt32(b[b.startIndex + 1]) << 16
            | UInt32(b[b.startIndex + 2]) << 8 | UInt32(b[b.startIndex + 3])
    }

    mutating func slice(_ count: Int) throws -> ArraySlice<UInt8> {
        try take(count)
    }

    mutating func rest() -> ArraySlice<UInt8> {
        defer { offset = bytes.count }
        return bytes[offset...]
    }

    /// A NUL-terminated Windows-1252 string; the NUL is consumed.
    mutating func cString() throws -> String {
        guard let end = bytes[offset...].firstIndex(of: 0) else {
            throw PalmFormatError.unterminatedString(at: offset)
        }
        defer { offset = end + 1 }
        return PalmText.string(bytes[offset..<end])
    }

    /// A fixed-width field holding a NUL-terminated string (text up to the
    /// first NUL, the rest of the field is padding).
    mutating func fixedString(_ width: Int) throws -> String {
        let field = try take(width)
        let text = field.prefix { $0 != 0 }
        return PalmText.string(text)
    }
}

/// Big-endian writes, the mirror of ByteReader.
struct ByteWriter {
    private(set) var bytes: [UInt8] = []

    var count: Int { bytes.count }
    var data: Data { Data(bytes) }

    mutating func u8(_ v: UInt8) { bytes.append(v) }
    mutating func u16(_ v: UInt16) { bytes += [UInt8(v >> 8), UInt8(v & 0xFF)] }
    mutating func u32(_ v: UInt32) {
        bytes += [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }
    mutating func append(_ more: some Sequence<UInt8>) { bytes += more }
    mutating func zeros(_ count: Int) { bytes += [UInt8](repeating: 0, count: count) }

    /// NUL-terminated Windows-1252.
    mutating func cString(_ s: String) {
        bytes += PalmText.bytes(s)
        bytes.append(0)
    }

    /// Text in a fixed-width field, NUL-terminated and zero-padded; longer
    /// text is cut to width - 1 so the NUL always fits.
    mutating func fixedString(_ s: String, width: Int) {
        var text = PalmText.bytes(s)
        if text.count > width - 1 { text = Array(text.prefix(width - 1)) }
        bytes += text
        zeros(width - text.count)
    }

    /// Overwrites a byte already written (for flags that are known only
    /// after the fields behind them).
    mutating func set(_ v: UInt8, at offset: Int) { bytes[offset] = v }
}

/// Palm OS text is Windows-1252 (Palm calls it "Palm Latin"); Swift strings
/// are Unicode. Characters the Palm cannot show are replaced on the way out.
public enum PalmText {
    public static func string(_ bytes: some Collection<UInt8>) -> String {
        let data = Data(bytes)
        return String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(decoding: data, as: UTF8.self)
    }

    public static func bytes(_ s: String) -> [UInt8] {
        if let data = s.data(using: .windowsCP1252) { return [UInt8](data) }
        return [UInt8](s.data(using: .windowsCP1252, allowLossyConversion: true) ?? Data())
    }
}
