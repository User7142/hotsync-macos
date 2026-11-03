import Foundation

/// Brings the Palm's location records up to date with the Mac's tzdata.
/// A Palm OS 5 device ships rules from its own time (a T|X: first Sunday
/// of April to last Sunday of October for all of North America), and it
/// knows nothing of a province that stopped changing clocks. Each location
/// is matched to an IANA zone by its name, the zone's rule for the coming
/// year is read from Foundation, and a record whose rule differs is
/// rewritten; the rest is left alone.
public enum TimeZoneFixups {
    /// What tzdata says a zone does over the coming year.
    public struct Rule: Equatable, Sendable {
        /// Minutes from GMT outside daylight saving time.
        public var offsetMinutes: Int16
        public var observesDST: Bool
        public var dstStart: DSTRule?
        public var dstEnd: DSTRule?
    }

    /// Palm location names that do not spell an IANA zone.
    static let aliases: [String: String] = [
        "beijing": "Asia/Shanghai", "geneva": "Europe/Zurich", "washington dc": "America/New_York",
        "washington d.c.": "America/New_York", "san francisco": "America/Los_Angeles", "seattle": "America/Los_Angeles",
        "dallas": "America/Chicago", "houston": "America/Chicago", "montreal": "America/Toronto",
        "rio de janeiro": "America/Sao_Paulo", "sao paulo": "America/Sao_Paulo", "são paulo": "America/Sao_Paulo",
        "boston": "America/New_York", "miami": "America/New_York", "atlanta": "America/New_York",
        "philadelphia": "America/New_York", "las vegas": "America/Los_Angeles", "san diego": "America/Los_Angeles",
        "calgary": "America/Edmonton", "ottawa": "America/Toronto", "quebec": "America/Toronto",
        "victoria": "America/Vancouver", "saskatoon": "America/Regina", "st. john's": "America/St_Johns",
        "frankfurt": "Europe/Berlin", "munich": "Europe/Berlin", "milan": "Europe/Rome", "barcelona": "Europe/Madrid",
        "manchester": "Europe/London", "edinburgh": "Europe/London", "osaka": "Asia/Tokyo", "mumbai": "Asia/Kolkata",
        "bombay": "Asia/Kolkata", "new delhi": "Asia/Kolkata", "delhi": "Asia/Kolkata", "melbourne": "Australia/Melbourne",
        "brisbane": "Australia/Brisbane", "perth": "Australia/Perth", "adelaide": "Australia/Adelaide",
        "johannesburg": "Africa/Johannesburg", "cairo": "Africa/Cairo", "istanbul": "Europe/Istanbul",
        "tel aviv": "Asia/Jerusalem", "dubai": "Asia/Dubai", "seoul": "Asia/Seoul", "bangkok": "Asia/Bangkok",
        "jakarta": "Asia/Jakarta", "manila": "Asia/Manila", "kuala lumpur": "Asia/Kuala_Lumpur",
        "mexico city": "America/Mexico_City", "buenos aires": "America/Argentina/Buenos_Aires",
        "santiago": "America/Santiago", "lima": "America/Lima", "bogota": "America/Bogota", "caracas": "America/Caracas",
        "anchorage": "America/Anchorage", "phoenix": "America/Phoenix", "salt lake city": "America/Denver",
        "minneapolis": "America/Chicago", "detroit": "America/Detroit", "st. louis": "America/Chicago",
        "new orleans": "America/Chicago", "kansas city": "America/Chicago", "indianapolis": "America/Indiana/Indianapolis",
        // the rest of a T|X's built-in list
        "canberra": "Australia/Sydney", "salzburg": "Europe/Vienna", "ponta delgada": "Atlantic/Azores",
        "dacca": "Asia/Dhaka", "rangoon": "Asia/Yangon", "waitangi": "Pacific/Chatham", "papeete": "Pacific/Tahiti",
        "nice": "Europe/Paris", "tangier": "Africa/Casablanca", "san juan": "America/Puerto_Rico",
        "kingston": "America/Jamaica", "quito": "America/Guayaquil", "kano": "Africa/Lagos", "valetta": "Europe/Malta",
        "new hebrides": "Pacific/Efate", "suva": "Pacific/Fiji", "ankara": "Europe/Istanbul", "kuwait city": "Asia/Kuwait",
        "bali": "Asia/Makassar", "irian jaya": "Asia/Jayapura", "taiohae": "Pacific/Marquesas", "venice": "Europe/Rome",
        "lucilinburhuc": "Europe/Luxembourg", "grytviken": "Atlantic/South_Georgia", "wellington": "Pacific/Auckland",
        "islamabad": "Asia/Karachi", "st. petersburg": "Europe/Moscow", "cape town": "Africa/Johannesburg",
        "nukualofa": "Pacific/Tongatapu", "kiev": "Europe/Kyiv", "glasgow": "Europe/London", "evansville": "America/Chicago",
        "fargo": "America/Chicago", "wichita": "America/Chicago", "cleveland": "America/New_York", "calcutta": "Asia/Kolkata",
        "rawaki": "Pacific/Kanton", "mauritius": "Indian/Mauritius", "barbados": "America/Barbados",
    ]

