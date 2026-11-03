import Foundation

/// The part of a Palm record and a Mac item both sides can hold: what a
/// sync compares, merges field by field, and keeps in the mirror as the
/// last agreed state. Calendar events, contacts and tasks each conform;
/// the engine is written once against this.
public protocol SyncedItem: Equatable, Hashable, Codable, Sendable {
    associatedtype Field: CaseIterable & RawRepresentable & Hashable & Sendable where Field.RawValue == String
    /// The Palm record type (CalendarEvent, Contact, PalmTask).
    associatedtype PalmRecord

    /// The Palm category name, which is also the Mac container's mapping.
    var category: String { get }
    /// What the log calls the item.
    var title: String? { get }

    init(_ record: PalmRecord, category: String)
    static func palmRecord(from data: Data) throws -> PalmRecord
    static func encode(_ record: PalmRecord) -> Data
    /// A record to write the shared fields into when there is none to
    /// write over.
    func newPalmRecord() -> PalmRecord
    /// Writes the shared fields into a Palm record, keeping what the
    /// record has besides them (blobs, unknown bytes).
    func apply(to record: inout PalmRecord)

    mutating func set(_ field: Field, from other: Self)
    func differs(from other: Self, in field: Field) -> Bool
    /// Readable value of a field for the conflict log.
    func describe(_ field: Field) -> String
    /// Slow sync: is this the same item as `other`, met without a mirror?
    func matches(_ other: Self) -> Bool
    /// Every date moved by `years` (DateFix, see `SyncEngine.dateShift`).
    func shiftingDates(by years: Int) -> Self
}

extension SyncedItem {
    /// The bytes to write for this item on top of an existing Palm record.
    public func palmBytes(over existing: Data?) -> Data {
        var record = existing.flatMap { try? Self.palmRecord(from: $0) } ?? newPalmRecord()
        apply(to: &record)
        return Self.encode(record)
    }
}

/// A Palm record as the bridge delivers it (the `record` event).
public struct PalmRecordIn: Equatable, Sendable {
    public var id: UInt32
    /// dlpRecAttr*: deleted 0x80, dirty 0x40, busy 0x20, secret 0x10, archived 0x08
    public var attributes: UInt8
    public var category: Int
    public var data: Data

    public init(id: UInt32, attributes: UInt8 = 0, category: Int = 0, data: Data) {
        self.id = id
        self.attributes = attributes
        self.category = category
        self.data = data
    }

    public var isDeleted: Bool { attributes & 0x80 != 0 }
    public var isArchived: Bool { attributes & 0x08 != 0 }
}

/// What the Palm side handed over: every record (slow sync, `readall`) or
/// only the ones changed since the last sync (fast sync, `readmodified`).
public enum PalmSnapshot: Equatable, Sendable {
    case all([PalmRecordIn])
    case modified([PalmRecordIn])
}

/// One thing the Palm gets a record for, as the Mac side hands it to the
/// engine: its key on the Mac, the shared fields, and for the calendar
/// whether the Mac owns it (an expanded occurrence the Palm must not edit).
public struct MacSyncItem<Item: SyncedItem>: Equatable, Sendable {
    public var key: MacKey
    public var item: Item
    public var macOwned: Bool
    /// The full Palm record the builder made (with what the shared fields
    /// do not cover); nil: a fresh record.
    public var palmRecord: Data?

    public init(key: MacKey, item: Item, macOwned: Bool = false, palmRecord: Data? = nil) {
        self.key = key
        self.item = item
        self.macOwned = macOwned
        self.palmRecord = palmRecord
    }
}

/// What happens when both sides changed the same field of the same item
/// to different values; the Palm Desktop conduits had the same three.
public enum ConflictPolicy: String, Codable, CaseIterable, Sendable {
    /// the Mac's value, the Palm's goes to the log
    case macWins
    /// the Palm's value, the Mac's goes to the log
    case palmWins
    /// the Mac's value in the item, and the Palm's version becomes a second
    /// item on both sides, as the Palm Desktop did; nothing is lost
    case keepBoth
    /// the user decides each one while the Palm waits (the engine's
    /// `resolve` answers; without it, the Mac wins for the first pass)
    case ask
}

