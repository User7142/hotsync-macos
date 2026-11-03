import Foundation

/// The part of a contact both sides can hold: the names, the seven phone
/// slots (phones and e-mails, as the Palm keeps them), three addresses, two
/// IM handles, the web site, the birthday and the category. The Palm's
/// custom fields, its note (macOS hands notes only to entitled apps) and
/// its picture stay in the record; the Mac's extra phones and addresses
/// beyond the slots stay on the Mac.
public struct SyncedContact: Equatable, Hashable, Codable, Sendable {
    public struct Phone: Equatable, Hashable, Codable, Sendable {
        /// ContactsBuilder.PhoneLabel's raw value: work 0, home 1, fax 2,
        /// other 3, e-mail 4, main 5, pager 6, mobile 7
        public var label: UInt8
        public var value: String
        public init(label: UInt8, value: String) {
            self.label = label
            self.value = value
        }
        public var isEmail: Bool { label == ContactsBuilder.PhoneLabel.email.rawValue }
    }

    public struct Address: Equatable, Hashable, Codable, Sendable {
        /// ContactsBuilder.AddressLabel's raw value: home 0, work 1, other 2
        public var label: UInt8
        public var street: String?
        public var city: String?
        public var state: String?
        public var zip: String?
        public var country: String?
        public init(label: UInt8, street: String? = nil, city: String? = nil, state: String? = nil,
                    zip: String? = nil, country: String? = nil) {
            self.label = label
            self.street = street
            self.city = city
            self.state = state
            self.zip = zip
            self.country = country
        }
        public var isEmpty: Bool { street == nil && city == nil && state == nil && zip == nil && country == nil }
    }

    public struct IM: Equatable, Hashable, Codable, Sendable {
        /// ContactsBuilder.IMLabel's raw value: AIM 0, MSN 1, Yahoo 2, ICQ 3, other 4
        public var service: UInt8
        public var value: String
        public init(service: UInt8, value: String) {
            self.service = service
            self.value = value
        }
    }

    public var lastName: String?
    public var firstName: String?
    public var company: String?
    public var jobTitle: String?
    public var phones: [Phone]
    public var addresses: [Address]
    public var instantMessages: [IM]
    public var website: String?
    public var birthday: PalmDate?
    public var category: String

    public enum Field: String, CaseIterable, Codable, Sendable {
        case lastName, firstName, company, jobTitle, phones, addresses, instantMessages, website, birthday, category
    }

    public init(lastName: String? = nil, firstName: String? = nil, company: String? = nil, jobTitle: String? = nil,
                phones: [Phone] = [], addresses: [Address] = [], instantMessages: [IM] = [], website: String? = nil,
                birthday: PalmDate? = nil, category: String) {
        self.lastName = lastName
        self.firstName = firstName
        self.company = company
        self.jobTitle = jobTitle
        self.phones = phones
        self.addresses = addresses
        self.instantMessages = instantMessages
        self.website = website
        self.birthday = birthday
        self.category = category
    }

    static let phoneFields: [Contact.Field] = [.phone1, .phone2, .phone3, .phone4, .phone5, .phone6, .phone7]
    static let addressFields: [(Contact.Field, Contact.Field, Contact.Field, Contact.Field, Contact.Field)] = [
        (.address1, .city1, .state1, .zip1, .country1),
        (.address2, .city2, .state2, .zip2, .country2),
        (.address3, .city3, .state3, .zip3, .country3),
    ]

    public init(_ record: Contact, category: String) {
        lastName = record[.lastName]
        firstName = record[.firstName]
        company = record[.company]
        jobTitle = record[.title]
        phones = Self.phoneFields.enumerated().compactMap { i, field in
            record[field].map { Phone(label: record.phoneLabel(i), value: $0) }
        }
        addresses = Self.addressFields.enumerated().compactMap { i, f in
            let a = Address(label: record.addressLabel(i), street: record[f.0], city: record[f.1], state: record[f.2],
                            zip: record[f.3], country: record[f.4])
            return a.isEmpty ? nil : a
        }
        instantMessages = [Contact.Field.im1, .im2].enumerated().compactMap { i, field in
            record[field].map { IM(service: record.imLabel(i), value: $0) }
        }
        website = record[.website]
        birthday = record.birthday?.date
        self.category = category
    }

    /// The same contact as the builder would hand the Palm.
    public init(_ contact: MacContact, category: String) {
        self.init(ContactsBuilder.palmContact(contact), category: category)
    }

    public var title: String? {
        let name = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        return name.isEmpty ? company : name
    }
}

extension SyncedContact: SyncedItem {
    public typealias PalmRecord = Contact

    public static func palmRecord(from data: Data) throws -> Contact { try Contact(data: data) }
    public static func encode(_ record: Contact) -> Data { record.encode() }
    public func newPalmRecord() -> Contact { Contact() }

