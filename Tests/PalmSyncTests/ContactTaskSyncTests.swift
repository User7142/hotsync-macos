import Foundation
import Testing
@testable import PalmSync

// MARK: - Contacts through the generic engine

private let contactCategories = ["Unfiled", "Friends", "Work"]
private let contactsBuilder = ContactsBuilder(options: .init(containers: [.init(id: "icloud", title: "iCloud")]))

private func macContact(_ id: String, _ first: String, _ last: String, group: String? = "Friends",
                        phones: [MacContact.Labeled] = [.init("mobile", "+1 604 555 0101")]) -> MacContact {
    MacContact(id: id, containerID: "icloud", groups: group.map { [$0] } ?? [], firstName: first, lastName: last, phones: phones)
}

private func palmContact(id: UInt32, _ first: String, _ last: String, category: Int = 1, attributes: UInt8 = 0,
                         phone: String = "+1 604 555 0101") -> PalmRecordIn {
    var c = Contact(fields: [.firstName: first, .lastName: last, .phone1: phone])
    c.setPhoneLabel(0, ContactsBuilder.PhoneLabel.mobile.rawValue)
    return PalmRecordIn(id: id, attributes: attributes, category: category, data: c.encode())
}

@Test func syncedContactRoundTripsThroughTheRecord() throws {
    var record = Contact(fields: [.firstName: "Zoë", .lastName: "Leto", .company: "PacketLoq", .custom1: "keep me",
                                  .note: "Palm-only note", .phone1: "+1 604 555 0101", .phone2: "zoe@example.com",
                                  .address1: "1 Main St", .city1: "Vancouver", .im1: "zoe"])
    record.setPhoneLabel(0, ContactsBuilder.PhoneLabel.mobile.rawValue)
    record.setPhoneLabel(1, ContactsBuilder.PhoneLabel.email.rawValue)
    record.setAddressLabel(0, ContactsBuilder.AddressLabel.work.rawValue)
    record.setIMLabel(0, ContactsBuilder.IMLabel.aim.rawValue)
    record.birthday = .init(date: PalmDate(year: 1990, month: 5, day: 6), reminderAdvance: 3, advanceUnits: 2)

    let synced = SyncedContact(record, category: "Friends")
    #expect(synced.phones.count == 2 && synced.phones[1].isEmail)
    #expect(synced.addresses == [.init(label: 1, street: "1 Main St", city: "Vancouver")])
    #expect(synced.instantMessages == [.init(service: 0, value: "zoe")])
    #expect(synced.birthday == PalmDate(year: 1990, month: 5, day: 6))

    // applying it back over the record keeps what it does not cover
    var edited = synced
    edited.lastName = "Leto-Smith"
    edited.phones = [edited.phones[0]]
    let bytes = edited.palmBytes(over: record.encode())
    let back = try Contact(data: bytes)
    #expect(back[.lastName] == "Leto-Smith" && back[.custom1] == "keep me" && back[.note] == "Palm-only note")
    #expect(back[.phone2] == nil && back.phoneLabel(1) == 0)
    #expect(back.birthday?.reminderAdvance == 3)
    #expect(SyncedContact(back, category: "Friends") == edited)
}

@Test func contactsSlowSyncPairsByName() throws {
    let engine = SyncEngine<SyncedContact>()
    let mac = contactsBuilder.syncItems([macContact("c1", "Zoë", "Leto"), macContact("c2", "Rose", "Tyler", group: "Work")])
    let palm = PalmSnapshot.all([palmContact(id: 0x3001, "Zoë", "Leto", phone: "+1 604 555 0199"),
                                 palmContact(id: 0x3002, "Larry", "Blue", category: 0)])
    let plan = try engine.plan(palm: palm, palmCategories: contactCategories, mac: mac, mirror: ContactMirror(pcID: 7))

    // Zoë paired (no base: the Mac's phone wins over the Palm's), Rose new on the Palm, Larry new on the Mac
    #expect(plan.log.contains("Zoë Leto: found on both sides, paired"))
    #expect(plan.palmWrites.count == 2 && plan.palmWrites.contains { $0.id == 0x3001 })
    #expect(try Contact(data: plan.palmWrites.first { $0.id == 0x3001 }!.record)[.phone1] == "+1 604 555 0101")
    #expect(plan.macCreates.count == 1 && plan.macCreates[0].item.title == "Larry Blue")
    #expect(plan.conflicts.isEmpty)

    // the whole database keeps the Palm's AppInfo and sorts by name
    let appInfo = ContactAppInfo(categories: CategoryAppInfo(names: contactCategories), labels: ContactsBuilder.standardLabels, country: 4)
    let (db, palmIDs, _) = plan.palmDatabase(appInfo: appInfo)
    #expect(db.records.count == 3 && palmIDs.count == 1)
    #expect(try db.records.map { try Contact(data: $0.data)[.lastName] } == ["Blue", "Leto", "Tyler"])
    #expect(try ContactAppInfo(data: db.appInfo!).country == 4)
    #expect(db.records.first { $0.uniqueID == 0x3002 }?.category == 0)
}