public struct SyncConflict: Equatable, Sendable {
    public var palmID: UInt32?
    public var mac: MacKey?
    public var title: String
    public var field: String
    public var palmValue: String
    public var macValue: String
    /// What was done about it: macWins, palmWins or keepBoth.
    public var resolution: ConflictPolicy = .macWins
}

/// What one sync has to do, decided before anything is written: the Palm
/// side as records, the Mac side as shared-field values for the adapter,
/// and the mirror that is right once both have been applied.
public struct SyncPlan<Item: SyncedItem>: Equatable, Sendable {
    public struct PalmWrite: Equatable, Sendable {
        /// nil: a new record, the Palm assigns the ID
        public var id: UInt32?
        public var category: Int
        public var record: Data
        /// index into `entries`, to take the assigned ID
        public var entry: Int
    }

    public struct MacChange: Equatable, Sendable {
        public var key: MacKey?
        public var item: Item
        public var entry: Int
        /// For an update: the fields that differ from what the Mac holds
        /// now, so the writer touches nothing else. Empty for a create.
        public var changed: [Item.Field] = []

        public init(key: MacKey?, item: Item, entry: Int, changed: [Item.Field] = []) {
            self.key = key
            self.item = item
            self.entry = entry
            self.changed = changed
        }
    }

    /// The mirror entries after this sync; the Palm ID or Mac key of a new
    /// item is filled in by `mirror(after:)`.
    public struct Entry: Equatable, Sendable {
        public var palmID: UInt32?
        public var mac: MacKey?
        public var item: Item
        public var palmRecord: Data
        public var macOwned: Bool
        /// The Palm's private flag, kept across the sync.
        public var secret: Bool = false
    }

    public var palmWrites: [PalmWrite] = []
    /// Records the user deleted on the Mac: gone from the Palm.
    public var palmDeletes: [UInt32] = []
    /// Records that left the window: gone from the Palm and the mirror, kept
    /// on the Mac. Housekeeping, not deletions, so `massDeletion` ignores them.
    public var agedOut: [UInt32] = []
    public var macCreates: [MacChange] = []
    public var macUpdates: [MacChange] = []
    public var macDeletes: [MacKey] = []
    public var conflicts: [SyncConflict] = []
    public var log: [String] = []
    public var entries: [Entry] = []
    /// Category names the Mac uses that the Palm's AppInfo lacks.
    public var missingCategories: [String] = []
    /// Records the codec cannot read: they go back onto the Palm as they
    /// are and never reach the Mac or the mirror.
    public var opaque: [PalmRecordIn] = []

    public init() {}

    public var isEmpty: Bool {
        palmWrites.isEmpty && palmDeletes.isEmpty && macCreates.isEmpty && macUpdates.isEmpty && macDeletes.isEmpty
    }

    /// Deletions or updates large enough to be a mistake rather than
    /// housekeeping: ten or more of one kind on one side, or three or more
    /// that are a fifth of what the mirror holds. An empty source, a reset
    /// Palm, a wrong calendar mapping or a shifted clock look like that; a
    /// user's edits rarely do. The caller refuses such a plan unless told to.
    public func massChange(mirrorEntries: Int) -> SyncMassChange? {
        func mass(_ n: Int) -> Bool { n >= 10 || (n >= 3 && n * 5 >= mirrorEntries) }
        let change = SyncMassChange(macDeletes: macDeletes.count, palmDeletes: palmDeletes.count,
                                macUpdates: macUpdates.count, palmUpdates: palmWrites.filter { $0.id != nil }.count)
        let flagged = [change.macDeletes, change.palmDeletes, change.macUpdates, change.palmUpdates].contains(where: mass)
        return flagged ? change : nil
    }

    /// The deletions alone (see `massChange`).
    public func massDeletion(mirrorEntries: Int) -> (mac: Int, palm: Int)? {
        func mass(_ n: Int) -> Bool { n >= 10 || (n >= 3 && n * 5 >= mirrorEntries) }
        return mass(macDeletes.count) || mass(palmDeletes.count) ? (macDeletes.count, palmDeletes.count) : nil
    }

