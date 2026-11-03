import Foundation
import Testing
@testable import PalmSync

private let icloud = ContactsBuilder.MacContainer(id: "icloud", title: "iCloud")
private let google = ContactsBuilder.MacContainer(id: "google", title: "Google")
private let builder = ContactsBuilder(options: .init(containers: [icloud, google]))

private func decoded(_ db: PalmDatabase) -> [Contact] { db.records.map { try! Contact(data: $0.data) } }

@Test func fieldsAndSlots() {
    let zoe = MacContact(id: "1", containerID: "icloud", groups: ["Friends"], firstName: "Zoë", middleName: "A",
                         lastName: "Leto", company: "Lasergirl", jobTitle: "Engineer",
                         phones: [.init("work", "+1 604 555 0100"), .init("mobile", "+1 604 555 0101"),
                                  .init("home fax", "+1 604 555 0102"), .init("Custom", "+1 604 555 0103")],
                         emails: [.init("home", "zoe@example.com"), .init("work", "z@work.example")],
                         addresses: [.init(label: "home", street: "1 Main St\nUnit 2", city: "Vancouver", state: "BC",
                                           postalCode: "V6B 1A1", country: "Canada"),
                                     .init(label: "work", street: "2 Work Ave", city: "Burnaby")],
                         instantMessages: [.init("Yahoo", "zoe_y"), .init("Jabber", "zoe@jabber")],
                         urls: ["https://example.com", "https://other.example"],
                         birthday: PalmDate(year: 1985, month: 3, day: 8))
    let (db, report) = builder.build([zoe])
    #expect(report.records == 1 && report.phonesDropped == 0 && report.addressesDropped == 0)
    #expect(report.categories == ["Unfiled", "Friends"])
    #expect(db.records[0].category == 1)

    let c = decoded(db)[0]
    #expect(c[.lastName] == "Leto" && c[.firstName] == "Zoë A")
    #expect(c[.company] == "Lasergirl" && c[.title] == "Engineer")
    // mobile first, then work, other, fax, then the e-mails
    #expect(c[.phone1] == "+1 604 555 0101" && c.phoneLabel(0) == ContactsBuilder.PhoneLabel.mobile.rawValue)
    #expect(c[.phone2] == "+1 604 555 0100" && c.phoneLabel(1) == ContactsBuilder.PhoneLabel.work.rawValue)
    #expect(c[.phone3] == "+1 604 555 0103" && c.phoneLabel(2) == ContactsBuilder.PhoneLabel.other.rawValue)
    #expect(c[.phone4] == "+1 604 555 0102" && c.phoneLabel(3) == ContactsBuilder.PhoneLabel.fax.rawValue)
    #expect(c[.phone5] == "zoe@example.com" && c.phoneLabel(4) == ContactsBuilder.PhoneLabel.email.rawValue)
    #expect(c[.phone6] == "z@work.example" && c[.phone7] == nil)
    #expect(c.showPhone == 0)
    #expect(c[.address1] == "1 Main St, Unit 2" && c[.city1] == "Vancouver" && c[.zip1] == "V6B 1A1")
    #expect(c.addressLabel(0) == ContactsBuilder.AddressLabel.home.rawValue)
    #expect(c[.address2] == "2 Work Ave" && c[.state2] == nil && c.addressLabel(1) == ContactsBuilder.AddressLabel.work.rawValue)
    #expect(c[.im1] == "zoe_y" && c.imLabel(0) == ContactsBuilder.IMLabel.yahoo.rawValue)
    #expect(c[.im2] == "zoe@jabber" && c.imLabel(1) == ContactsBuilder.IMLabel.other.rawValue)
    #expect(c[.website] == "https://example.com")
    #expect(c.birthday == .init(date: PalmDate(year: 1985, month: 3, day: 8), reminderAdvance: nil, advanceUnits: 0))
    #expect(c[.note] == nil)
}

