import Foundation

/// A record of the Palm OS 5 Contacts application (database
/// ContactsDB-PAdd, creator PAdd), the Garnet successor of the Address Book.
///
/// Layout (big-endian):
///
///      0  labels[8]        nibbles: showPhone, phone7, phone6 … phone1,
///                          (unused), address3, address2, address1,
///                          (unused byte), IM2, IM1
///      8  contents1        UInt32, bit i = field i (0-27) is present
///     12  contents2        UInt32, bits 0-10 = fields 28-38 present,
///                          0x1800 birthday, 0x2000 birthday reminder
///     16  companyOffset    from this byte to the company field, 0 if none
///     17  fields           NUL-terminated, in field order, present ones only
///         birthday         date[2] pad[1] advanceUnits[1]        if 0x1800
///         reminder         advance[1]                             if 0x2000
///         blobs            type[4] length[2] data                 to the end
public struct Contact: Equatable, Sendable {
    /// The 39 text fields, in record order.
    public enum Field: Int, CaseIterable, Sendable {
        case lastName, firstName, company, title
        case phone1, phone2, phone3, phone4, phone5, phone6, phone7
        case im1, im2, website
        case custom1, custom2, custom3, custom4, custom5, custom6, custom7, custom8, custom9
        case address1, city1, state1, zip1, country1
        case address2, city2, state2, zip2, country2
        case address3, city3, state3, zip3, country3
        case note
    }

    public struct Birthday: Equatable, Sendable {
        public var date: PalmDate
        /// Days (or whatever `advanceUnits` says) before the birthday to
        /// remind; nil: no reminder.
        public var reminderAdvance: UInt8?
        /// Same values as CalendarEvent.AlarmUnit: 0 minutes, 1 hours, 2 days.
        public var advanceUnits: UInt8

        public init(date: PalmDate, reminderAdvance: UInt8? = nil, advanceUnits: UInt8 = 2) {
            self.date = date
            self.reminderAdvance = reminderAdvance
            self.advanceUnits = advanceUnits
        }
    }

    public static let fieldCount = 39
    public static let pictureBlobType = "Bd00"
    public static let anniversaryBlobType = "Bd01"
    static let headerSize = 17
    static let birthdayFlags: UInt32 = 0x1800
    static let reminderFlag: UInt32 = 0x2000

    /// The eight label bytes as stored; the accessors below read and write
    /// the nibbles that have a meaning.
    public var labelBytes: [UInt8]
    /// Text of each field, nil when the field is absent.
    public var fields: [String?]
    public var birthday: Birthday?
    public var blobs: [PalmBlob]

    public init(fields: [Field: String] = [:], birthday: Birthday? = nil, blobs: [PalmBlob] = []) {
        labelBytes = [UInt8](repeating: 0, count: 8)
        self.fields = [String?](repeating: nil, count: Self.fieldCount)
        for (field, text) in fields { self.fields[field.rawValue] = text }
        self.birthday = birthday
        self.blobs = blobs
    }

    public subscript(field: Field) -> String? {
        get { fields[field.rawValue] }
        set { fields[field.rawValue] = newValue }
    }

    // MARK: Labels

    private func nibble(_ byte: Int, high: Bool) -> UInt8 {
        high ? labelBytes[byte] >> 4 : labelBytes[byte] & 0x0F
    }

    private mutating func setNibble(_ byte: Int, high: Bool, _ value: UInt8) {
        let v = value & 0x0F
        labelBytes[byte] = high ? (labelBytes[byte] & 0x0F) | v << 4 : (labelBytes[byte] & 0xF0) | v
    }

    /// Which phone (0-6) the list view shows.
    public var showPhone: UInt8 {
        get { nibble(0, high: true) }
        set { setNibble(0, high: true, newValue) }
    }

    /// The label index (into the AppInfo phone labels: Work, Home, Fax,
    /// Other, E-mail, Main, Pager, Mobile) of phone 0-6.
    public func phoneLabel(_ i: Int) -> UInt8 {
        // phone1 is the low nibble of byte 3, phone7 the low nibble of byte 0
        let byte = 3 - i / 2
        return nibble(byte, high: i % 2 == 1)
    }

    public mutating func setPhoneLabel(_ i: Int, _ label: UInt8) {
        setNibble(3 - i / 2, high: i % 2 == 1, label)
    }

    /// The label index (Home, Work, Other) of address 0-2.
    public func addressLabel(_ i: Int) -> UInt8 {
        switch i {
        case 0: return nibble(5, high: false)
        case 1: return nibble(5, high: true)
        default: return nibble(4, high: false)
        }
    }

    public mutating func setAddressLabel(_ i: Int, _ label: UInt8) {
        switch i {
        case 0: setNibble(5, high: false, label)
        case 1: setNibble(5, high: true, label)
        default: setNibble(4, high: false, label)
        }
    }

    /// The service (AIM, MSN, Yahoo, ICQ, Other) of IM 0-1.
    public func imLabel(_ i: Int) -> UInt8 {
        nibble(7, high: i == 1)
    }

    public mutating func setIMLabel(_ i: Int, _ label: UInt8) {
        setNibble(7, high: i == 1, label)
    }

    // MARK: Decoding