    /// The mirror once the plan was applied: `palmIDs` maps the entry index
    /// of each new Palm record to the ID the Palm assigned, `macKeys` the
    /// entry index of each new Mac item to its key.
    public func mirror(after old: SyncMirror<Item>, palmIDs: [Int: UInt32], macKeys: [Int: MacKey], at date: Date = Date()) -> SyncMirror<Item> {
        var mirror = old
        mirror.lastSync = date
        mirror.entries = entries.enumerated().compactMap { i, e in
            guard let palmID = e.palmID ?? palmIDs[i], let mac = e.mac ?? macKeys[i] else { return nil }
            return MirrorEntry(palmID: palmID, mac: mac, base: e.item, palmRecord: e.palmRecord, macOwned: e.macOwned, secret: e.secret)
        }
        return mirror
    }

    /// The Palm's side of the plan as records for a whole database to
    /// install: every entry's record, new ones with IDs this Mac assigns
    /// above the Palm's highest, categories from the Palm's own block plus
    /// any the Mac brought along (into free slots). Replacing the database
    /// whole keeps the Palm's record order sane and resets its modified
    /// flags. `order` sorts the records as the Palm application expects.
    ///
    /// Returns the records, per entry index the ID a new record got (for
    /// `mirror(after:palmIDs:macKeys:)`), the categories, and the next ID.
    public func palmRecords(categories existing: CategoryAppInfo, order: (Item, Item) -> Bool)
        -> (records: [PalmDatabase.Record], palmIDs: [Int: UInt32], categories: CategoryAppInfo, nextID: UInt32) {
        var categories = existing
        func index(of name: String) -> Int {
            let short = String(name.prefix(CategoryAppInfo.nameWidth - 1))
            if let i = categories.names.firstIndex(of: short) { return i }
            if let free = categories.names.indices.dropFirst().first(where: { categories.names[$0].isEmpty }) {
                categories.names[free] = short
                return free
            }
            // no slot left: "Other" (made if a slot frees up later), else Unfiled
            return categories.names.firstIndex(of: "Other") ?? 0
        }

        // above every ID on the Palm, the unreadable records' included
        var nextID = max(entries.compactMap(\.palmID).max() ?? 0, opaque.map(\.id).max() ?? 0) + 1
        var palmIDs: [Int: UInt32] = [:]
        var records: [(item: Item, record: PalmDatabase.Record)] = []
        for (i, entry) in entries.enumerated() {
            let id: UInt32
            if let known = entry.palmID {
                id = known
            } else {
                id = nextID
                nextID += 1
                palmIDs[i] = id
            }
            records.append((entry.item, PalmDatabase.Record(attributes: entry.secret ? PalmDatabase.Record.secret : 0,
                                                             category: index(of: entry.item.category), uniqueID: id, data: entry.palmRecord)))
        }
        records.sort { order($0.item, $1.item) }
        // what could not be read keeps its place, flags and bytes
        let kept = opaque.map {
            PalmDatabase.Record(attributes: $0.attributes & PalmDatabase.Record.secret, category: $0.category, uniqueID: $0.id, data: $0.data)
        }
        return (records.map(\.record) + kept, palmIDs, categories, nextID)
    }
}

/// What a plan does to items both sides already had: deletions and updates
/// on each side (creates and aged-out records are not counted).
public struct SyncMassChange: Equatable, Sendable {
    public var macDeletes: Int
    public var palmDeletes: Int
    public var macUpdates: Int
    public var palmUpdates: Int

    public init(macDeletes: Int, palmDeletes: Int, macUpdates: Int, palmUpdates: Int) {
        self.macDeletes = macDeletes
        self.palmDeletes = palmDeletes
        self.macUpdates = macUpdates
        self.palmUpdates = palmUpdates
    }
}

public enum SyncError: Error, Equatable {
    /// A fast sync needs a mirror from an earlier sync.
    case fastSyncWithoutMirror
}

