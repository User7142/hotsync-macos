import Foundation
import Testing
@testable import PalmSync

/// ContactsDB-PAdd.pdb is written by Fixtures/generate-contacts.c with
/// pilot-link's pack_Contact; every record must come back byte for byte.
private func contactsFixture() throws -> PalmDatabase {
    let url = try #require(Bundle.module.url(forResource: "ContactsDB-PAdd.pdb", withExtension: nil, subdirectory: "Fixtures"))
    return try PalmDatabase(data: try Data(contentsOf: url))
}

@Test func contactsContainer() throws {
    let db = try contactsFixture()
    #expect(db.name == "ContactsDB-PAdd")
    #expect(db.creator == "PAdd")
    #expect(db.records.count == 7)
    #expect(db.appInfo?.count == ContactAppInfo.size(labels: ContactAppInfo.labelCountV11))
}

@Test func everyContactRoundTripsByteForByte() throws {
    let db = try contactsFixture()
    for (i, record) in db.records.enumerated() {
        let contact = try Contact(data: record.data)
        #expect(contact.encode() == record.data, "record \(i)")
    }
}

@Test func fullContact() throws {
    let c = try Contact(data: try contactsFixture().records[0].data)
    #expect(c[.lastName] == "Leto")
    #expect(c[.firstName] == "Zoë")
    #expect(c[.company] == "Lasergirl")
    #expect(c[.title] == "Engineer")
    #expect(c[.phone5] == "zoe@example.com")
    #expect(c[.im2] == "zoe_icq")
    #expect(c[.website] == "https://example.com")
    #expect(c[.custom1] == "c1" && c[.custom2] == nil && c[.custom9] == "c9")
    #expect(c[.address1] == "1 Main St" && c[.zip1] == "V6B 1A1")
    #expect(c[.address2] == "2 Work Ave" && c[.state2] == nil)
    #expect(c[.country3] == "Canada")
    #expect(c[.note] == "Note — café")
    #expect(c.fields.compactMap { $0 }.count == 26)

    #expect((0..<7).map(c.phoneLabel) == [0, 1, 2, 3, 4, 5, 7])
    #expect(c.showPhone == 6)
    #expect((0..<3).map(c.addressLabel) == [0, 1, 2])
    #expect((0..<2).map(c.imLabel) == [0, 3])

    #expect(c.birthday == .init(date: PalmDate(year: 1985, month: 3, day: 8), reminderAdvance: 7, advanceUnits: 2))

    #expect(c.blobs.map(\.type) == [Contact.pictureBlobType, Contact.anniversaryBlobType])
    #expect(c.blobs[0].data.prefix(4) == Data([0x00, 0x00, 0xff, 0xd8]))
    #expect(c.blobs[1].data == Data([0xc2, 0xde, 0x00, 0x01, 0x03]))
}

@Test func sparseContacts() throws {
    let records = try contactsFixture().records

    let solo = try Contact(data: records[1].data)
    #expect(solo[.lastName] == "Solo")
    #expect(solo.fields.compactMap { $0 } == ["Solo"])
    #expect(solo.birthday == nil && solo.blobs.isEmpty)

    let empty = try Contact(data: records[2].data)
    #expect(records[2].data.count == 17)
    #expect(empty.fields.allSatisfy { $0 == nil })
    #expect(empty == Contact())

    let company = try Contact(data: records[3].data)
    #expect(company[.company] == "Acme")
    #expect(company.phoneLabel(0) == 5)
    #expect(records[3].data[16] == 1)       // company offset: just the byte itself
    #expect(records[0].data[16] == 1 + 5 + 4)  // "Leto\0" and "Zoë\0" in front

    let noReminder = try Contact(data: records[4].data)
    #expect(noReminder.birthday == .init(date: PalmDate(year: 2000, month: 12, day: 31), reminderAdvance: nil, advanceUnits: 0))

    #expect(records[5].isDeleted && records[5].isDirty)
    #expect(records[6].isSecret && records[6].category == 3)
    #expect(try Contact(data: records[6].data)[.note]?.count == 400)
}

@Test func contactLabelsAreSetInTheRightNibbles() {
    var c = Contact(fields: [.lastName: "X"])
    c.setPhoneLabel(0, 7)
    c.setPhoneLabel(6, 1)
    c.showPhone = 3
    c.setAddressLabel(0, 1)
    c.setAddressLabel(1, 2)
    c.setAddressLabel(2, 0)
    c.setIMLabel(0, 2)
    c.setIMLabel(1, 4)
    #expect(c.labelBytes == [0x31, 0x00, 0x00, 0x07, 0x00, 0x21, 0x00, 0x42])
    let back = try! Contact(data: c.encode())
    #expect(back == c)
    #expect(back.phoneLabel(0) == 7 && back.phoneLabel(6) == 1 && back.showPhone == 3)
}

@Test func encodesContactFromScratchLikePilotLink() throws {
    var c = Contact(fields: [.company: "Acme", .phone1: "+1 800 555 0199"])
    c.setPhoneLabel(0, 5)
    #expect(c.encode() == (try contactsFixture().records[3].data))
}

@Test func contactAppInfo() throws {
    let data = try #require(try contactsFixture().appInfo)
    let info = try ContactAppInfo(data: data)
    #expect(info.categories.names.prefix(4) == ["Unfiled", "Business", "Personal", "QuickList"])
    #expect(info.labels.count == 53)
    #expect(info.labels[0] == "Last name" && info.labels[38] == "Note" && info.labels[40] == "Mobile")
    #expect(info.phoneLabels == ["Work", "Home", "Fax", "Other", "E-mail", "Main", "Pager", "Mobile"])
    #expect(info.country == 1)
    #expect(!info.sortByCompany)
    #expect(info.encode() == data)

    #expect(throws: PalmFormatError.invalidValue(field: "appInfo.size", value: 10)) {
        try ContactAppInfo(data: Data(count: 10))
    }
}
