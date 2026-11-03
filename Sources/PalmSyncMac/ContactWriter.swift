import Contacts
import Foundation
import PalmSync

/// Applies the Mac side of a contacts sync plan to Contacts.app. Only the
/// fields the Palm changed are rewritten, so what the Palm has no slot
/// for (a fourth address, an eighth phone, the note, the picture) stays
/// as it is on the Mac. The category is the first group the contact is in,
/// within the chosen accounts.
public struct ContactWriter {
    public struct Result: Equatable, Sendable {
        public var createdKeys: [Int: MacKey] = [:]
        public var updated = 0
        public var deleted = 0
        public var failures: [String] = []
        /// Entry indices of creates and updates that did not happen, so the
        /// mirror keeps the old base for them and they are retried.
        public var failedEntries: [Int] = []
    }

    public let store: CNContactStore
    /// The accounts the sync covers: groups are looked up and made here.
    public let containerIDs: [String]
    /// Where a contact the Palm made goes: the first chosen account.
    public var newContactsContainer: String? { containerIDs.first }

    public init(store: CNContactStore, containerIDs: [String]) {
        self.store = store
        self.containerIDs = containerIDs
    }

    static let keys: [CNKeyDescriptor] = [
        CNContactIdentifierKey, CNContactGivenNameKey, CNContactMiddleNameKey, CNContactFamilyNameKey,
        CNContactOrganizationNameKey, CNContactJobTitleKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
        CNContactPostalAddressesKey, CNContactInstantMessageAddressesKey, CNContactUrlAddressesKey, CNContactBirthdayKey,
    ] as [CNKeyDescriptor]

    // MARK: Mapping

    static func cnPhoneLabel(_ label: UInt8) -> String {
        switch ContactsBuilder.PhoneLabel(rawValue: label) ?? .other {
        case .work: return CNLabelWork
        case .home: return CNLabelHome
        case .fax: return CNLabelPhoneNumberWorkFax
        case .other, .email: return CNLabelOther
        case .main: return CNLabelPhoneNumberMain
        case .pager: return CNLabelPhoneNumberPager
        case .mobile: return CNLabelPhoneNumberMobile
        }
    }

    static func cnAddressLabel(_ label: UInt8) -> String {
        switch ContactsBuilder.AddressLabel(rawValue: label) ?? .other {
        case .home: return CNLabelHome
        case .work: return CNLabelWork
        case .other: return CNLabelOther
        }
    }

    static func cnIMService(_ service: UInt8) -> String {
        switch ContactsBuilder.IMLabel(rawValue: service) ?? .other {
        case .aim: return CNInstantMessageServiceAIM
        case .msn: return CNInstantMessageServiceMSN
        case .yahoo: return CNInstantMessageServiceYahoo
        case .icq: return CNInstantMessageServiceICQ
        case .other: return "Other"
        }
    }

    /// Writes the fields in which `item` differs from what the contact
    /// holds now. A phone or e-mail the Mac has beyond the Palm's slots is
    /// kept; one the Palm dropped from a slot is dropped.
    public static func fill(_ c: CNMutableContact, from item: SyncedContact) {
        let now = SyncedContact(ContactSource.macContact(c, containerID: "", groups: []), category: item.category)

        if item.differs(from: now, in: .firstName) {
            c.givenName = item.firstName ?? ""
            c.middleName = ""
        }
        if item.differs(from: now, in: .lastName) { c.familyName = item.lastName ?? "" }
        if item.differs(from: now, in: .company) { c.organizationName = item.company ?? "" }
        if item.differs(from: now, in: .jobTitle) { c.jobTitle = item.jobTitle ?? "" }

        if item.differs(from: now, in: .phones) {
            let slotValues = Set(now.phones.map(\.value))
            // what the slots did not take stays
            let extraPhones = c.phoneNumbers.filter { !slotValues.contains($0.value.stringValue) }
            let extraEmails = c.emailAddresses.filter { !slotValues.contains(String($0.value)) }
            // a value already on the Mac keeps its own label
            let phoneLabels = Dictionary(c.phoneNumbers.map { ($0.value.stringValue, $0.label) }, uniquingKeysWith: { a, _ in a })
            let emailLabels = Dictionary(c.emailAddresses.map { (String($0.value), $0.label) }, uniquingKeysWith: { a, _ in a })
            c.phoneNumbers = item.phones.filter { !$0.isEmail }.map {
                CNLabeledValue(label: phoneLabels[$0.value] ?? cnPhoneLabel($0.label), value: CNPhoneNumber(stringValue: $0.value))
            } + extraPhones
            c.emailAddresses = item.phones.filter(\.isEmail).map {
                CNLabeledValue(label: emailLabels[$0.value] ?? CNLabelHome, value: $0.value as NSString)
            } + extraEmails
        }

        if item.differs(from: now, in: .addresses) {
            let extra = c.postalAddresses.dropFirst(3)
            c.postalAddresses = item.addresses.map { a in
                let address = CNMutablePostalAddress()
                address.street = a.street ?? ""
                address.city = a.city ?? ""
                address.state = a.state ?? ""
                address.postalCode = a.zip ?? ""
                address.country = a.country ?? ""
                return CNLabeledValue(label: cnAddressLabel(a.label), value: address)
            } + extra
        }

        if item.differs(from: now, in: .instantMessages) {
            let extra = c.instantMessageAddresses.dropFirst(2)
            c.instantMessageAddresses = item.instantMessages.map {
                CNLabeledValue(label: nil, value: CNInstantMessageAddress(username: $0.value, service: cnIMService($0.service)))
            } + extra
        }

        if item.differs(from: now, in: .website) {
            var urls = c.urlAddresses
            if let site = item.website {
                let value = CNLabeledValue(label: urls.first?.label ?? CNLabelURLAddressHomePage, value: site as NSString)
                if urls.isEmpty { urls = [value] } else { urls[0] = value }
            } else if !urls.isEmpty {
                urls.removeFirst()
            }
            c.urlAddresses = urls
        }

        if item.differs(from: now, in: .birthday) {
            c.birthday = item.birthday.map { DateComponents(year: $0.year, month: $0.month, day: $0.day) }
        }
    }

