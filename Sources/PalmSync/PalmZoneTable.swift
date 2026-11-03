import Foundation

/// The Palm OS 5 time zone table (locLTimeZoneDB, creator locL): one record
/// per zone the Date & Time panel lists, "USA (Eastern)", "Canada
/// (Pacific)", "Pakistan". The Palm regenerates it from the location
/// databases; the sync reads it only to name zones in the log. A record is
/// 54 bytes, the bytes behind the name are uninitialised.
///
///      0  offset    Int16, minutes from GMT
///      2  country   Palm OS country code
///      3  name      NUL-terminated
public struct PalmZoneTable: Equatable, Sendable {
    public struct Zone: Equatable, Hashable, Sendable {
        public var offsetMinutes: Int16
        public var country: UInt8
        public var name: String
    }

    public var zones: [Zone]

    public init(zones: [Zone]) {
        self.zones = zones
    }

    public init(records: [Data]) {
        zones = records.compactMap { data in
            guard data.count >= 5 else { return nil }
            var r = ByteReader(data)
            guard let offset = try? r.u16(), let country = try? r.u8(), let name = try? r.cString() else { return nil }
            return Zone(offsetMinutes: Int16(bitPattern: offset), country: country, name: name)
        }
    }

    /// The zone name the picker shows for a location: its country's zone at
    /// its offset, else the country's only zone, else nil.
    public func name(country: UInt8, offsetMinutes: Int16) -> String? {
        if let zone = zones.first(where: { $0.country == country && $0.offsetMinutes == offsetMinutes }) { return zone.name }
        let ofCountry = zones.filter { $0.country == country }
        return ofCountry.count == 1 ? ofCountry[0].name : nil
    }
}

extension TimeZoneFixups {
    /// The Date & Time picker sorts its list by zone name, then city, and
    /// assumes the default location database is stored in that order: it
    /// opens the n-th record for the n-th row. Countries are contiguous
    /// blocks in the database, so when a fix changes a location's zone
    /// (Vancouver from "Canada (Pacific)" to "Canada (Mountain)"), its
    /// country's block is re-sorted the picker's way. Blocks with a zone
    /// the table cannot name are left alone.
    public static func reorderWithinCountries<T>(_ records: [T], location: (T) -> PalmLocation?,
                                                 zones: PalmZoneTable) -> [T] {
        var result: [T] = []
        var block: [(T, PalmLocation)] = []
        func flush() {
            defer { block = [] }
            guard block.count > 1 else { result += block.map(\.0); return }
            let keys: [(String, String)?] = block.map { _, l in
                guard let zone = zones.name(country: l.timezone.country, offsetMinutes: l.timezone.offsetMinutes) else { return nil }
                return (zone.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil),
                        l.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil))
            }
            guard keys.allSatisfy({ $0 != nil }) else { result += block.map(\.0); return }
            let order = block.indices.sorted { a, b in
                let ka = keys[a]!, kb = keys[b]!
                return ka == kb ? a < b : ka < kb
            }
            result += order.map { block[$0].0 }
        }
        for record in records {
            guard let l = location(record) else { flush(); result.append(record); continue }
            if let last = block.last, last.1.timezone.country != l.timezone.country { flush() }
            block.append((record, l))
        }
        flush()
        return result
    }
}
