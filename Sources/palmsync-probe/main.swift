// palmsync-probe: the live check of the record bridge (Phase 3's exit gate).
// Waits for a Palm on the port, reads one database through hotsync-session,
// runs every record through the codec and back, and says what it found.
// Writes nothing unless asked.
//
//   palmsync-probe [--port usb:] [--db CalendarDB-PDat] [--tool PATH] [--dump DIR] [--write-test]
//
// --dump DIR    saves the database as DIR/<name>.pdb (a fixture from a real device)
// --write-test  on CalendarDB-PDat: writes a test event, reads it back, deletes it
//
// Quit HotSync.app first: it holds the USB port. --tool defaults to the
// hotsync-session of the HotSync.app that Scripts/build.sh builds.

import Foundation
import HotSyncCore
import PalmSync

var port = "usb:"
var dbName = "CalendarDB-PDat"
var tool: String?
var dump: String?
var writeTest = false
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--port": port = args.removeFirst()
    case "--db": dbName = args.removeFirst()
    case "--tool": tool = args.removeFirst()
    case "--dump": dump = args.removeFirst()
    case "--write-test": writeTest = true
    default:
        print("usage: palmsync-probe [--port usb:] [--db NAME] [--tool PATH] [--dump DIR] [--write-test]")
        exit(2)
    }
}

let toolURL = URL(fileURLWithPath: tool ?? "HotSync.app/Contents/Resources/hotsync-session")
guard FileManager.default.isExecutableFile(atPath: toolURL.path) else {
    print("palmsync-probe: no hotsync-session at \(toolURL.path); build with Scripts/build.sh or pass --tool")
    exit(1)
}

let transport = ProcessTransport(tool: toolURL, port: port) { line in
    FileHandle.standardError.write("  [session] \(line)\n".data(using: .utf8)!)
}
let bridge = RecordBridge(transport: transport)
try transport.start()
print("waiting for a Palm on \(port): press HotSync")

func run(dbName: String, dump: String?, writeTest: Bool) async throws {
    let palm = try await bridge.waitForPalm()
    print("connected: \(palm.user.name) (ID \(palm.user.userId)), ROM 0x\(String(palm.romVersion, radix: 16))")
    print("sync info: last PC \(palm.lastSyncPC), last sync \(palm.lastSyncDate.map { "\($0)" } ?? "never")")

    let count = try await bridge.openDatabase(dbName, writable: writeTest)
    print("\(dbName): \(count) records")
    let appInfo = try await bridge.readAppInfo()
    print("AppInfo: \(appInfo.count) bytes")

    var categories: [String] = []
    if dbName == "CalendarDB-PDat", let info = try? CalendarAppInfo(data: appInfo) {
        categories = info.categories.names
        print("  categories: \(info.categories.named.map { "\($0.name) (\($0.id))" }.joined(separator: ", ")); week starts \(info.startOfWeek == 0 ? "Sunday" : "Monday")")
        print("  internal: \(info.internalBytes.map { String(format: "%02x", $0) }.joined(separator: " "))")
    } else if dbName == "ContactsDB-PAdd", let info = try? ContactAppInfo(data: appInfo) {
        categories = info.categories.names
        print("  categories: \(info.categories.named.map(\.name).joined(separator: ", ")); \(info.labels.count) labels; country \(info.country)")
    } else if appInfo.count >= CategoryAppInfo.size, let cats = try? CategoryAppInfo(bytes: [UInt8](appInfo)[...]) {
        categories = cats.names
        print("  categories: \(cats.named.map(\.name).joined(separator: ", ")); \(appInfo.count - CategoryAppInfo.size) app-specific bytes")
    }

    let records = try await bridge.readAllRecords()
    print("read \(records.count) records")

    var ok = 0, failed = 0, deleted = 0
    for record in records {
        if record.isDeleted { deleted += 1; continue }
        let roundTrip: Data?
        switch dbName {
        case "CalendarDB-PDat": roundTrip = (try? CalendarEvent(data: record.data))?.encode()
        case "ContactsDB-PAdd": roundTrip = (try? Contact(data: record.data))?.encode()
        case "locLDefLocationDB", "locLCusLocationDB": roundTrip = (try? PalmLocation(data: record.data))?.encode()
        default: roundTrip = record.data
        }
        if roundTrip == record.data {
            ok += 1
        } else {
            failed += 1
            print("  record \(record.id) (\(record.data.count) bytes, category \(record.category)): \(roundTrip == nil ? "does not decode" : "re-encodes differently")")
            print("    \(record.data.prefix(48).map { String(format: "%02x", $0) }.joined(separator: " "))")
        }
    }
    print("codec round trip: \(ok) identical, \(failed) different, \(deleted) deleted")
    if dbName == "CalendarDB-PDat" {
        for record in records.prefix(5) where !record.isDeleted {
            if let e = try? CalendarEvent(data: record.data) {
                let cat = record.category < categories.count ? categories[record.category] : "?"
                print("  \(e.date.year)-\(e.date.month)-\(e.date.day) \(e.time.map { "\($0.start.hour):\($0.start.minute)" } ?? "all day") [\(cat)] \(e.title ?? "") \(e.timezone.map { "tz \($0.name) \($0.offsetMinutes)" } ?? "")")
            }
        }
    }

    if let dump {
        var db = PalmDatabase(name: dbName, type: "DATA", creator: "    ", appInfo: appInfo)
        db.records = records.map { PalmDatabase.Record(attributes: $0.attributes, category: $0.category, uniqueID: $0.id, data: $0.data) }
        let url = URL(fileURLWithPath: dump).appendingPathComponent("\(dbName).pdb")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try db.encode().write(to: url)
        print("dumped to \(url.path) (type/creator not read: set from the backup)")
    }

    if writeTest && dbName == "CalendarDB-PDat" {
        let test = CalendarEvent(date: PalmDate(year: 2026, month: 12, day: 31),
                                 time: .init(start: PalmTime(hour: 23, minute: 0), end: PalmTime(hour: 23, minute: 30)),
                                 title: "PalmSync probe", note: "written and deleted by palmsync-probe")
        let id = try await bridge.writeRecord(id: nil, attributes: 0x40, category: 0, data: test.encode())
        print("write test: record \(id) written")
        let back = try await bridge.readRecord(id: id)
        print("  read back: \(back.data == test.encode() ? "identical" : "DIFFERENT"), attrs 0x\(String(back.attributes, radix: 16))")
        let modified = try await bridge.readModifiedRecords()
        print("  readmodified: \(modified.count) records, test record \(modified.contains { $0.id == id } ? "among them" : "MISSING")")
        try await bridge.deleteRecord(id: id)
        print("  deleted")
    }

    try await bridge.closeDatabase()
    try await bridge.log("palmsync-probe read \(dbName)")
    try await bridge.end()
    print("done; \(await bridge.takeSidelined().count) other events")
}

do {
    try await run(dbName: dbName, dump: dump, writeTest: writeTest)
} catch {
    print("palmsync-probe: \(error)")
    transport.kill()
    exit(1)
}
