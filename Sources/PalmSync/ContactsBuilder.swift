import Foundation

/// A contact as the Mac has it, without Contacts.framework: the adapter
/// fills these from CNContact, the builder packs them into Palm records,
/// the tests make them up. Multi-value fields keep their order; the
/// builder decides what fits into the Palm's slots.
public struct MacContact: Equatable, Sendable {
    public struct Labeled: Equatable, Sendable {
        /// A neutral label: "mobile", "home", "work", "main", "fax",
        /// "pager", "other" for phones; the service name for IM; anything
        /// for the rest.
        public var label: String
        public var value: String
        public init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    public struct Address: Equatable, Sendable {
        /// "home", "work" or "other"
        public var label: String
        public var street: String
        public var city: String
        public var state: String
        public var postalCode: String
        public var country: String
        public init(label: String, street: String = "", city: String = "", state: String = "",
                    postalCode: String = "", country: String = "") {
            self.label = label
            self.street = street
            self.city = city
            self.state = state
            self.postalCode = postalCode
            self.country = country
        }
    }

    public var id: String
    public var containerID: String
    /// Names of the groups the contact is in, in the account's order.
    public var groups: [String]
    public var firstName: String
    public var middleName: String
    public var lastName: String
    public var company: String
    public var jobTitle: String
    public var phones: [Labeled]
    public var emails: [Labeled]
    public var addresses: [Address]
    public var instantMessages: [Labeled]
    public var urls: [String]
    /// Only with a year: the Palm cannot store a birthday without one.
    public var birthday: PalmDate?
    public var note: String?

    public init(id: String, containerID: String, groups: [String] = [], firstName: String = "",
                middleName: String = "", lastName: String = "", company: String = "", jobTitle: String = "",
                phones: [Labeled] = [], emails: [Labeled] = [], addresses: [Address] = [],
                instantMessages: [Labeled] = [], urls: [String] = [], birthday: PalmDate? = nil, note: String? = nil) {
        self.id = id
        self.containerID = containerID
        self.groups = groups
        self.firstName = firstName
        self.middleName = middleName
        self.lastName = lastName
        self.company = company
        self.jobTitle = jobTitle
        self.phones = phones
        self.emails = emails
        self.addresses = addresses
        self.instantMessages = instantMessages
        self.urls = urls
        self.birthday = birthday
        self.note = note
    }

    public var isEmpty: Bool {
        firstName.isEmpty && lastName.isEmpty && company.isEmpty && phones.isEmpty && emails.isEmpty
    }
}

/// Builds a complete ContactsDB-PAdd from the Mac's contacts: the one-way
/// sync where the database is installed whole. The Mac's fields are
/// unbounded, the Palm's are slots, so this is where the choosing happens:
///
/// - 7 phone slots take phones and e-mails together, phones first in the
///   order mobile, main, home, work, other, fax, pager; the list view shows
///   the first mobile number, else the first slot.
/// - 3 address slots, labelled home, work or other.
/// - 2 IM slots (AIM, MSN, Yahoo, ICQ, other), the first web address.
/// - The first group a contact is in becomes its category; past 15 they
///   fold into "Other". Contacts in no group are "Unfiled".
/// - The same person in several accounts (same name) is kept from the
///   first account in priority order.
/// Everything that does not fit stays on the Mac and is never touched.
public struct ContactsBuilder {
    public struct MacContainer: Equatable, Sendable {
        public var id: String
        public var title: String
        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    public struct Options: Sendable {
        /// Accounts in priority order: the first wins a duplicate.
        public var containers: [MacContainer]
        /// DateFix on the Palm: years taken away from the birthday on encoding.
        public var dateShift: Int
        public init(containers: [MacContainer], dateShift: Int = 0) {
            self.containers = containers
            self.dateShift = dateShift
        }
    }

    public struct Report: Equatable, Sendable {
        public var records = 0
        public var duplicatesDropped = 0
        public var phonesDropped = 0
        public var addressesDropped = 0
        public var emptySkipped = 0
        public var categories: [String] = []
        public var warnings: [String] = []
    }

    public static let databaseName = "ContactsDB-PAdd"
    public static let maxCategories = 16
    public static let overflowCategory = "Other"