    /// Writes the shared fields into the record; custom fields, note,
    /// birthday reminder and blobs stay as they are.
    public func apply(to record: inout Contact) {
        record[.lastName] = lastName
        record[.firstName] = firstName
        record[.company] = company
        record[.title] = jobTitle
        for (i, field) in Self.phoneFields.enumerated() {
            if i < phones.count {
                record[field] = phones[i].value
                record.setPhoneLabel(i, phones[i].label)
            } else {
                record[field] = nil
                record.setPhoneLabel(i, 0)
            }
        }
        if Int(record.showPhone) >= phones.count {
            record.showPhone = UInt8(phones.firstIndex { $0.label == ContactsBuilder.PhoneLabel.mobile.rawValue } ?? 0)
        }
        for (i, f) in Self.addressFields.enumerated() {
            let a = i < addresses.count ? addresses[i] : Address(label: 0)
            record[f.0] = a.street
            record[f.1] = a.city
            record[f.2] = a.state
            record[f.3] = a.zip
            record[f.4] = a.country
            record.setAddressLabel(i, a.label)
        }
        for (i, field) in [Contact.Field.im1, .im2].enumerated() {
            if i < instantMessages.count {
                record[field] = instantMessages[i].value
                record.setIMLabel(i, instantMessages[i].service)
            } else {
                record[field] = nil
                record.setIMLabel(i, 0)
            }
        }
        record[.website] = website
        if let birthday {
            if var existing = record.birthday {
                existing.date = birthday
                record.birthday = existing
            } else {
                record.birthday = .init(date: birthday, reminderAdvance: nil, advanceUnits: 0)
            }
        } else {
            record.birthday = nil
        }
    }

    public func value(of field: Field) -> AnyHashable {
        switch field {
        case .lastName: return lastName
        case .firstName: return firstName
        case .company: return company
        case .jobTitle: return jobTitle
        case .phones: return phones
        case .addresses: return addresses
        case .instantMessages: return instantMessages
        case .website: return website
        case .birthday: return birthday
        case .category: return category
        }
    }

    public mutating func set(_ field: Field, from other: SyncedContact) {
        switch field {
        case .lastName: lastName = other.lastName
        case .firstName: firstName = other.firstName
        case .company: company = other.company
        case .jobTitle: jobTitle = other.jobTitle
        case .phones: phones = other.phones
        case .addresses: addresses = other.addresses
        case .instantMessages: instantMessages = other.instantMessages
        case .website: website = other.website
        case .birthday: birthday = other.birthday
        case .category: category = other.category
        }
    }

    public func differs(from other: SyncedContact, in field: Field) -> Bool {
        value(of: field) != other.value(of: field)
    }

    public func describe(_ field: Field) -> String {
        switch field {
        case .lastName: return lastName ?? ""
        case .firstName: return firstName ?? ""
        case .company: return company ?? ""
        case .jobTitle: return jobTitle ?? ""
        case .phones: return phones.map(\.value).joined(separator: ", ")
        case .addresses: return addresses.map { [$0.street, $0.city, $0.state, $0.zip, $0.country].compactMap { $0 }.joined(separator: " ") }.joined(separator: "; ")
        case .instantMessages: return instantMessages.map(\.value).joined(separator: ", ")
        case .website: return website ?? ""
        case .birthday: return birthday.map { String(format: "%d-%02d-%02d", $0.year, $0.month, $0.day) } ?? "none"
        case .category: return category
        }
    }

    public func shiftingDates(by years: Int) -> SyncedContact {
        guard years != 0, let birthday else { return self }
        var s = self
        s.birthday = DateFix.shift(birthday, years: years)
        return s
    }

    /// Slow sync: the same name and company, as the builder's duplicate
    /// rule has it.
    public func matches(_ other: SyncedContact) -> Bool {
        func key(_ c: SyncedContact) -> [String] { [c.lastName, c.firstName, c.company].map { ($0 ?? "").lowercased() } }
        let mine = key(self)
        return mine != ["", "", ""] && mine == key(other)
    }
}

public typealias ContactSyncPlan = SyncPlan<SyncedContact>
public typealias ContactMirror = SyncMirror<SyncedContact>

extension ContactsBuilder {
    /// One contact as a Palm record, the slot rules applied, nothing reported.
    public static func palmContact(_ contact: MacContact) -> Contact {
        var report = Report()
        return ContactsBuilder(options: .init(containers: [])).convert(contact, &report)
    }

    /// The Mac's contacts as the sync engine takes them: duplicates across
    /// accounts dropped as in the one-way build, the first group as the
    /// category, each keyed by its Contacts identifier.
    public func syncItems(_ contacts: [MacContact]) -> [MacSyncItem<SyncedContact>] {
        var report = Report()
        return dropDuplicates(contacts, &report).filter { !$0.isEmpty }.map { contact in
            let record = convert(contact, &report)
            let category = contact.groups.first.map { String($0.prefix(CategoryAppInfo.nameWidth - 1)) } ?? "Unfiled"
            return MacSyncItem(key: MacKey(seriesID: contact.id), item: SyncedContact(record, category: category),
                               palmRecord: record.encode())
        }
    }
}

extension SyncPlan where Item == SyncedContact {
    /// The Palm's side of the plan as a whole ContactsDB-PAdd to install,
    /// sorted by name as the Contacts application lists them. The Palm's
    /// own AppInfo (its labels, country, sort order) is kept; only the
    /// categories change.
    public func palmDatabase(appInfo existing: ContactAppInfo)
        -> (database: PalmDatabase, palmIDs: [Int: UInt32], categories: CategoryAppInfo) {
        let (records, palmIDs, categories, nextID) = palmRecords(categories: existing.categories) { a, b in
            func key(_ c: SyncedContact) -> [String] { [c.lastName, c.firstName, c.company].map { ($0 ?? "").lowercased() } }
            return key(a).lexicographicallyPrecedes(key(b))
        }
        var appInfo = existing
        appInfo.categories = categories
        var db = PalmDatabase(name: ContactsBuilder.databaseName, type: "DATA", creator: "PAdd", attributes: 0, version: 1,
                              appInfo: appInfo.encode())
        db.records = records
        db.uniqueIDSeed = nextID
        return (db, palmIDs, categories)
    }
}
