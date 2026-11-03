import Contacts
import EventKit
import Foundation
import Testing
import PalmSync
@testable import PalmSyncMac

// The mapping only: contacts and reminders are made and filled, never saved.

@Test func contactFillRewritesOnlyWhatThePalmChanged() {
    let c = CNMutableContact()
    c.givenName = "Zoë"
    c.middleName = "A"
    c.familyName = "Leto"
    c.phoneNumbers = [
        CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "+1 604 555 0101")),
        CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: "+1 604 555 0100")),
    ]
    c.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: "zoe@example.com")]
    c.urlAddresses = [CNLabeledValue(label: CNLabelURLAddressHomePage, value: "https://example.com")]
    c.postalAddresses = [CNLabeledValue(label: CNLabelHome, value: CNMutablePostalAddress())]

    // what the Palm has, with the last name and the mobile number changed
    var item = SyncedContact(ContactSource.macContact(c, containerID: "", groups: []), category: "Friends")
    #expect(item.firstName == "Zoë A")   // the builder joins first and middle
    item.lastName = "Leto-Smith"
    item.phones[0].value = "+1 604 555 0199"

    ContactWriter.fill(c, from: item)
    #expect(c.familyName == "Leto-Smith")
    #expect(c.givenName == "Zoë" && c.middleName == "A")   // untouched: the Palm did not change the first name
    #expect(c.phoneNumbers.map { $0.value.stringValue } == ["+1 604 555 0199", "+1 604 555 0100"])
    #expect(c.phoneNumbers[1].label == CNLabelWork)   // a kept value keeps its own label
    #expect(c.emailAddresses.map { String($0.value) } == ["zoe@example.com"] && c.emailAddresses[0].label == CNLabelWork)
    #expect(c.urlAddresses.count == 1 && c.postalAddresses.count == 1)
}

@Test func contactFillFromThePalmAlone() {
    let c = CNMutableContact()
    let item = SyncedContact(lastName: "Blue", firstName: "Larry", company: "DataFort",
                             phones: [.init(label: ContactsBuilder.PhoneLabel.work.rawValue, value: "+1 604 555 0300"),
                                      .init(label: ContactsBuilder.PhoneLabel.email.rawValue, value: "larry@example.com")],
                             addresses: [.init(label: ContactsBuilder.AddressLabel.work.rawValue, street: "9 Harbour Rd", city: "Vancouver")],
                             website: "https://datafort.example", birthday: PalmDate(year: 1980, month: 2, day: 3), category: "Work")
    ContactWriter.fill(c, from: item)
    #expect(c.givenName == "Larry" && c.familyName == "Blue" && c.organizationName == "DataFort")
    #expect(c.phoneNumbers.count == 1 && c.phoneNumbers[0].label == CNLabelWork)
    #expect(c.emailAddresses.count == 1 && String(c.emailAddresses[0].value) == "larry@example.com")
    #expect(c.postalAddresses[0].value.street == "9 Harbour Rd" && c.postalAddresses[0].label == CNLabelWork)
    #expect(c.urlAddresses.first.map { String($0.value) } == "https://datafort.example")
    #expect(c.birthday?.year == 1980 && c.birthday?.day == 3)
    // and it reads back as the same shared fields
    #expect(SyncedContact(ContactSource.macContact(c, containerID: "", groups: []), category: "Work") == item)
}

private let store = EKEventStore()
private let vancouver: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Vancouver")!
    return c
}()
private let writer = TaskWriter(store: store, homeZone: vancouver.timeZone, today: PalmDate(year: 2026, month: 10, day: 25)) { _ in nil }

@Test func reminderFillFromThePalm() {
    let r = EKReminder(eventStore: store)
    let item = SyncedTask(title: "Buy milk", note: "2 l", dueDate: PalmDate(year: 2026, month: 10, day: 27), priority: 3,
                          alarm: .init(time: PalmTime(hour: 9, minute: 30), daysEarlier: 1), category: "Family")
    writer.fill(r, from: item)
    #expect(r.title == "Buy milk" && r.notes == "2 l" && r.priority == 5)
    #expect(r.dueDateComponents?.day == 27 && r.dueDateComponents?.hour == nil)
    let fire = r.alarms?.first?.absoluteDate
    #expect(fire.map { vancouver.dateComponents([.day, .hour, .minute], from: $0) } == DateComponents(day: 26, hour: 9, minute: 30))
    #expect(!r.isCompleted)

    // completing it on the Palm
    var done = item
    done.completedDate = PalmDate(year: 2026, month: 10, day: 26)
    writer.fill(r, from: done)
    #expect(r.isCompleted && r.completionDate.map { vancouver.component(.day, from: $0) } == 26)
    #expect(r.alarms?.count == 1)   // the alarm field did not change, so it was left alone
}

@Test func reminderFillKeepsTheURLAndTheDueTime() {
    let r = EKReminder(eventStore: store)
    r.title = "Read"
    r.notes = "the manual"
    r.url = URL(string: "https://example.com/manual")
    r.dueDateComponents = DateComponents(year: 2026, month: 10, day: 27, hour: 18, minute: 0)
    // what the Palm got from the builder: the URL on the note's last line, the due time as an alarm
    var item = SyncedTask(TasksBuilder(options: .init(lists: [], today: PalmDate(year: 2026, month: 10, day: 25)))
                            .palmTask(ReminderSource.macReminder(r, calendar: vancouver)), category: "Unfiled")
    #expect(item.note == "the manual\nhttps://example.com/manual")
    item.note = "the whole manual\nhttps://example.com/manual"
    item.dueDate = PalmDate(year: 2026, month: 10, day: 28)
    writer.fill(r, from: item)
    #expect(r.notes == "the whole manual" && r.url?.absoluteString == "https://example.com/manual")
    #expect(r.dueDateComponents?.day == 28 && r.dueDateComponents?.hour == 18)
}