    /// The Palm's phone labels, by index as the record's nibbles name them.
    public enum PhoneLabel: UInt8 { case work = 0, home, fax, other, email, main, pager, mobile }
    /// Address labels: home, work, other.
    public enum AddressLabel: UInt8 { case home = 0, work, other }
    /// IM services as the Palm lists them.
    public enum IMLabel: UInt8 { case aim = 0, msn, yahoo, icq, other }

    /// The labels of a Palm OS 5 Contacts database (version 1.1), in the
    /// order the records refer to them.
    public static let standardLabels: [String] = [
        "Last name", "First name", "Company", "Title",
        "Work", "Home", "Fax", "Other", "E-mail", "Main", "Pager",
        "IM", "IM", "Website",
        "Custom 1", "Custom 2", "Custom 3", "Custom 4", "Custom 5", "Custom 6", "Custom 7", "Custom 8", "Custom 9",
        "Address", "City", "State", "Zip Code", "Country",
        "Address", "City", "State", "Zip Code", "Country",
        "Address", "City", "State", "Zip Code", "Country",
        "Note", "Birthday", "Mobile",
        "AIM", "MSN", "Yahoo", "ICQ", "Other",
        "Home", "Work", "Other",
        "Picture", "Anniversary", "", ""
    ]

    /// Palm OS country codes for the AppInfo, by ISO region.
    public static let palmCountries: [String: UInt8] = [
        "AU": 0, "AT": 1, "BE": 2, "BR": 3, "CA": 4, "DK": 5, "FI": 6, "FR": 7, "DE": 8, "HK": 9,
        "IS": 10, "IE": 11, "IT": 12, "JP": 13, "LU": 14, "MX": 15, "NL": 16, "NZ": 17, "NO": 18,
        "ES": 19, "SE": 20, "CH": 21, "GB": 22, "US": 23, "IN": 24, "ID": 25, "KR": 26, "MY": 27,
        "CN": 28, "PH": 29, "SG": 30, "TH": 31, "TW": 32,
    ]

    public static func palmCountry(for locale: Locale = .current) -> UInt8 {
        locale.region.flatMap { palmCountries[$0.identifier] } ?? 23
    }

    public let options: Options

    public init(options: Options) {
        self.options = options
    }

    public func build(_ contacts: [MacContact]) -> (database: PalmDatabase, report: Report) {
        var report = Report()
        let kept = dropDuplicates(contacts, &report).filter { contact in
            if contact.isEmpty { report.emptySkipped += 1; return false }
            return true
        }

        // categories from the groups, in order of first appearance
        var names = ["Unfiled"]
        var overflow = false
        var categoryOf: [String: Int] = [:]
        for contact in kept {
            guard let group = contact.groups.first else { continue }
            let name = String(group.prefix(CategoryAppInfo.nameWidth - 1))
            if categoryOf[name] != nil { continue }
            if names.count < Self.maxCategories - 1 {
                names.append(name)
                categoryOf[name] = names.count - 1
            } else {
                if !overflow {
                    names.append(Self.overflowCategory)
                    overflow = true
                    report.warnings.append("more than \(Self.maxCategories - 2) groups: the rest go into \"\(Self.overflowCategory)\"")
                }
                categoryOf[name] = names.firstIndex(of: Self.overflowCategory)!
            }
        }

        // the Palm shows them sorted by name, so hand them over that way
        let sorted = kept.sorted { a, b in
            let ka = (a.lastName.lowercased(), a.firstName.lowercased(), a.company.lowercased())
            let kb = (b.lastName.lowercased(), b.firstName.lowercased(), b.company.lowercased())
            return ka < kb
        }

        var db = PalmDatabase(name: Self.databaseName, type: "DATA", creator: "PAdd", attributes: 0, version: 1,
                              appInfo: ContactAppInfo(categories: CategoryAppInfo(names: names),
                                                      labels: Self.standardLabels,
                                                      country: Self.palmCountry()).encode())
        db.records = sorted.enumerated().map { i, contact in
            let record = convert(contact, &report)
            let category = contact.groups.first.flatMap { categoryOf[String($0.prefix(CategoryAppInfo.nameWidth - 1))] } ?? 0
            return PalmDatabase.Record(category: category, uniqueID: UInt32(i + 1), data: DateFix.shift(record, years: -options.dateShift).encode())
        }
        db.uniqueIDSeed = UInt32(sorted.count + 1)
        report.records = sorted.count
        report.categories = names
        return (db, report)
    }