/// Three-way merge of a Palm database against the Mac's items, with the
/// mirror as the common ancestor. Rules:
///
/// - Only one side changed a field: that value wins. Both changed it to
///   different values: the `conflictPolicy` decides (Mac wins, Palm wins,
///   keep both), the losing value goes to the conflict log.
/// - Deleted on one side, unchanged on the other: deleted on both. Deleted
///   on one side, edited on the other: the edit wins and the item comes
///   back on the side that deleted it.
/// - Archived on the Palm: removed from the Palm's view, kept on the Mac.
/// - An item `inWindow` says no to (a calendar event whose date left the
///   window) is dropped from the Palm and the mirror, never from the Mac.
/// - An item the Mac owns (an expanded occurrence) takes no Palm edits:
///   they are logged and the record is rewritten from the Mac.
/// - Slow sync: Palm records unknown to the mirror are matched to Mac items
///   by content (`matches`) before either side gets a copy of the other's.
public struct SyncEngine<Item: SyncedItem> {
    /// One side's state of a mirrored item. `missing`: not on the Palm in a
    /// slow sync whose deletions are not trusted (see `palmDeletesTrusted`).
    enum Side { case same, changed(Item), deleted, archived, missing }

    public var conflictPolicy: ConflictPolicy
    /// With `conflictPolicy == .ask`: the answer for the n-th conflict of
    /// the plan (conflicts come in a fixed order, so a second plan with the
    /// same input asks the same questions). nil: the Mac wins meanwhile.
    public var resolve: (@Sendable (Int, SyncConflict) -> ConflictPolicy)?
    /// Whether a mirrored record absent from the Palm means the user deleted
    /// it there. False after a hard reset, a sync with another PC, or an
    /// interrupted install (`lastSyncPC` is not ours): then, as HotSync
    /// Manager's conduits did, nothing is deleted on the Mac and the record
    /// is put back on the Palm.
    public var palmDeletesTrusted: Bool
    /// DateFix: years to add to every date read from the Palm and to take
    /// away from every date written to it. Record bytes stay in the Palm's
    /// years; only items carry real ones.
    public var dateShift = 0
    /// The `dateShift` the mirror's records were written under, when it is
    /// not `dateShift` any more: DateFix was installed, removed or moved to
    /// another start year since the last sync. The Palm's record bytes did
    /// not change, so they are read with the old shift (and match the
    /// mirror's bases), and every mirrored record is written back under
    /// the new one, so the Palm shows the right years again. Records new on
    /// the Palm were entered after the change and are read with `dateShift`.
    public var previousDateShift: Int?
    /// After reading a mirrored item from the Palm: a chance to undo what
    /// the Palm could not store (DateFix's clamp), given the mirror's base.
    public var unclamp: (@Sendable (Item, Item) -> Item)?
    /// Whether a mirrored item missing from the Mac's list is still the
    /// Mac's business (deleted there) or merely outside what the Mac was
    /// asked for (aged out). Always true for contacts and tasks.
    public var inWindow: @Sendable (Item) -> Bool

    public init(conflictPolicy: ConflictPolicy = .macWins, palmDeletesTrusted: Bool = true,
                inWindow: @escaping @Sendable (Item) -> Bool = { _ in true }) {
        self.conflictPolicy = conflictPolicy
        self.palmDeletesTrusted = palmDeletesTrusted
        self.inWindow = inWindow
    }

