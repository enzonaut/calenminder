import Testing
import Foundation
@testable import CalenminderKit

/// Direct coverage of the domain value types' load-bearing behavior:
/// durable-identifier composition and the garbled-identifier guard the agenda
/// assembly relies on.
struct DomainModelTests {
    let cal = Fixture.calendar()

    @Test("Event.id composes the durable external identifier with the occurrence date")
    func eventIDComposesDurableKey() {
        let occ = Fixture.date(cal, 2026, 7, 3, 9)
        let evt = Fixture.event(id: "abc", start: occ, end: occ.addingTimeInterval(3600), occurrence: occ)
        #expect(evt.id == EventID(externalIdentifier: "abc", occurrenceDate: occ))
    }

    @Test("Two occurrences of one recurring series share an external id but differ by occurrence date")
    func recurringOccurrencesDifferByDate() {
        let first = Fixture.date(cal, 2026, 7, 3, 9)
        let second = Fixture.date(cal, 2026, 7, 10, 9)
        let a = Fixture.event(id: "series", start: first, end: first.addingTimeInterval(3600), occurrence: first)
        let b = Fixture.event(id: "series", start: second, end: second.addingTimeInterval(3600), occurrence: second)
        #expect(a.externalIdentifier == b.externalIdentifier)
        #expect(a.id != b.id)
    }

    @Test("hasValidIdentifier rejects empty and whitespace-only identifiers")
    func hasValidIdentifierGuard() {
        let base = Fixture.date(cal, 2026, 7, 3, 9)
        #expect(Fixture.event(id: "ok", start: base, end: base).hasValidIdentifier)
        #expect(!Fixture.event(id: "", start: base, end: base).hasValidIdentifier)
        #expect(!Fixture.event(id: "  \t", start: base, end: base).hasValidIdentifier)

        let day = DayStamp(year: 2026, month: 7, day: 3)
        #expect(Fixture.task(id: "ok", due: day).hasValidIdentifier)
        #expect(!Fixture.task(id: " ", due: day).hasValidIdentifier)
    }

    @Test("DayTask id is its external identifier")
    func dayTaskIDIsExternalIdentifier() {
        let task = Fixture.task(id: "reminder-123", due: DayStamp(year: 2026, month: 7, day: 3))
        #expect(task.id == "reminder-123")
    }

    @Test("EditSpan and drafts carry their values")
    func draftsAndSpanValues() {
        let day = DayStamp(year: 2026, month: 7, day: 3)
        let taskDraft = TaskDraft(title: "Recycling", dueDay: day, recurrence: .weekly(weekday: 2))
        #expect(taskDraft.recurrence == .weekly(weekday: 2))

        let start = Fixture.date(cal, 2026, 7, 3, 9)
        let eventDraft = EventDraft(title: "Standup", start: start, end: start.addingTimeInterval(1800), isAllDay: false)
        #expect(eventDraft.calendarIdentifier == nil)  // default calendar
        #expect(EditSpan.thisEvent != EditSpan.futureEvents)
    }
}
