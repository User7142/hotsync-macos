import Foundation

/// A Palm record database (.pdb) in memory: header, AppInfo and SortInfo
/// blocks, and the records with their attributes and unique IDs. Parses the
/// files hotsync-macos backs up and writes files it can install, byte for
/// byte in the layout pilot-link's pi-file uses (header, record list, two
/// padding bytes, AppInfo, SortInfo, record data in list order).
///
/// Resource databases (.prc) are not records and are refused.
///
/// Layout (Palm File Format Specification, big-endian):
///
///      0  name[32]           NUL-terminated
///     32  attributes         UInt16, bit 0 = resource database
///     34  version            UInt16
///     36  creationDate       UInt32, seconds since 1904-01-01
///     40  modificationDate
///     44  lastBackupDate
///     48  modificationNumber
///     52  appInfoOffset      0 = none
///     56  sortInfoOffset     0 = none
///     60  type[4]
///     64  creator[4]
///     68  uniqueIDSeed
///     72  nextRecordListID
///     76  numRecords         UInt16
///     78  record list, 8 bytes each: offset[4] attributes[1] uniqueID[3]
public struct PalmDatabase: Equatable, Sendable {
    public struct Record: Equatable, Sendable {
        /// Flags in the high nibble, the category in the low nibble.
        public var attributes: UInt8
        /// 24 bits; the Palm assigns it, 0 means "not yet".
        public var uniqueID: UInt32
        public var data: Data

        public static let deleted: UInt8 = 0x80
        public static let dirty: UInt8 = 0x40
        public static let busy: UInt8 = 0x20
        public static let secret: UInt8 = 0x10

        public init(attributes: UInt8 = 0, category: Int = 0, uniqueID: UInt32 = 0, data: Data) {
            self.attributes = (attributes & 0xF0) | UInt8(category & 0x0F)
            self.uniqueID = uniqueID & 0x00FF_FFFF
            self.data = data
        }

        public var category: Int {
            get { Int(attributes & 0x0F) }
            set { attributes = (attributes & 0xF0) | UInt8(newValue & 0x0F) }
        }
        public var isDeleted: Bool { attributes & Self.deleted != 0 }
        public var isDirty: Bool { attributes & Self.dirty != 0 }
        public var isBusy: Bool { attributes & Self.busy != 0 }
        public var isSecret: Bool { attributes & Self.secret != 0 }
    }

    public enum Problem: Error, Equatable, Sendable {
        case tooSmall
        case resourceDatabase
        case truncated
        case badRecordList
    }

    public var name: String
    public var attributes: UInt16
    public var version: UInt16
    /// Seconds since 1904-01-01 00:00 UTC, as the Palm stores them.
    public var creationDate: UInt32
    public var modificationDate: UInt32
    public var lastBackupDate: UInt32
    public var modificationNumber: UInt32
    public var type: String
    public var creator: String
    public var uniqueIDSeed: UInt32
    public var nextRecordListID: UInt32
    public var appInfo: Data?
    public var sortInfo: Data?
    public var records: [Record]

    public static let headerSize = 78
    static let entrySize = 8
    /// Difference between the Palm epoch (1904) and the Unix epoch (1970).
    public static let epochOffset: TimeInterval = 2_082_844_800

    public init(name: String, type: String, creator: String, attributes: UInt16 = 0x0008,
                version: UInt16 = 0, created: Date = Date(), appInfo: Data? = nil,
                records: [Record] = []) {
        self.name = name
        self.attributes = attributes & ~0x0001
        self.version = version
        let palmSeconds = UInt32(max(0, created.timeIntervalSince1970 + Self.epochOffset))
        self.creationDate = palmSeconds
        self.modificationDate = palmSeconds
        self.lastBackupDate = 0
        self.modificationNumber = 0
        self.type = type
        self.creator = creator
        self.uniqueIDSeed = 0
        self.nextRecordListID = 0
        self.appInfo = appInfo
        self.sortInfo = nil
        self.records = records
    }

    public static func date(fromPalmSeconds seconds: UInt32) -> Date? {
        let unix = TimeInterval(seconds) - epochOffset
        return unix > 0 ? Date(timeIntervalSince1970: unix) : nil
    }

