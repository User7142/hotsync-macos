// palmsync-calendar: the Mac side of the one-way calendar sync (Phase 2) as
// a command-line tool; the app does the same from its Sync section. Reads
// the chosen Calendar.app calendars for a window of days and writes a
// CalendarDB-PDat.pdb into a device's Install/ folder; the next HotSync
// installs it and the Palm's Calendar shows the Mac's.
//
//   palmsync-calendar --list
//   palmsync-calendar --calendar Work --calendar "Family=iC Family" --device "Zoë Leto" [--back 90] [--ahead 365]
//   palmsync-calendar --calendar Work --out /tmp/CalendarDB-PDat.pdb
//   palmsync-calendar --calendar Work --dry-run
//
// --calendar takes a calendar title (or identifier from --list), with an
// optional "=Category" naming the Palm category; calendars listed first
// win when the same invite is in several. The Palm's copy of the database
// is replaced whole: edits made on the Palm are lost. Phase 4 changes that.

import EventKit
import Foundation
import PalmSync
import PalmSyncMac

struct Arguments {
    var list = false
    var dryRun = false
    var calendars: [(name: String, category: String?)] = []
    var device: String?
    var out: String?
    var back = 90
    var ahead = 365

    init(_ args: [String]) throws {
        var i = 0
        func value(_ flag: String) throws -> String {
            i += 1
            guard i < args.count else { throw Usage("\(flag) needs a value") }
            return args[i]
        }
        while i < args.count {
            switch args[i] {
            case "--list": list = true
            case "--dry-run": dryRun = true
            case "--calendar":
                let spec = try value("--calendar")
                if let eq = spec.firstIndex(of: "=") {
                    calendars.append((String(spec[..<eq]), String(spec[spec.index(after: eq)...])))
                } else {
                    calendars.append((spec, nil))
                }
            case "--device": device = try value("--device")
            case "--out": out = try value("--out")
            case "--back": back = Int(try value("--back")) ?? -1
            case "--ahead": ahead = Int(try value("--ahead")) ?? -1
            case "-h", "--help": throw Usage(nil)
            default: throw Usage("unknown option \(args[i])")
            }
            i += 1
        }
        guard back >= 0, ahead >= 0 else { throw Usage("--back and --ahead take a number of days") }
        if !list && calendars.isEmpty { throw Usage("choose calendars with --calendar (see --list)") }
        if !list && !dryRun && device == nil && out == nil {
            throw Usage("say where the database goes: --device NAME or --out PATH (or --dry-run)")
        }
    }

    var outputURL: URL? {
        if let out { return URL(fileURLWithPath: out) }
        guard let device else { return nil }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("HotSync").appendingPathComponent(device)
            .appendingPathComponent("Install").appendingPathComponent("CalendarDB-PDat.pdb")
    }
}

struct Usage: Error {
    let message: String?
    init(_ message: String?) { self.message = message }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("palmsync-calendar: \(message)\n".data(using: .utf8)!)
    exit(1)
}

func describe(_ rule: CalendarEvent.Repeat, exceptions: Int) -> String {
    var text = " (repeats "
    switch rule.type {
    case .daily: text += rule.frequency == 1 ? "daily" : "every \(rule.frequency) days"
    case .weekly:
        let names = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
        let days = (0..<7).filter { rule.weekdays.rawValue & (1 << $0) != 0 }.map { names[$0] }
        text += (rule.frequency == 1 ? "weekly" : "every \(rule.frequency) weeks") + " on " + days.joined(separator: " ")
    case .monthlyByDate: text += rule.frequency == 1 ? "monthly" : "every \(rule.frequency) months"
    case .monthlyByDay:
        let week = ["1st", "2nd", "3rd", "4th", "last"][min(4, Int(rule.on) / 7)]
        let day = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][Int(rule.on) % 7]
        text += "monthly on the \(week) \(day)"
    case .yearly: text += rule.frequency == 1 ? "yearly" : "every \(rule.frequency) years"
    }
    if let end = rule.endDate { text += String(format: " until %d-%02d-%02d", end.year, end.month, end.day) }
    if exceptions > 0 { text += ", \(exceptions) exception\(exceptions == 1 ? "" : "s")" }
    return text + ")"
}

