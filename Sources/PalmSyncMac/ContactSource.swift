import Contacts
import Foundation
import PalmSync

/// Contacts.app through Contacts.framework, as the sync sees it: the
/// accounts (containers) to choose from and their contacts as MacContacts,
/// with the groups they are in. One instance per process.
public final class ContactSource: @unchecked Sendable {
    public struct Container: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        /// "iCloud", "CardDAV", "Exchange", "Local"
        public let kind: String

        public init(id: String, title: String, kind: String) {
            self.id = id
            self.title = title
            self.kind = kind
        }
    }

    public let store = CNContactStore()

    public init() {}

    public var accessStatus: CNAuthorizationStatus { CNContactStore.authorizationStatus(for: .contacts) }
    public var hasAccess: Bool { accessStatus == .authorized }

    public func requestAccess() async throws -> Bool {
        try await store.requestAccess(for: .contacts)
    }

    public func containers() -> [Container] {
        let containers = (try? store.containers(matching: nil)) ?? []
        return containers.map { c in
            let kind: String
            switch c.type {
            case .local: kind = "Local"
            case .exchange: kind = "Exchange"
            case .cardDAV: kind = c.name.lowercased().contains("icloud") ? "iCloud" : "CardDAV"
            default: kind = "Other"
            }
            return Container(id: c.identifier, title: c.name.isEmpty ? kind : c.name, kind: kind)
        }
        .sorted { $0.title < $1.title }
    }

    /// Every contact of the given accounts, with its groups. The note is not
    /// read: macOS hands it out only to apps with an entitlement Apple grants
    /// on request, so it stays on the Mac.
    public enum Failure: Error, LocalizedError {
        case containerMissing(String)
        public var errorDescription: String? {
            switch self {
            case .containerMissing(let id): return "a chosen account no longer exists (\(id)); choose the accounts again"
            }
        }
    }

    public func contacts(in containerIDs: [String]) throws -> [MacContact] {
        // an account that is gone is an error, not an empty account
        let existing = Set((try store.containers(matching: nil)).map(\.identifier))
        if let gone = containerIDs.first(where: { !existing.contains($0) }) { throw Failure.containerMissing(gone) }
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey, CNContactGivenNameKey, CNContactMiddleNameKey, CNContactFamilyNameKey,
            CNContactOrganizationNameKey, CNContactJobTitleKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
            CNContactPostalAddressesKey, CNContactInstantMessageAddressesKey, CNContactUrlAddressesKey, CNContactBirthdayKey,
        ] as [CNKeyDescriptor]

        // which group each contact is in, by the groups of these accounts
        var groupsOf: [String: [String]] = [:]
        for container in containerIDs {
            let groups = (try? store.groups(matching: CNGroup.predicateForGroupsInContainer(withIdentifier: container))) ?? []
            for group in groups {
                let members = (try? store.unifiedContacts(matching: CNContact.predicateForContactsInGroup(withIdentifier: group.identifier),
                                                           keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])) ?? []
                for member in members { groupsOf[member.identifier, default: []].append(group.name) }
            }
        }

        var result: [MacContact] = []
        for container in containerIDs {
            let predicate = CNContact.predicateForContactsInContainer(withIdentifier: container)
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
            for c in contacts {
                result.append(Self.macContact(c, containerID: container, groups: groupsOf[c.identifier] ?? []))
            }
        }
        return result
    }

    // MARK: CNContact to MacContact

    static func label(_ label: String?) -> String {
        guard let label else { return "other" }
        switch label {
        case CNLabelPhoneNumberMobile, CNLabelPhoneNumberiPhone: return "mobile"
        case CNLabelHome: return "home"
        case CNLabelWork: return "work"
        case CNLabelPhoneNumberMain: return "main"
        case CNLabelPhoneNumberHomeFax, CNLabelPhoneNumberWorkFax, CNLabelPhoneNumberOtherFax: return "fax"
        case CNLabelPhoneNumberPager: return "pager"
        case CNLabelOther: return "other"
        default: return CNLabeledValue<NSString>.localizedString(forLabel: label)
        }
    }

    public static func macContact(_ c: CNContact, containerID: String, groups: [String]) -> MacContact {
        MacContact(
            id: c.identifier,
            containerID: containerID,
            groups: groups,
            firstName: c.givenName,
            middleName: c.middleName,
            lastName: c.familyName,
            company: c.organizationName,
            jobTitle: c.jobTitle,
            phones: c.phoneNumbers.map { .init(label($0.label), $0.value.stringValue) },
            emails: c.emailAddresses.map { .init(label($0.label), String($0.value)) },
            addresses: c.postalAddresses.map {
                .init(label: label($0.label), street: $0.value.street, city: $0.value.city, state: $0.value.state,
                      postalCode: $0.value.postalCode, country: $0.value.country)
            },
            instantMessages: c.instantMessageAddresses.map { .init($0.value.service, $0.value.username) },
            urls: c.urlAddresses.map { String($0.value) },
            birthday: c.birthday.flatMap { b in
                guard let y = b.year, let m = b.month, let d = b.day, y >= 1904 else { return nil }
                return PalmDate(year: y, month: m, day: d)
            })
    }
}

/// What the user chose for a Palm: which accounts' contacts go on it.
/// Groups become categories on their own. Stored with the device profile.
public struct ContactSyncSettings: Codable, Equatable, Sendable {
    public struct Choice: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var title: String
        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    public var enabled: Bool
    public var containers: [Choice]
    /// nil (profiles from before the setting): the Mac wins
    public var conflictPolicy: ConflictPolicy?

    public init(enabled: Bool = false, containers: [Choice] = [], conflictPolicy: ConflictPolicy? = nil) {
        self.enabled = enabled
        self.containers = containers
        self.conflictPolicy = conflictPolicy
    }

    public var conflicts: ConflictPolicy { conflictPolicy ?? .macWins }
}

/// One run of the one-way contacts sync, checked by reading it back.
public struct ContactSyncRun {
    public let contacts: Int
    public let database: PalmDatabase
    public let report: ContactsBuilder.Report

    public enum Failure: Error {
        case noAccess
        case doesNotReadBack
    }

    public init(settings: ContactSyncSettings, source: ContactSource, dateShift: Int = 0) throws {
        guard source.hasAccess else { throw Failure.noAccess }
        let macContacts = try source.contacts(in: settings.containers.map(\.id))
        contacts = macContacts.count
        let builder = ContactsBuilder(options: .init(containers: settings.containers.map { .init(id: $0.id, title: $0.title) },
                                                     dateShift: dateShift))
        (database, report) = builder.build(macContacts)

        let image = database.encode()
        guard let check = try? PalmDatabase(data: image), check == database,
              check.records.allSatisfy({ (try? Contact(data: $0.data))?.encode() == $0.data }),
              let appInfo = check.appInfo, (try? ContactAppInfo(data: appInfo)) != nil else {
            throw Failure.doesNotReadBack
        }
    }

    @discardableResult
    public func write(to url: URL) throws -> Int {
        let image = database.encode()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try image.write(to: url, options: .atomic)
        return image.count
    }
}