    func dropDuplicates(_ contacts: [MacContact], _ report: inout Report) -> [MacContact] {
        let priority = Dictionary(uniqueKeysWithValues: options.containers.enumerated().map { ($1.id, $0) })
        var best: [String: MacContact] = [:]
        var order: [String] = []
        for contact in contacts {
            let key = [contact.lastName, contact.firstName, contact.company].map { $0.lowercased() }.joined(separator: "\u{1}")
            if key == "\u{1}\u{1}" {    // nothing to match on
                best[contact.id] = contact
                order.append(contact.id)
                continue
            }
            if let current = best[key] {
                report.duplicatesDropped += 1
                if (priority[contact.containerID] ?? Int.max) < (priority[current.containerID] ?? Int.max) {
                    best[key] = contact
                }
            } else {
                best[key] = contact
                order.append(key)
            }
        }
        return order.compactMap { best[$0] }
    }

    // MARK: One contact

    static func phoneLabel(_ label: String) -> PhoneLabel {
        switch label.lowercased() {
        case "mobile", "iphone", "cell": return .mobile
        case "home": return .home
        case "work": return .work
        case "main": return .main
        case "fax", "home fax", "work fax", "other fax": return .fax
        case "pager": return .pager
        default: return .other
        }
    }

    static let phonePriority: [PhoneLabel] = [.mobile, .main, .home, .work, .other, .fax, .pager]

    func convert(_ contact: MacContact, _ report: inout Report) -> Contact {
        var c = Contact()
        func set(_ field: Contact.Field, _ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { c[field] = trimmed }
        }
        set(.lastName, contact.lastName)
        set(.firstName, contact.middleName.isEmpty ? contact.firstName : "\(contact.firstName) \(contact.middleName)")
        set(.company, contact.company)
        set(.title, contact.jobTitle)

        // phones by priority, then e-mails, into the seven slots
        let phones = contact.phones.map { (Self.phoneLabel($0.label), $0.value) }
        var slots: [(PhoneLabel, String)] = []
        for wanted in Self.phonePriority {
            slots += phones.filter { $0.0 == wanted }
        }
        slots += contact.emails.map { (PhoneLabel.email, $0.value) }
        if slots.count > 7 {
            report.phonesDropped += slots.count - 7
            slots = Array(slots.prefix(7))
        }
        let phoneFields: [Contact.Field] = [.phone1, .phone2, .phone3, .phone4, .phone5, .phone6, .phone7]
        for (i, slot) in slots.enumerated() {
            set(phoneFields[i], slot.1)
            c.setPhoneLabel(i, slot.0.rawValue)
        }
        c.showPhone = UInt8(slots.firstIndex { $0.0 == .mobile } ?? 0)

        // addresses
        let addressFields: [(Contact.Field, Contact.Field, Contact.Field, Contact.Field, Contact.Field)] = [
            (.address1, .city1, .state1, .zip1, .country1),
            (.address2, .city2, .state2, .zip2, .country2),
            (.address3, .city3, .state3, .zip3, .country3),
        ]
        if contact.addresses.count > 3 { report.addressesDropped += contact.addresses.count - 3 }
        for (i, address) in contact.addresses.prefix(3).enumerated() {
            let f = addressFields[i]
            set(f.0, address.street.replacingOccurrences(of: "\n", with: ", "))
            set(f.1, address.city)
            set(f.2, address.state)
            set(f.3, address.postalCode)
            set(f.4, address.country)
            let label: AddressLabel
            switch address.label.lowercased() {
            case "home": label = .home
            case "work": label = .work
            default: label = .other
            }
            c.setAddressLabel(i, label.rawValue)
        }

        // IM and web
        for (i, im) in contact.instantMessages.prefix(2).enumerated() {
            set(i == 0 ? .im1 : .im2, im.value)
            let service: IMLabel
            switch im.label.lowercased() {
            case "aim": service = .aim
            case "msn": service = .msn
            case "yahoo": service = .yahoo
            case "icq": service = .icq
            default: service = .other
            }
            c.setIMLabel(i, service.rawValue)
        }
        if let url = contact.urls.first { set(.website, url) }

        if let birthday = contact.birthday {
            c.birthday = .init(date: birthday, reminderAdvance: nil, advanceUnits: 0)
        }
        if let note = contact.note { set(.note, note) }
        return c
    }
}