@Test func tooManyPhonesAndAddresses() {
    let many = MacContact(id: "1", containerID: "icloud", lastName: "Many",
                          phones: (1...6).map { .init("home", "\($0)") },
                          emails: (1...4).map { .init("work", "e\($0)@x") },
                          addresses: (1...4).map { .init(label: "other", street: "\($0)") })
    let (db, report) = builder.build([many])
    #expect(report.phonesDropped == 3 && report.addressesDropped == 1)
    let c = decoded(db)[0]
    #expect(c[.phone7] == "e1@x")
    #expect(c.showPhone == 0)
    #expect(c[.address3] == "3")
}

@Test func mobileIsShownInTheList() {
    let c = decoded(builder.build([MacContact(id: "1", containerID: "icloud", lastName: "X",
                                              phones: [.init("home", "1"), .init("work", "2"), .init("iPhone", "3")])]).database)[0]
    #expect(c[.phone1] == "3" && c.showPhone == 0)
    let d = decoded(builder.build([MacContact(id: "2", containerID: "icloud", lastName: "Y",
                                              phones: [.init("home", "1")], emails: [.init("home", "a@b")])]).database)[0]
    #expect(d.showPhone == 0 && d[.phone2] == "a@b")
}

@Test func sortedByNameAndEmptyOnesSkipped() {
    let (db, report) = builder.build([
        MacContact(id: "1", containerID: "icloud", firstName: "A", lastName: "Zed"),
        MacContact(id: "2", containerID: "icloud", firstName: "B", lastName: "adams"),
        MacContact(id: "3", containerID: "icloud", company: "Acme"),
        MacContact(id: "4", containerID: "icloud"),
    ])
    #expect(report.emptySkipped == 1 && report.records == 3)
    let names: [String] = decoded(db).map { c in c[.lastName] ?? c[.company] ?? "" }
    #expect(names == ["Acme", "adams", "Zed"])
    #expect(db.records.map(\.uniqueID) == [1, 2, 3])
}

@Test func samePersonInTwoAccountsIsKeptFromTheFirst() {
    let (db, report) = builder.build([
        MacContact(id: "g", containerID: "google", firstName: "Zoë", lastName: "Leto", phones: [.init("mobile", "google")]),
        MacContact(id: "i", containerID: "icloud", firstName: "Zoë", lastName: "Leto", phones: [.init("mobile", "icloud")]),
        MacContact(id: "o", containerID: "google", firstName: "One", lastName: "Other"),
    ])
    #expect(report.duplicatesDropped == 1 && report.records == 2)
    #expect(decoded(db)[0][.phone1] == "icloud")
}

@Test func groupsBecomeCategoriesWithOverflow() {
    var contacts = (1...17).map { MacContact(id: "\($0)", containerID: "icloud", groups: ["Group \($0)"], lastName: "N\($0)") }
    contacts.append(MacContact(id: "x", containerID: "icloud", lastName: "Nobody"))
    let (db, report) = builder.build(contacts)
    #expect(report.categories.count == 16 && report.categories.last == "Other")
    #expect(report.warnings.count == 1)
    let byName = Dictionary(uniqueKeysWithValues: decoded(db).enumerated().map { ($1[.lastName]!, db.records[$0].category) })
    #expect(byName["N1"] == 1 && byName["N14"] == 14 && byName["N15"] == 15 && byName["N17"] == 15)
    #expect(byName["Nobody"] == 0)
}

@Test func contactsDatabaseReadsBack() throws {
    let (db, _) = builder.build([MacContact(id: "1", containerID: "icloud", firstName: "Zoë", lastName: "Leto")])
    let data = db.encode()
    let back = try PalmDatabase(data: data)
    #expect(back == db && back.name == "ContactsDB-PAdd" && back.creator == "PAdd")
    let info = try ContactAppInfo(data: try #require(back.appInfo))
    #expect(info.labels.count == 53 && info.phoneLabels[7] == "Mobile")
    #expect(try Contact(data: back.records[0].data).encode() == back.records[0].data)
}