    /// The IANA zone a Palm location means, by its name; nil when there is
    /// no match or the match sits in a different part of the world than the
    /// record's offset says.
    public static func zone(for location: PalmLocation) -> TimeZone? {
        // "Tehrãn", "São Paulo", "Nouméa": the Palm's spelling, folded to plain letters
        let name = location.name.trimmingCharacters(in: .whitespaces)
        let key = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var zone: TimeZone?
        if let alias = aliases[key] {
            zone = TimeZone(identifier: alias)
        } else {
            let wanted = key.replacingOccurrences(of: " ", with: "_")
            let matches = TimeZone.knownTimeZoneIdentifiers.filter { id in
                id.split(separator: "/").last.map { $0.lowercased() == wanted } ?? false
            }
            // prefer a canonical region over a link ("America/Toronto" over "Canada/Eastern")
            zone = matches.sorted { $0.count < $1.count }.first.flatMap { TimeZone(identifier: $0) }
        }
        guard let zone else { return nil }
        // a city of the same name elsewhere: the offsets would be hours apart
        let standard = Int(zone.secondsFromGMT(for: Date()) / 60) - (zone.isDaylightSavingTime(for: Date()) ? Int(zone.daylightSavingTimeOffset(for: Date()) / 60) : 0)
        guard abs(standard - Int(location.timezone.offsetMinutes)) <= 120 else { return nil }
        return zone
    }

    /// The zone's rule over the 400 days after `now`: no transition, or
    /// transitions that keep the offset (a zone that just went permanent),
    /// means no daylight saving time.
    public static func rule(of zone: TimeZone, now: Date = Date()) -> Rule {
        let horizon = now.addingTimeInterval(400 * 86400)
        var transitions: [Date] = []
        var t = zone.nextDaylightSavingTimeTransition(after: now)
        while let next = t, next < horizon, transitions.count < 4 {
            transitions.append(next)
            t = zone.nextDaylightSavingTimeTransition(after: next)
        }
        func offset(_ date: Date) -> Int { zone.secondsFromGMT(for: date) / 60 }

        var start: (Date, Int)?   // transition into the larger offset, and the standard offset before it
        var end: (Date, Int)?
        for transition in transitions {
            let before = offset(transition.addingTimeInterval(-1))
            let after = offset(transition)
            if after > before, start == nil { start = (transition, before) }
            if after < before, end == nil { end = (transition, after) }
        }
        guard let start, let end else {
            // the offset in force once any pending change is through
            let settled = transitions.last.map { offset($0) } ?? offset(now)
            return Rule(offsetMinutes: Int16(clamping: settled), observesDST: false, dstStart: nil, dstEnd: nil)
        }
        return Rule(offsetMinutes: Int16(clamping: start.1), observesDST: true,
                    dstStart: dstRule(for: start.0, in: zone), dstEnd: dstRule(for: end.0, in: zone))
    }

    /// "the n-th weekday of the month" for the local day a transition falls
    /// on (a second before it, so the day is right on both sides).
    static func dstRule(for transition: Date, in zone: TimeZone) -> DSTRule {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let local = transition.addingTimeInterval(-1)
        let c = calendar.dateComponents([.year, .month, .day, .weekday, .hour], from: local)
        let daysInMonth = calendar.range(of: .day, in: .month, for: local)!.count
        let index = (c.day! - 1) / 7
        // the Palm says "last" rather than "fourth" when it is the last one
        let week = c.day! + 7 > daysInMonth ? 4 : index
        // the fourth byte is not the hour (see fix); 0 until it is understood
        return DSTRule(weekday: UInt8(c.weekday! - 1), week: UInt8(week), month: UInt8(c.month!), unknown: 0)
    }

    /// The record as it should be, with what changed in words; nil when the
    /// zone is unknown or the record is already right.
    public static func fix(_ location: PalmLocation, now: Date = Date()) -> (location: PalmLocation, change: String)? {
        guard let zone = zone(for: location) else { return nil }
        let rule = rule(of: zone, now: now)
        var fixed = location
        fixed.timezone.offsetMinutes = rule.offsetMinutes
        fixed.timezone.observesDST = rule.observesDST
        if rule.observesDST, var start = rule.dstStart, var end = rule.dstEnd {
            // The fourth byte of a rule is not the hour: a T|X writes 1 or 2
            // in the start rule and always 0 in the end rule, and a device
            // shown other values computes wild offsets. Keep what the record
            // had; a record that had no rules gets the device's usual values.
            let had = location.timezone.dstStart.unknown
            start.unknown = location.timezone.observesDST && (1...2).contains(had) ? had : 2
            end.unknown = 0
            fixed.timezone.dstStart = start
            fixed.timezone.dstEnd = end
        } else {
            fixed.timezone.dstStart = DSTRule(weekday: 0, week: 0, month: 0)
            fixed.timezone.dstEnd = DSTRule(weekday: 0, week: 0, month: 0)
        }
        guard fixed.timezone != location.timezone else { return nil }
        return (fixed, "\(location.name): \(describe(location.timezone)) → \(describe(fixed.timezone)) (\(zone.identifier))")
    }

    static func describe(_ tz: PalmTimezone) -> String {
        let hours = Double(tz.offsetMinutes) / 60
        let offset = hours == hours.rounded() ? String(format: "UTC%+.0f", hours) : String(format: "UTC%+.2f", hours)
        guard tz.observesDST else { return "\(offset), no DST" }
        return "\(offset), DST \(describe(tz.dstStart))–\(describe(tz.dstEnd))"
    }

    static func describe(_ rule: DSTRule) -> String {
        let week = ["1st", "2nd", "3rd", "4th", "last"][min(4, Int(rule.week))]
        let day = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][min(6, Int(rule.weekday))]
        let month = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][min(12, Int(rule.month))]
        return "\(week) \(day) \(month)"
    }
}
