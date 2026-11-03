import Foundation
import Testing
@testable import PalmSync

/// TasksDB-PTod.pdb from a T|X, with sample tasks made on the device on
/// 2026-10-24: plain, with a due date, repeating, completed, with a note.
private func tasksFixture() throws -> PalmDatabase {
    let url = try #require(Bundle.module.url(forResource: "TasksDB-PTod", withExtension: "pdb", subdirectory: "Fixtures/device"))
    return try PalmDatabase(data: try Data(contentsOf: url))
}

private func task(_ title: String) throws -> PalmTask {
    let db = try tasksFixture()
    for record in db.records {
        if let task = try? PalmTask(data: record.data), task.title == title { return task }
    }
    Issue.record("no task \(title)")
    throw PalmFormatError.truncated(at: 0)
}

@Test func everyDeviceTaskRoundTripsByteForByte() throws {
    let db = try tasksFixture()
    #expect(db.records.count == 7)
    for record in db.records {
        let task = try PalmTask(data: record.data)
        #expect(task.encode() == record.data, "\(task.title)")
    }
    let info = try TaskAppInfo(data: try #require(db.appInfo))
    #expect(info.categories.names.prefix(3) == ["Unfiled", "Business", "Personal"])
    #expect(info.encode() == db.appInfo)
    #expect(info.internalBytes == TaskAppInfo().internalBytes)
}

@Test func plainTask() throws {
    let plain = try task("Plain")
    #expect(plain.dueDate == nil && plain.completedDate == nil && plain.repeatRule == nil)
    #expect(plain.priority == 1 && plain.note == "")
    #expect(plain == PalmTask(title: "Plain"))
    #expect(PalmTask(title: "Plain").encode() == Data([0x08, 0, 0, 0, 0, 1] + Array("Plain".utf8) + [0, 0]))
}

@Test func dueDateAndPriority() throws {
    let due = try task("Due tomorrow")
    #expect(due.dueDate == PalmDate(year: 2026, month: 10, day: 26))
    #expect(due.priority == 3)
    #expect(!due.isCompleted)
}

@Test func completedTask() throws {
    let done = try task("HI")
    #expect(done.dueDate == PalmDate(year: 2026, month: 10, day: 25))
    #expect(done.completedDate == PalmDate(year: 2026, month: 10, day: 24))
    #expect(done.isCompleted)
}

@Test func repeatingTask() throws {
    let weekly = try task("Weelkly")
    let (start, rule) = try #require(weekly.repeatRule)
    #expect(start == PalmDate(year: 2026, month: 10, day: 30))
    #expect(rule.type == .weekly && rule.frequency == 1 && rule.endDate == nil)
    #expect(rule.weekdays == [.friday])
}

@Test func noteAndCategory() throws {
    let db = try tasksFixture()
    let register = try #require(db.records.first { (try? PalmTask(data: $0.data))?.title.hasPrefix("Don't forget") == true })
    let t = try PalmTask(data: register.data)
    #expect(t.note.hasPrefix("To register your Palm"))
    #expect(register.category == 2)   // Personal
    let business = try #require(db.records.first { (try? PalmTask(data: $0.data))?.title == "TEST Task" })
    #expect(business.category == 1)
}

@Test func alarmTask() throws {
    let alarm = try task("Alarm")
    #expect(alarm.dueDate == PalmDate(year: 2026, month: 10, day: 30))
    #expect(alarm.alarm == .init(time: PalmTime(hour: 5, minute: 20), daysEarlier: 7))
    #expect(alarm.encode()[0] == 0xA8)
    #expect(throws: PalmFormatError.self) {
        try PalmTask(data: Data([0xA8, 0, 0, 0, 0, 1, 0xf5, 0x5a, 25, 0, 0, 0, 0x41, 0, 0]))   // hour 25
    }
}

@Test func tasksFromScratch() {
    var t = PalmTask(title: "Rent", note: "e-transfer", priority: 2, dueDate: PalmDate(year: 2026, month: 11, day: 1))
    t.repeatRule = (PalmDate(year: 2026, month: 11, day: 1), .init(type: .monthlyByDate, frequency: 1))
    let back = try! PalmTask(data: t.encode())
    #expect(back == t)
    #expect(back.note == "e-transfer" && back.repeatRule?.rule.type == .monthlyByDate)
    #expect(t.encode()[0] == 0x80 | 0x10 | 0x08 | 0x04)
}