    public func plan(palm snapshot: PalmSnapshot, palmCategories: [String], mac items: [MacSyncItem<Item>],
                     mirror: SyncMirror<Item>) throws -> SyncPlan<Item> {
        var plan = SyncPlan<Item>()
        var categoryIndex: [String: Int] = [:]
        for (i, name) in palmCategories.enumerated() where !name.isEmpty { categoryIndex[name] = i }

        func palmCategory(_ name: String) -> Int {
            if let i = categoryIndex[name] { return i }
            if !plan.missingCategories.contains(name) { plan.missingCategories.append(name) }
            return 0
        }
        let rebase = previousDateShift.map { $0 != dateShift } ?? false
        let mirroredShift = rebase ? previousDateShift! : dateShift
        var keptUndecoded = Set<Int>()   // entries whose Palm bytes no longer decode
        func palmItem(_ record: PalmRecordIn, shift: Int) -> Item? {
            guard let decoded = try? Item.palmRecord(from: record.data) else {
                // kept as it is on the Palm (see `opaque`), never shown to the Mac
                plan.log.append("Palm record \(record.id): cannot be decoded, left alone")
                return nil
            }
            let name = record.category < palmCategories.count ? palmCategories[record.category] : "Unfiled"
            return Item(decoded, category: name).shiftingDates(by: shift)
        }
        func writePalm(_ item: Item, id: UInt32?, over existing: Data?, mac: MacKey?, macOwned: Bool, secret: Bool = false) {
            let bytes = item.shiftingDates(by: -dateShift).palmBytes(over: existing)
            plan.entries.append(.init(palmID: id, mac: mac, item: item, palmRecord: bytes, macOwned: macOwned, secret: secret))
            plan.palmWrites.append(.init(id: id, category: palmCategory(item.category), record: bytes, entry: plan.entries.count - 1))
        }

        // What the Palm has now, by ID
        let fast: Bool
        var palmRecords: [UInt32: PalmRecordIn] = [:]
        switch snapshot {
        case .all(let records):
            fast = false
            for r in records { palmRecords[r.id] = r }
        case .modified(let records):
            guard mirror.lastSync != nil else { throw SyncError.fastSyncWithoutMirror }
            fast = true
            for r in records { palmRecords[r.id] = r }
        }
        var macItems: [MacKey: MacSyncItem<Item>] = [:]
        for item in items { macItems[item.key] = item }

        var usedPalm = Set<UInt32>()
        var usedMac = Set<MacKey>()

        // Items both sides know
        for entry in mirror.entries {
            usedPalm.insert(entry.palmID)
            usedMac.insert(entry.mac)
            let base = entry.base
            let current = palmRecords[entry.palmID]
            let macItem = macItems[entry.mac]

            // the Palm's state
            var palm: Side = .same
            var palmBytes = entry.palmRecord
            var secret = entry.secret
            if let current {
                secret = current.attributes & PalmDatabase.Record.secret != 0
                if current.isArchived { palm = .archived }
                else if current.isDeleted { palm = .deleted }
                else if var item = palmItem(current, shift: mirroredShift) {
                    if let unclamp { item = unclamp(item, base) }
                    palmBytes = current.data
                    palm = item == base ? .same : .changed(item)
                } else {
                    // the Palm's bytes no longer decode: keep them as they
                    // are, tell the Mac nothing, keep the mirror's base
                    plan.entries.append(.init(palmID: entry.palmID, mac: entry.mac, item: base, palmRecord: current.data,
                                              macOwned: entry.macOwned, secret: secret))
                    keptUndecoded.insert(plan.entries.count - 1)
                    continue
                }
            } else if !fast {
                // a slow sync lists every record: gone means deleted, if the
                // Palm's state is to be believed
                palm = palmDeletesTrusted ? .deleted : .missing
            }

            // the Mac's state
            var mac: Side = .same
            var agedOut = false
            if let macItem {
                mac = macItem.item == base ? .same : .changed(macItem.item)
            } else if !inWindow(base) {
                agedOut = true
            } else {
                mac = .deleted
            }

            if agedOut {
                if case .same = palm { plan.agedOut.append(entry.palmID) }
                if case .changed = palm { plan.agedOut.append(entry.palmID) }
                plan.log.append("\(base.title ?? "?"): left the window, removed from the Palm")
                continue
            }

            if case .missing = palm {
                if case .same = mac {
                    plan.log.append("\(base.title ?? "?"): missing on the Palm, put back (its deletions are not trusted)")
                    writePalm(base, id: nil, over: entry.palmRecord, mac: entry.mac, macOwned: entry.macOwned, secret: secret)
                    continue
                }
                palm = .deleted    // edited or deleted on the Mac: the usual rules
            }

            switch (palm, mac) {
            case (.same, .same):
                plan.entries.append(.init(palmID: entry.palmID, mac: entry.mac, item: base, palmRecord: palmBytes, macOwned: entry.macOwned, secret: secret))

            case (.archived, _):
                plan.log.append("\(base.title ?? "?"): archived on the Palm, kept on the Mac")
                // keep the Mac's version; the Palm forgets it

            case (.deleted, .same):
                plan.macDeletes.append(entry.mac)

            case (.deleted, .changed(let item)):
                plan.log.append("\(item.title ?? "?"): deleted on the Palm but edited on the Mac, put back on the Palm")
                writePalm(item, id: nil, over: entry.palmRecord, mac: entry.mac, macOwned: entry.macOwned, secret: secret)

            case (.same, .deleted):
                plan.palmDeletes.append(entry.palmID)

            case (.changed(let item), .deleted):
                if entry.macOwned {
                    plan.palmDeletes.append(entry.palmID)
                } else {
                    plan.log.append("\(item.title ?? "?"): deleted on the Mac but edited on the Palm, put back on the Mac")
                    plan.entries.append(.init(palmID: entry.palmID, mac: nil, item: item, palmRecord: palmBytes, macOwned: false, secret: secret))
                    plan.macCreates.append(.init(key: nil, item: item, entry: plan.entries.count - 1))
                }

            case (.changed(let item), .same):
                if entry.macOwned {
                    plan.log.append("\(base.title ?? "?"): edited on the Palm, but the Mac owns it; the edit is undone")
                    writePalm(base, id: entry.palmID, over: palmBytes, mac: entry.mac, macOwned: true, secret: secret)
                } else {
                    plan.entries.append(.init(palmID: entry.palmID, mac: entry.mac, item: item, palmRecord: palmBytes, macOwned: false, secret: secret))
                    plan.macUpdates.append(.init(key: entry.mac, item: item, entry: plan.entries.count - 1,
                                                 changed: Self.fields(of: item, differingFrom: base)))
                }

            case (.same, .changed(let item)):
                writePalm(item, id: entry.palmID, over: palmBytes, mac: entry.mac, macOwned: entry.macOwned, secret: secret)

            case (.changed(let palmVersion), .changed(let macVersion)):
                if entry.macOwned {
                    plan.log.append("\(base.title ?? "?"): edited on the Palm, but the Mac owns it; the edit is undone")
                    writePalm(macVersion, id: entry.palmID, over: palmBytes, mac: entry.mac, macOwned: true, secret: secret)
                    break
                }
                let (merged, keptBoth) = Self.merge(base: base, palm: palmVersion, mac: macVersion, palmID: entry.palmID, mac: entry.mac,
                                                    policy: conflictPolicy, resolve: resolve, conflicts: &plan.conflicts)
                if keptBoth {
                    // the Palm's version lives on as a second item on both sides
                    plan.log.append("\(palmVersion.title ?? "?"): conflict, the Palm's version is kept as a second item")
                    writePalm(palmVersion, id: nil, over: palmBytes, mac: nil, macOwned: false, secret: secret)
                    plan.macCreates.append(.init(key: nil, item: palmVersion, entry: plan.entries.count - 1))
                }
                if merged != palmVersion {
                    writePalm(merged, id: entry.palmID, over: palmBytes, mac: entry.mac, macOwned: false, secret: secret)
                } else {
                    plan.entries.append(.init(palmID: entry.palmID, mac: entry.mac, item: merged, palmRecord: palmBytes, macOwned: false, secret: secret))
                }
                if merged != macVersion {
                    plan.macUpdates.append(.init(key: entry.mac, item: merged, entry: plan.entries.count - 1,
                                                 changed: Self.fields(of: merged, differingFrom: macVersion)))
                }

            case (.deleted, .deleted), (.deleted, .archived), (.same, .archived), (.changed, .archived):
                break    // gone on both sides, or the Mac side cannot be archived
            case (.missing, _), (_, .missing):
                break    // handled above; the Mac side is never "missing"
            }
        }

        // New on the Palm, each decoded once (an unreadable one is logged once)
        var newPalm = palmRecords.values.filter { !usedPalm.contains($0.id) && !$0.isDeleted && !$0.isArchived }
            .sorted { $0.id < $1.id }
            .map { (record: $0, item: palmItem($0, shift: dateShift)) }
        var newMac = items.filter { !usedMac.contains($0.key) }

        if !fast {
            // slow sync: the same item on both sides is one item
            var remaining: [MacSyncItem<Item>] = []
            for macItem in newMac {
                let candidate = macItem.item
                if let i = newPalm.firstIndex(where: { $0.item?.matches(candidate) ?? false }) {
                    let (record, decoded) = newPalm.remove(at: i)
                    let palmVersion = decoded!
                    let secret = record.attributes & PalmDatabase.Record.secret != 0
                    // no common ancestor: the Palm's version stands in for it,
                    // so every difference is a Mac change
                    let (merged, _) = Self.merge(base: palmVersion, palm: palmVersion, mac: candidate, palmID: record.id, mac: macItem.key,
                                                 policy: conflictPolicy, resolve: resolve, conflicts: &plan.conflicts)
                    if merged != palmVersion {
                        writePalm(merged, id: record.id, over: record.data, mac: macItem.key, macOwned: macItem.macOwned, secret: secret)
                    } else {
                        plan.entries.append(.init(palmID: record.id, mac: macItem.key, item: merged, palmRecord: record.data,
                                                  macOwned: macItem.macOwned, secret: secret))
                    }
                    plan.log.append("\(candidate.title ?? "?"): found on both sides, paired")
                } else {
                    remaining.append(macItem)
                }
            }
            newMac = remaining
        }

        for (record, decoded) in newPalm {
            guard let item = decoded else {
                plan.opaque.append(record)    // stays on the Palm untouched
                continue
            }
            plan.entries.append(.init(palmID: record.id, mac: nil, item: item, palmRecord: record.data, macOwned: false,
                                      secret: record.attributes & PalmDatabase.Record.secret != 0))
            plan.macCreates.append(.init(key: nil, item: item, entry: plan.entries.count - 1))
        }
        for macItem in newMac {
            writePalm(macItem.item, id: nil, over: macItem.palmRecord, mac: macItem.key, macOwned: macItem.macOwned)
        }

        if rebase {
            // DateFix changed: every mirrored record still on the Palm is
            // written again in the new years. Ones the Mac already rewrites
            // are, the undecodable ones cannot be.
            let written = Set(plan.palmWrites.map(\.entry))
            var rewritten = 0
            for i in plan.entries.indices where plan.entries[i].palmID != nil && !written.contains(i) && !keptUndecoded.contains(i) {
                let e = plan.entries[i]
                let bytes = e.item.shiftingDates(by: -dateShift).palmBytes(over: e.palmRecord)
                if bytes == e.palmRecord { continue }   // new on the Palm since the change: already in the new years
                plan.entries[i].palmRecord = bytes
                plan.palmWrites.append(.init(id: e.palmID, category: palmCategory(e.item.category), record: bytes, entry: i))
                rewritten += 1
            }
            plan.log.append("DateFix changed on the Palm (shift \(previousDateShift!) → \(dateShift) years): \(rewritten) records rewritten in the new years")
        }

        return plan
    }

