import Foundation

/// What identifies an item on the Mac side: the series (EventKit's
/// calendarItemIdentifier, a CNContact's identifier) and, for an occurrence that stands on its own on
/// the Palm (edited on the Mac, or expanded because the Palm cannot express
/// the rule), the date the rule put it on.
public struct MacKey: Hashable, Codable, Sendable {
    public var seriesID: String
    public var occurrence: Date?

    public init(seriesID: String, occurrence: Date? = nil) {
        self.seriesID = seriesID
        self.occurrence = occurrence
    }
}

/// One synced item, as both sides agreed on it at the last sync. The merge
/// compares each side against `base`; `palmRecord` keeps the Palm's bytes so
/// an update can be written without losing the blobs the Palm put there.
public struct MirrorEntry<Item: SyncedItem>: Equatable, Codable, Sendable {
    public var palmID: UInt32
    public var mac: MacKey
    public var base: Item
    public var palmRecord: Data
    /// The Mac owns this item (an expanded occurrence of a rule the Palm
    /// cannot express): edits made on the Palm are logged and undone.
    public var macOwned: Bool
    /// The Palm's private flag.
    public var secret: Bool

    public init(palmID: UInt32, mac: MacKey, base: Item, palmRecord: Data, macOwned: Bool = false, secret: Bool = false) {
        self.palmID = palmID
        self.mac = mac
        self.base = base
        self.palmRecord = palmRecord
        self.macOwned = macOwned
        self.secret = secret
    }

    enum CodingKeys: String, CodingKey { case palmID, mac, base, palmRecord, macOwned, secret }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        palmID = try c.decode(UInt32.self, forKey: .palmID)
        mac = try c.decode(MacKey.self, forKey: .mac)
        base = try c.decode(Item.self, forKey: .base)
        palmRecord = try c.decode(Data.self, forKey: .palmRecord)
        macOwned = try c.decodeIfPresent(Bool.self, forKey: .macOwned) ?? false
        secret = try c.decodeIfPresent(Bool.self, forKey: .secret) ?? false   // mirrors from before the flag
    }
}

/// The sync state for one Palm database on one device. Lose it and the next
/// sync is a slow one that matches records by content. Kept as a JSON file
/// next to the device's backup: small, readable, diffable.
public struct SyncMirror<Item: SyncedItem>: Equatable, Codable, Sendable {
    /// This Mac's ID as written into the Palm's lastSyncPC: when the Palm
    /// reports the same one, its modified flags are trustworthy.
    public var pcID: UInt32
    public var lastSync: Date?
    public var entries: [MirrorEntry<Item>]
    /// The Palm's DateFix start year (1904 without DateFix) when the mirror
    /// was last saved; nil in a mirror from before this was recorded. When
    /// the Palm reports another one, its stored dates mean other years than
    /// the mirror's bases say (see `SyncEngine.previousDateShift`).
    public var dateFixStartYear: Int?

    public init(pcID: UInt32, lastSync: Date? = nil, entries: [MirrorEntry<Item>] = [], dateFixStartYear: Int? = nil) {
        self.pcID = pcID
        self.lastSync = lastSync
        self.entries = entries
        self.dateFixStartYear = dateFixStartYear
    }

    /// A fresh ID for a Mac that has none yet: anything but 0, which the
    /// Palm uses for "never synced".
    public static func newPCID() -> UInt32 {
        max(1, UInt32.random(in: 1...UInt32.max))
    }

    public static func load(from url: URL) throws -> SyncMirror {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        return try decoder.decode(SyncMirror.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
