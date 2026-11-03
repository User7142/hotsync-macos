import Foundation

/// DateFix (a Palm-side patch by the hotsync-macos author) moves Palm OS's
/// date epoch from 1904 to a later start year, so a Palm keeps a working
/// calendar after 2031. Its stored dates and its clock are then shifted by
/// `startYear - 1904` years, and a HotSync sees the shifted values.
///
/// The shift is applied to decoded values, never to record bytes: a Palm
/// record can only hold years 1904…2031, so a real year like 2040 exists
/// only in memory (as a `PalmDate` with that year) and is written back to
/// the Palm as 2012. The sync engine shifts items it reads from the Palm
/// by `+years` and items it writes by `-years`; the one-way builders encode
/// with `-years`.
public enum DateFix {
    /// DateFix moves the clock by whole 4-year blocks (1461 days each), so
    /// leap years stay aligned; start years are 1904, 1908, … 1972.
    public static func offsetDays(startYear: Int) -> Int {
        max(0, (startYear - 1904) / 4) * 1461
    }

    /// A date shifted by `years`; one that would fall before the Palm's
    /// window becomes the window's first day, as DateFix itself does.
    public static func shift(_ date: PalmDate, years: Int) -> PalmDate {
        var d = date
        d.year += years
        if d.year < 1904 { return PalmDate(year: 1904, month: 1, day: 1) }
        return d
    }

    public static func shift(_ event: CalendarEvent, years: Int) -> CalendarEvent {
        guard years != 0 else { return event }
        var e = event
        e.date = shift(e.date, years: years)
        if let end = e.repeatRule?.endDate { e.repeatRule?.endDate = shift(end, years: years) }
        e.exceptions = e.exceptions.map { shift($0, years: years) }
        return e
    }

    public static func shift(_ task: PalmTask, years: Int) -> PalmTask {
        guard years != 0 else { return task }
        var t = task
        t.dueDate = t.dueDate.map { shift($0, years: years) }
        t.completedDate = t.completedDate.map { shift($0, years: years) }
        if let (start, rule) = t.repeatRule {
            var r = rule
            r.endDate = r.endDate.map { shift($0, years: years) }
            t.repeatRule = (shift(start, years: years), r)
        }
        return t
    }

    /// Birthday and the anniversary blob (a dirty word, then the packed date).
    public static func shift(_ contact: Contact, years: Int) -> Contact {
        guard years != 0 else { return contact }
        var c = contact
        if let birthday = c.birthday { c.birthday?.date = shift(birthday.date, years: years) }
        c.blobs = c.blobs.map { blob in
            guard blob.type == Contact.anniversaryBlobType, blob.data.count >= 4 else { return blob }
            var bytes = [UInt8](blob.data)
            let packed = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
            guard packed != PalmDate.none else { return blob }
            let moved = shift(PalmDate(packed: packed), years: years).packed
            bytes[2] = UInt8(moved >> 8)
            bytes[3] = UInt8(moved & 0xFF)
            return PalmBlob(type: blob.type, data: Data(bytes))
        }
        return c
    }

    /// A date DateFix could not represent (before its start year) is stored
    /// as the window's first day. Read back, that is no edit: where the
    /// mirror knows the real date and it lies before the window, the item
    /// gets it back, so the clamp never travels to the Mac. Contacts
    /// birthdays are the only such dates in practice.
    public static func unclamp(_ item: SyncedContact, startYear: Int, base: SyncedContact) -> SyncedContact {
        guard let real = base.birthday, real.year < startYear,
              item.birthday == PalmDate(year: startYear, month: 1, day: 1) else { return item }
        var fixed = item
        fixed.birthday = real
        return fixed
    }
}