    public init(data: Data) throws {
        var r = ByteReader(data)
        labelBytes = Array(try r.slice(8))
        let contents1 = try r.u32()
        let contents2 = try r.u32()
        _ = try r.u8()  // companyOffset, derived from the fields

        fields = []
        for i in 0..<Self.fieldCount {
            let present = i < 28 ? contents1 & (1 << UInt32(i)) != 0
                                 : contents2 & (1 << UInt32(i - 28)) != 0
            fields.append(present ? try r.cString() : nil)
        }

        if contents2 & Self.birthdayFlags != 0 {
            let date = PalmDate(packed: try r.u16())
            _ = try r.u8()  // padding
            let units = try r.u8()
            let advance: UInt8? = contents2 & Self.reminderFlag != 0 ? try r.u8() : nil
            birthday = Birthday(date: date, reminderAdvance: advance, advanceUnits: units)
        } else {
            birthday = nil
        }

        blobs = try PalmBlob.readAll(&r)
    }

    // MARK: Encoding

    public func encode() -> Data {
        var w = ByteWriter()
        w.append(labelBytes.prefix(8))
        w.zeros(8 - min(8, labelBytes.count))
        var contents1: UInt32 = 0
        var contents2: UInt32 = 0
        for (i, text) in fields.prefix(Self.fieldCount).enumerated() where text != nil {
            if i < 28 { contents1 |= 1 << UInt32(i) } else { contents2 |= 1 << UInt32(i - 28) }
        }
        if let birthday {
            contents2 |= Self.birthdayFlags
            if birthday.reminderAdvance != nil { contents2 |= Self.reminderFlag }
        }
        w.u32(contents1)
        w.u32(contents2)
        w.u8(companyOffset)

        for text in fields.prefix(Self.fieldCount) {
            if let text { w.cString(text) }
        }
        if let birthday {
            w.u16(birthday.date.packed)
            w.u8(0)
            w.u8(birthday.advanceUnits)
            if let advance = birthday.reminderAdvance { w.u8(advance) }
        }
        for blob in blobs { blob.write(&w) }
        return w.data
    }

    /// Distance from the companyOffset byte to the company field: one for
    /// the byte itself plus the names in front of the company.
    var companyOffset: UInt8 {
        guard self[.company] != nil else { return 0 }
        var offset = 1
        for field in [Field.lastName, .firstName] {
            if let text = self[field] { offset += PalmText.bytes(text).count + 1 }
        }
        return UInt8(clamping: offset)
    }
}

/// The AppInfo block of ContactsDB-PAdd: the category block, 26 bytes
/// nobody has documented, the field and menu labels (49 in version 1.0,
/// 53 in 1.1, 16 bytes each), the country, and the sort order.
///
/// Label indices the records refer to: phone labels are labels 4-10 plus
/// 40 (Mobile), custom field names 14-22, address labels 46-48 (via the
/// address nibbles), IM services 41-45.
public struct ContactAppInfo: Equatable, Sendable {
    public var categories: CategoryAppInfo
    public var internalBytes: Data
    public var labels: [String]
    /// Palm OS country code: Canada 4, France 7, Germany 8, UK 22, US 23 …
    public var country: UInt8
    public var countryPadding: UInt8
    public var sortByCompany: Bool
    public var sortPadding: UInt8

    public static let labelWidth = 16
    public static let labelCountV10 = 49
    public static let labelCountV11 = 53

    public static func size(labels: Int) -> Int {
        CategoryAppInfo.size + 26 + labels * labelWidth + 4
    }

    public init(categories: CategoryAppInfo = CategoryAppInfo(), labels: [String], country: UInt8 = 0,
                sortByCompany: Bool = false) {
        self.categories = categories
        internalBytes = Data(count: 26)
        self.labels = labels
        self.country = country
        countryPadding = 0
        self.sortByCompany = sortByCompany
        sortPadding = 0
    }

    public init(data: Data) throws {
        let count: Int
        switch data.count {
        case Self.size(labels: Self.labelCountV10): count = Self.labelCountV10
        case Self.size(labels: Self.labelCountV11): count = Self.labelCountV11
        default: throw PalmFormatError.invalidValue(field: "appInfo.size", value: data.count)
        }
        var r = ByteReader(data)
        categories = try CategoryAppInfo(bytes: try r.slice(CategoryAppInfo.size))
        internalBytes = Data(try r.slice(26))
        labels = try (0..<count).map { _ in try r.fixedString(Self.labelWidth) }
        country = try r.u8()
        countryPadding = try r.u8()
        sortByCompany = try r.u8() != 0
        sortPadding = try r.u8()
    }

    public func encode() -> Data {
        var w = ByteWriter()
        w.append(categories.encode())
        w.append(internalBytes.prefix(26))
        w.zeros(26 - min(26, internalBytes.count))
        for label in labels { w.fixedString(label, width: Self.labelWidth) }
        w.u8(country)
        w.u8(countryPadding)
        w.u8(sortByCompany ? 1 : 0)
        w.u8(sortPadding)
        return w.data
    }

    /// The eight phone labels a record's phone nibbles index.
    public var phoneLabels: [String] {
        guard labels.count > 40 else { return [] }
        return Array(labels[4...10]) + [labels[40]]
    }
}