@Test func contactsFastSyncMergesFieldByField() throws {
    let engine = SyncEngine<SyncedContact>()
    let mac = contactsBuilder.syncItems([macContact("c1", "Zoë", "Leto")])
    let first = try engine.plan(palm: .all([palmContact(id: 0x3001, "Zoë", "Leto")]), palmCategories: contactCategories,
                                mac: mac, mirror: ContactMirror(pcID: 7))
    let mirror = first.mirror(after: ContactMirror(pcID: 7), palmIDs: [:], macKeys: [:])
    #expect(mirror.entries.count == 1)

    // the Palm changed the phone, the Mac the last name
    let palmEdit = palmContact(id: 0x3001, "Zoë", "Leto", attributes: 0x40, phone: "+1 604 555 0200")
    let macEdit = contactsBuilder.syncItems([macContact("c1", "Zoë", "Leto-Smith")])
    let plan = try engine.plan(palm: .modified([palmEdit]), palmCategories: contactCategories, mac: macEdit, mirror: mirror)
    #expect(plan.conflicts.isEmpty)
    let toPalm = try Contact(data: plan.palmWrites[0].record)
    #expect(toPalm[.lastName] == "Leto-Smith" && toPalm[.phone1] == "+1 604 555 0200")
    #expect(plan.macUpdates[0].item.phones[0].value == "+1 604 555 0200" && plan.macUpdates[0].item.lastName == "Leto-Smith")
}

// MARK: - Tasks through the generic engine

private let today = PalmDate(year: 2026, month: 10, day: 25)
private let tasksBuilder = TasksBuilder(options: .init(lists: [.init(id: "l1", title: "Family")], keepCompletedDays: 30, today: today))

@Test func syncedTaskRoundTripsThroughTheRecord() throws {
    var task = PalmTask(title: "Buy milk", note: "2 l", priority: 3, dueDate: PalmDate(year: 2026, month: 10, day: 27),
                        alarm: .init(time: PalmTime(hour: 9, minute: 30), daysEarlier: 1))
    task.unknown = (1, 2, 3)
    let synced = SyncedTask(task, category: "Family")
    #expect(synced.alarm == .init(time: PalmTime(hour: 9, minute: 30), daysEarlier: 1) && synced.priority == 3)

    var edited = synced
    edited.completedDate = today
    edited.note = nil
    let back = try PalmTask(data: edited.palmBytes(over: task.encode()))
    #expect(back.isCompleted && back.note.isEmpty && back.unknown == (1, 2, 3))
    #expect(SyncedTask(back, category: "Family") == edited)
}

@Test func tasksSyncWithTheCompletedWindow() throws {
    let engine = SyncEngine<SyncedTask>(inWindow: tasksBuilder.inWindow)
    let old = MacReminder(id: "r-old", listID: "l1", title: "Old chore", completionDate: PalmDate(year: 2026, month: 1, day: 1))
    let milk = MacReminder(id: "r-milk", listID: "l1", title: "Buy milk", dueDate: PalmDate(year: 2026, month: 10, day: 27), priority: 5)
    let mac = tasksBuilder.syncItems([old, milk])
    #expect(mac.count == 1)   // the old completed one is not the Palm's business

    let palmTask = PalmTask(title: "Call Larry", priority: 2)
    let palm = PalmRecordIn(id: 0x4001, category: 1, data: palmTask.encode())
    let plan = try engine.plan(palm: .all([palm]), palmCategories: ["Unfiled", "Family"], mac: mac, mirror: TaskMirror(pcID: 7))
    #expect(plan.palmWrites.count == 1 && plan.macCreates.count == 1)
    #expect(try PalmTask(data: plan.palmWrites[0].record).priority == 3)
    #expect(plan.macCreates[0].item.title == "Call Larry")

    // once synced and then completed long ago on the Mac, it leaves the Palm without being deleted on the Mac
    let mirror = plan.mirror(after: TaskMirror(pcID: 7), palmIDs: [plan.palmWrites[0].entry: 0x4002], macKeys: [plan.macCreates[0].entry: MacKey(seriesID: "r-larry")])
    var doneLongAgo = SyncedTask(palmTask, category: "Family")
    doneLongAgo.completedDate = PalmDate(year: 2026, month: 2, day: 1)
    var aged = mirror
    let larry = try #require(aged.entries.firstIndex { $0.mac.seriesID == "r-larry" })
    aged.entries[larry].base = doneLongAgo
    let next = try engine.plan(palm: .modified([]), palmCategories: ["Unfiled", "Family"], mac: tasksBuilder.syncItems([milk]), mirror: aged)
    #expect(next.agedOut == [0x4001] && next.palmDeletes.isEmpty && next.macDeletes.isEmpty && next.palmWrites.isEmpty)
    #expect(next.log.contains { $0.contains("left the window") })

    let (db, _, _) = plan.palmDatabase(appInfo: TaskAppInfo(categories: CategoryAppInfo(names: ["Unfiled", "Family"])))
    #expect(db.name == "TasksDB-PTod" && db.records.count == 2)
    #expect(try PalmTask(data: db.records[0].data).title == "Buy milk")   // due ones first
    #expect(try PalmDatabase(data: db.encode()) == db)
}