    // MARK: Parsing

    public init(data: Data) throws {
        var r = ByteReader(data)
        guard data.count >= Self.headerSize else { throw Problem.tooSmall }

        name = try r.fixedString(32)
        attributes = try r.u16()
        guard attributes & 0x0001 == 0 else { throw Problem.resourceDatabase }
        version = try r.u16()
        creationDate = try r.u32()
        modificationDate = try r.u32()
        lastBackupDate = try r.u32()
        modificationNumber = try r.u32()
        let appInfoOffset = Int(try r.u32())
        let sortInfoOffset = Int(try r.u32())
        type = PalmText.string(try r.slice(4))
        creator = PalmText.string(try r.slice(4))
        uniqueIDSeed = try r.u32()
        nextRecordListID = try r.u32()
        let count = Int(try r.u16())

        guard Self.headerSize + count * Self.entrySize <= data.count else { throw Problem.truncated }
        var entries: [(offset: Int, attributes: UInt8, uniqueID: UInt32)] = []
        entries.reserveCapacity(count)
        for _ in 0..<count {
            let offset = Int(try r.u32())
            let attributes = try r.u8()
            let uid = UInt32(try r.u8()) << 16 | UInt32(try r.u8()) << 8 | UInt32(try r.u8())
            guard offset <= data.count else { throw Problem.badRecordList }
            entries.append((offset, attributes, uid))
        }

        // The blocks sit between the record list and the first record, in
        // the order AppInfo, SortInfo; a block ends where the next thing starts.
        let bytes = r.bytes
        let firstRecord = entries.first?.offset ?? data.count
        func block(at offset: Int, endingAt end: Int) throws -> Data? {
            guard offset > 0 else { return nil }
            guard offset <= end, end <= bytes.count else { throw Problem.badRecordList }
            return Data(bytes[offset..<end])
        }
        appInfo = try block(at: appInfoOffset, endingAt: sortInfoOffset > 0 ? sortInfoOffset : firstRecord)
        sortInfo = try block(at: sortInfoOffset, endingAt: firstRecord)

        records = []
        records.reserveCapacity(count)
        for (i, e) in entries.enumerated() {
            let end = i + 1 < entries.count ? entries[i + 1].offset : data.count
            guard e.offset <= end else { throw Problem.badRecordList }
            records.append(Record(attributes: e.attributes & 0xF0, category: Int(e.attributes & 0x0F),
                                  uniqueID: e.uniqueID, data: Data(bytes[e.offset..<end])))
        }
    }

    // MARK: Writing

    public func encode() -> Data {
        var w = ByteWriter()
        var offset = Self.headerSize + records.count * Self.entrySize + 2
        let appInfoOffset = appInfo.map { _ in offset } ?? 0
        offset += appInfo?.count ?? 0
        let sortInfoOffset = sortInfo.map { _ in offset } ?? 0
        offset += sortInfo?.count ?? 0

        w.fixedString(name, width: 32)
        w.u16(attributes & ~0x0001)
        w.u16(version)
        w.u32(creationDate)
        w.u32(modificationDate)
        w.u32(lastBackupDate)
        w.u32(modificationNumber)
        w.u32(UInt32(appInfoOffset))
        w.u32(UInt32(sortInfoOffset))
        w.append(fourCC(type))
        w.append(fourCC(creator))
        w.u32(uniqueIDSeed)
        w.u32(nextRecordListID)
        w.u16(UInt16(records.count))

        for record in records {
            w.u32(UInt32(offset))
            w.u8(record.attributes)
            w.u8(UInt8((record.uniqueID >> 16) & 0xFF))
            w.u8(UInt8((record.uniqueID >> 8) & 0xFF))
            w.u8(UInt8(record.uniqueID & 0xFF))
            offset += record.data.count
        }
        w.zeros(2)
        if let appInfo { w.append(appInfo) }
        if let sortInfo { w.append(sortInfo) }
        for record in records { w.append(record.data) }
        return w.data
    }

    private func fourCC(_ s: String) -> [UInt8] {
        var b = PalmText.bytes(s)
        if b.count > 4 { b = Array(b.prefix(4)) }
        return b + [UInt8](repeating: 0x20, count: 4 - b.count)
    }
}