// MARK: - Main

let arguments: Arguments
do {
    arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
} catch let usage as Usage {
    if let message = usage.message { FileHandle.standardError.write("palmsync-calendar: \(message)\n".data(using: .utf8)!) }
    print("""
    usage: palmsync-calendar --list
           palmsync-calendar --calendar NAME[=Category] ... (--device NAME | --out PATH | --dry-run) [--back DAYS] [--ahead DAYS]
    """)
    exit(usage.message == nil ? 0 : 2)
}

let source = CalendarSource()
let granted = try await source.requestAccess()
guard granted else {
    let status: String
    switch source.accessStatus {
    case .notDetermined: status = "not determined (macOS showed no prompt)"
    case .denied: status = "denied"
    case .restricted: status = "restricted"
    case .writeOnly: status = "add-only; full access is needed"
    case .fullAccess: status = "full access, yet the request failed"
    @unknown default: status = "unknown"
    }
    fail("no access to Calendar (\(status)): allow it in System Settings > Privacy & Security > Calendars")
}

let all = source.calendars()

if arguments.list {
    var lastSource = ""
    for cal in all {
        if cal.source != lastSource { print("\(cal.source):"); lastSource = cal.source }
        let kind = cal.isSubscribed ? "subscribed" : (cal.isReadOnly ? "read-only" : "")
        print("  \(cal.title.padding(toLength: 28, withPad: " ", startingAt: 0)) \(cal.id) \(kind)")
    }
    exit(0)
}

var settings = CalendarSyncSettings(enabled: true, daysBack: arguments.back, daysAhead: arguments.ahead)
for spec in arguments.calendars {
    let matches = all.filter { $0.id == spec.name || $0.title == spec.name }
    guard !matches.isEmpty else { fail("no calendar named \"\(spec.name)\" (see --list)") }
    guard matches.count == 1 else {
        fail("\"\(spec.name)\" names \(matches.count) calendars; use the identifier from --list: "
             + matches.map { "\($0.id) (\($0.source))" }.joined(separator: ", "))
    }
    settings.calendars.append(.init(id: matches[0].id, title: matches[0].title, category: spec.category))
}

let run: CalendarSyncRun
do {
    run = try CalendarSyncRun(settings: settings, source: source)
} catch CalendarSyncRun.Failure.doesNotReadBack {
    fail("the built database does not read back as built")
}
let report = run.report

let tzdata = (try? String(contentsOfFile: "/usr/share/zoneinfo/+VERSION", encoding: .utf8))?
    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
let dayFormat = DateFormatter()
dayFormat.dateFormat = "yyyy-MM-dd"
print("window:     \(dayFormat.string(from: run.windowStart)) to \(dayFormat.string(from: run.windowEnd)), home zone \(TimeZone.current.identifier), tzdata \(tzdata)")
print("calendars:  \(settings.calendars.map(\.title).joined(separator: ", "))")
print("categories: \(report.categories.joined(separator: ", "))")
print("records:    \(report.records) (\(run.occurrences) occurrences on the Mac: \(report.seriesMapped) series as repeat rules with \(report.exceptions) exceptions, \(report.seriesExpanded) series expanded, \(report.detachedOccurrences) edited occurrences, \(report.duplicatesDropped) duplicates dropped)")
for warning in report.warnings { print("warning:    \(warning)") }

if arguments.dryRun {
    print("")
    for record in run.database.records.prefix(40) {
        let event = try CalendarEvent(data: record.data)
        let time = event.time.map { String(format: "%02d:%02d-%02d:%02d", $0.start.hour, $0.start.minute, $0.end.hour, $0.end.minute) } ?? "all day    "
        let rule = event.repeatRule.map { describe($0, exceptions: event.exceptions.count) } ?? ""
        print("  \(event.date.year)-\(String(format: "%02d-%02d", event.date.month, event.date.day)) \(time)  [\(report.categories[record.category])] \(event.title ?? "")\(rule)")
    }
    if run.database.records.count > 40 { print("  … \(run.database.records.count - 40) more") }
    exit(0)
}

let url = arguments.outputURL!
let bytes = try run.write(to: url)
print("wrote:      \(url.path) (\(bytes) bytes, verified)")
