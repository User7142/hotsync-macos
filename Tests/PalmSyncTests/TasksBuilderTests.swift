import Foundation
import Testing
@testable import PalmSync

private let home = TasksBuilder.MacList(id: "l-home", title: "Home")
private let work = TasksBuilder.MacList(id: "l-work", title: "Work")
private let today = PalmDate(year: 2026, month: 10, day: 25)
private let builder = TasksBuilder(options: .init(lists: [home, work], today: today))

private func decoded(_ db: PalmDatabase) -> [PalmTask] { db.records.map { try! PalmTask(data: $0.data) } }

@Test func remindersBecomeTasks() {
    let (db, report) = builder.build([
        MacReminder(id: "1", listID: "l-home", title: "Buy milk", notes: "2%", dueDate: PalmDate(year: 2026, month: 10, day: 26),
                    dueTime: PalmTime(hour: 18, minute: 0), priority: 5),
        MacReminder(id: "2", listID: "l-work", title: "Report", url: URL(string: "https://example.com/r"), priority: 1),
        MacReminder(id: "3", listID: "l-home", title: "  ", priority: 9),
    ])
    #expect(report.records == 3 && report.categories == ["Unfiled", "Home", "Work"])
    let tasks = decoded(db)
    // the due one first
    #expect(tasks[0].title == "Buy milk" && tasks[0].priority == 3 && tasks[0].note == "2%")
    #expect(tasks[0].alarm == PalmTask.Alarm(time: PalmTime(hour: 18, minute: 0), daysEarlier: 0))
    #expect(db.records[0].category == 1)
    #expect(tasks[1].title == "Report" && tasks[1].priority == 1 && tasks[1].note == "https://example.com/r")
    #expect(db.records[1].category == 2)
    #expect(tasks[2].title == "(untitled)" && tasks[2].priority == 5)
    #expect(db.version == 1 && db.appInfo?.count == TaskAppInfo.size)
    #expect(try! TaskAppInfo(data: db.appInfo!).categories.names[1] == "Home")
}

@Test func alarmsAndRepeats() {
    let due = PalmDate(year: 2026, month: 10, day: 30)
    let (db, report) = builder.build([
        MacReminder(id: "a", listID: "l-home", title: "Alarm", dueDate: due,
                    alarmDate: PalmDate(year: 2026, month: 10, day: 23), alarmTime: PalmTime(hour: 5, minute: 20)),
        MacReminder(id: "w", listID: "l-home", title: "Weekly", dueDate: due,
                    recurrence: .init(frequency: .weekly, daysOfTheWeek: [.init(6)])),
        MacReminder(id: "c", listID: "l-home", title: "Counted", dueDate: due,
                    recurrence: .init(frequency: .daily, end: .count(3))),
        MacReminder(id: "n", listID: "l-home", title: "No due date", recurrence: .init(frequency: .daily)),
    ])
    let tasks = Dictionary(uniqueKeysWithValues: decoded(db).map { ($0.title, $0) })
    #expect(tasks["Alarm"]?.alarm == PalmTask.Alarm(time: PalmTime(hour: 5, minute: 20), daysEarlier: 7))
    // the same bytes the T|X wrote for its own "Alarm" task
    #expect(tasks["Alarm"]?.encode() == Data([0xa8, 0, 0, 0, 0, 1, 0xf5, 0x5e, 0x05, 0x14, 0x00, 0x07] + Array("Alarm".utf8) + [0, 0]))
    #expect(tasks["Weekly"]?.repeatRule?.rule.weekdays == [.friday])
    #expect(tasks["Weekly"]?.repeatRule?.start == due)
    #expect(tasks["Counted"]?.repeatRule == nil && tasks["No due date"]?.repeatRule == nil)
    #expect(report.rulesDropped == 1)   // the counted one; a rule without a due date is just ignored
}

@Test func oldCompletedRemindersStayOnTheMac() {
    let (db, report) = builder.build([
        MacReminder(id: "1", listID: "l-home", title: "Recent", dueDate: PalmDate(year: 2026, month: 10, day: 20),
                    completionDate: PalmDate(year: 2026, month: 10, day: 21)),
        MacReminder(id: "2", listID: "l-home", title: "Old", dueDate: PalmDate(year: 2026, month: 8, day: 1),
                    completionDate: PalmDate(year: 2026, month: 8, day: 2)),
    ])
    #expect(report.records == 1 && report.completedSkipped == 1)
    let recent = decoded(db)[0]
    #expect(recent.isCompleted && recent.completedDate == PalmDate(year: 2026, month: 10, day: 21))
    #expect(recent.encode()[0] & 0x40 != 0 && recent.encode()[3] == 1)
}

@Test func priorities() {
    #expect([0, 1, 2, 4, 5, 6, 8, 9].map(TasksBuilder.palmPriority) == [1, 1, 2, 2, 3, 4, 4, 5])
}

@Test func tasksDatabaseReadsBack() throws {
    let (db, _) = builder.build([MacReminder(id: "1", listID: "l-work", title: "X", dueDate: today)])
    let data = db.encode()
    let back = try PalmDatabase(data: data)
    #expect(back == db && back.name == "TasksDB-PTod" && back.creator == "PTod")
    #expect(try PalmTask(data: back.records[0].data).encode() == back.records[0].data)
}