    // MARK: Applying

    public func apply(_ plan: ContactSyncPlan) -> Result {
        var result = Result()
        var groups = loadGroups()

        func place(_ contact: CNContact, in category: String, request: CNSaveRequest) {
            // out of the other groups of these accounts, into the category's
            for group in groups.all where group.name != category && groups.members[group.identifier, default: []].contains(contact.identifier) {
                request.removeMember(contact, from: group)
                groups.members[group.identifier]?.remove(contact.identifier)
            }
            guard category != "Unfiled" else { return }
            let group: CNGroup
            if let existing = groups.all.first(where: { $0.name == category }) {
                group = existing
            } else if let container = newContactsContainer {
                let made = CNMutableGroup()
                made.name = category
                request.add(made, toContainerWithIdentifier: container)
                groups.all.append(made)
                group = made
            } else {
                return
            }
            if !(groups.members[group.identifier]?.contains(contact.identifier) ?? false) {
                request.addMember(contact, to: group)
                groups.members[group.identifier, default: []].insert(contact.identifier)
            }
        }

        for change in plan.macCreates {
            let c = CNMutableContact()
            Self.fill(c, from: change.item)
            let request = CNSaveRequest()
            request.add(c, toContainerWithIdentifier: newContactsContainer)
            place(c, in: change.item.category, request: request)
            do {
                try store.execute(request)
                result.createdKeys[change.entry] = MacKey(seriesID: c.identifier)
            } catch {
                result.failures.append("\(change.item.title ?? "?"): \(error.localizedDescription)")
                result.failedEntries.append(change.entry)
            }
        }

        for change in plan.macUpdates {
            guard let key = change.key, let existing = find(key) else {
                result.failures.append("\(change.item.title ?? "?"): not found on the Mac any more")
                result.failedEntries.append(change.entry)
                continue
            }
            let c = existing.mutableCopy() as! CNMutableContact
            Self.fill(c, from: change.item)
            let request = CNSaveRequest()
            request.update(c)
            // group membership changes only when the Palm changed the category
            if change.changed.contains(.category) { place(c, in: change.item.category, request: request) }
            do {
                try store.execute(request)
                result.updated += 1
            } catch {
                result.failures.append("\(change.item.title ?? "?"): \(error.localizedDescription)")
                result.failedEntries.append(change.entry)
            }
        }

        for key in plan.macDeletes {
            // only the cards in the chosen accounts: a unified contact may be
            // linked to cards in accounts the sync does not cover
            guard let unified = find(key) else { continue }   // already gone: fine
            let cards = ownCards(of: unified)
            guard !cards.isEmpty else {
                result.failures.append("\(unified.givenName) \(unified.familyName): no card in the chosen accounts, nothing deleted")
                continue
            }
            let request = CNSaveRequest()
            for card in cards { request.delete(card.mutableCopy() as! CNMutableContact) }
            do {
                try store.execute(request)
                result.deleted += 1
            } catch {
                result.failures.append("\(cards[0].givenName) \(cards[0].familyName): \(error.localizedDescription)")
            }
        }
        return result
    }

    /// The cards in the chosen accounts that are linked into this unified
    /// contact: every card of those accounts whose own unified contact is
    /// this one. (A unified contact's identifier is one card's, which may
    /// well live in an account the sync does not cover.)
    private func ownCards(of unified: CNContact) -> [CNContact] {
        let keys = [CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey] as [CNKeyDescriptor]
        var cards: [CNContact] = []
        for container in containerIDs {
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.unifyResults = false
            request.predicate = CNContact.predicateForContactsInContainer(withIdentifier: container)
            try? store.enumerateContacts(with: request) { card, _ in
                if card.identifier == unified.identifier
                    || (try? store.unifiedContact(withIdentifier: card.identifier, keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]))?
                        .identifier == unified.identifier {
                    cards.append(card)
                }
            }
        }
        return cards
    }

    public func find(_ key: MacKey) -> CNContact? {
        try? store.unifiedContact(withIdentifier: key.seriesID, keysToFetch: Self.keys)
    }

    /// The groups of the chosen accounts and who is in them.
    private func loadGroups() -> (all: [CNGroup], members: [String: Set<String>]) {
        var all: [CNGroup] = []
        var members: [String: Set<String>] = [:]
        for container in containerIDs {
            let groups = (try? store.groups(matching: CNGroup.predicateForGroupsInContainer(withIdentifier: container))) ?? []
            for group in groups {
                all.append(group)
                let found = (try? store.unifiedContacts(matching: CNContact.predicateForContactsInGroup(withIdentifier: group.identifier),
                                                         keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])) ?? []
                members[group.identifier] = Set(found.map(\.identifier))
            }
        }
        return (all, members)
    }
}
