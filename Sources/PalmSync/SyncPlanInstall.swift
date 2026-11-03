import Foundation

extension SyncPlan where Item == SyncedEvent {
    /// The Palm's side of the plan as a whole CalendarDB-PDat to install,
    /// records sorted by date and time as the Calendar expects.
    ///
    /// Returns the database and, per entry index, the ID a new record got,
    /// for `mirror(after:palmIDs:macKeys:)`.
    public func palmDatabase(categories existing: CategoryAppInfo, startOfWeek: UInt8 = 0)
        -> (database: PalmDatabase, palmIDs: [Int: UInt32], categories: CategoryAppInfo) {
        let (records, palmIDs, categories, nextID) = palmRecords(categories: existing) { a, b in
            if a.date != b.date { return a.date < b.date }
            switch (a.time?.start, b.time?.start) {
            case (nil, nil): return false
            case (nil, _): return true
            case (_, nil): return false
            case let (x?, y?): return x < y
            }
        }
        var db = PalmDatabase(name: CalendarBuilder.databaseName, type: "DATA", creator: "PDat", attributes: 0, version: 1,
                              appInfo: CalendarAppInfo(categories: categories, startOfWeek: startOfWeek).encode())
        db.records = records
        db.uniqueIDSeed = nextID
        return (db, palmIDs, categories)
    }
}