    static func fields(of a: Item, differingFrom b: Item) -> [Item.Field] {
        Item.Field.allCases.filter { a.differs(from: b, in: $0) }
    }

    /// Field by field against the base; a field both changed goes to the
    /// policy's side (keep both: the Mac's, and `keptBoth` tells the caller
    /// to duplicate the item). With `.ask`, `resolve` answers per conflict.
    static func merge(base: Item, palm: Item, mac: Item, palmID: UInt32?, mac key: MacKey?,
                      policy: ConflictPolicy = .macWins, resolve: ((Int, SyncConflict) -> ConflictPolicy)? = nil,
                      conflicts: inout [SyncConflict]) -> (Item, keptBoth: Bool) {
        var merged = base
        var keptBoth = false
        for field in Item.Field.allCases {
            let palmChanged = palm.differs(from: base, in: field)
            let macChanged = mac.differs(from: base, in: field)
            switch (palmChanged, macChanged) {
            case (false, false): break
            case (true, false): merged.set(field, from: palm)
            case (false, true): merged.set(field, from: mac)
            case (true, true):
                guard palm.differs(from: mac, in: field) else {
                    merged.set(field, from: mac)   // both changed it the same way
                    break
                }
                var conflict = SyncConflict(palmID: palmID, mac: key, title: mac.title ?? palm.title ?? "",
                                            field: field.rawValue, palmValue: palm.describe(field), macValue: mac.describe(field))
                var choice = policy
                if policy == .ask { choice = resolve?(conflicts.count, conflict) ?? .macWins }
                if choice == .ask { choice = .macWins }
                conflict.resolution = choice
                merged.set(field, from: choice == .palmWins ? palm : mac)
                if choice == .keepBoth { keptBoth = true }
                conflicts.append(conflict)
            }
        }
        return (merged, keptBoth)
    }
}
