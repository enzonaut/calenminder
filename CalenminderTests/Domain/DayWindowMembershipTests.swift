import Testing
import Foundation
@testable import CalenminderKit

/// DW-2.3: day-window membership boundary tests - midnight, all-day, DST
/// transition, and multi-day spans.
struct DayWindowMembershipTests {
    let cal = Fixture.calendar("America/New_York")

    func window(_ y: Int, _ m: Int, _ d: Int) -> DayWindow {
        DayWindow(day: DayStamp(year: y, month: m, day: d), calendar: cal)!
    }

    // MARK: midnight boundary

    @Test("DW-2.3: an event ending exactly at midnight belongs to the day it ends within, not the next")
    func test_DW_2_3_membershipMidnightBoundary() {
        // 22:00 Jul 3 -> 00:00 Jul 4 (ends exactly at the exclusive window end).
        let evt = Fixture.event(
            start: Fixture.date(cal, 2026, 7, 3, 22),
            end: Fixture.date(cal, 2026, 7, 4, 0)
        )
        #expect(window(2026, 7, 3).contains(evt))         // belongs to Jul 3
        #expect(!window(2026, 7, 4).contains(evt))        // NOT Jul 4
    }

    @Test("DW-2.3: an event starting at 23:59 belongs to that day (and the next, if it spills over)")
    func test_DW_2_3_membershipLateStartSpillover() {
        let evt = Fixture.event(
            start: Fixture.date(cal, 2026, 7, 3, 23, 59),
            end: Fixture.date(cal, 2026, 7, 4, 0, 30)
        )
        #expect(window(2026, 7, 3).contains(evt))         // starts within Jul 3
        #expect(window(2026, 7, 4).contains(evt))         // spills into Jul 4
        #expect(!window(2026, 7, 5).contains(evt))
    }

    @Test("An event entirely before the window is not a member")
    func eventBeforeWindowExcluded() {
        let evt = Fixture.event(
            start: Fixture.date(cal, 2026, 7, 2, 9),
            end: Fixture.date(cal, 2026, 7, 2, 10)
        )
        #expect(!window(2026, 7, 3).contains(evt))
    }

    // MARK: all-day

    @Test("DW-2.3: an all-day event is a member of its own day only")
    func test_DW_2_3_membershipAllDayEvent() {
        // All-day EventKit convention: start = civil midnight, end = midnight of
        // the following day (exclusive).
        let allDay = Fixture.event(
            start: Fixture.date(cal, 2026, 7, 3, 0),
            end: Fixture.date(cal, 2026, 7, 4, 0),
            allDay: true
        )
        #expect(!window(2026, 7, 2).contains(allDay))
        #expect(window(2026, 7, 3).contains(allDay))
        #expect(!window(2026, 7, 4).contains(allDay))
    }

    @Test("DW-2.3: a multi-day all-day event is a member of each day it spans")
    func test_DW_2_3_membershipMultiDayAllDay() {
        // Covers Jul 3 and Jul 4 (end is exclusive midnight of Jul 5).
        let allDay = Fixture.event(
            start: Fixture.date(cal, 2026, 7, 3, 0),
            end: Fixture.date(cal, 2026, 7, 5, 0),
            allDay: true
        )
        #expect(!window(2026, 7, 2).contains(allDay))
        #expect(window(2026, 7, 3).contains(allDay))
        #expect(window(2026, 7, 4).contains(allDay))
        #expect(!window(2026, 7, 5).contains(allDay))
    }

    // MARK: DST transition

    @Test("DW-2.3: membership holds across the spring-forward DST day (23-hour day)")
    func test_DW_2_3_membershipDSTTransition() {
        // 2026-03-08 is spring-forward in US Eastern: 02:00 -> 03:00 (no 02:xx).
        let dstWindow = window(2026, 3, 8)
        // Sanity: the civil day is only 23 real hours long.
        #expect(dstWindow.end.timeIntervalSince(dstWindow.start) == 23 * 3600)

        // An event around the missing hour (01:30 EST -> 03:30 EDT) is a member.
        let acrossGap = Fixture.event(
            start: Fixture.date(cal, 2026, 3, 8, 1, 30),
            end: Fixture.date(cal, 2026, 3, 8, 3, 30)
        )
        #expect(dstWindow.contains(acrossGap))
        #expect(!window(2026, 3, 7).contains(acrossGap))
        #expect(!window(2026, 3, 9).contains(acrossGap))

        // A late event ending exactly at the next civil midnight still belongs
        // only to the DST day, not the next.
        let lateNight = Fixture.event(
            start: Fixture.date(cal, 2026, 3, 8, 23),
            end: Fixture.date(cal, 2026, 3, 9, 0)
        )
        #expect(dstWindow.contains(lateNight))
        #expect(!window(2026, 3, 9).contains(lateNight))
    }

    @Test("Membership holds across the fall-back DST day (25-hour day)")
    func membershipFallBackDSTDay() {
        // 2026-11-01 is fall-back in US Eastern: 02:00 EDT -> 01:00 EST.
        let dstWindow = window(2026, 11, 1)
        #expect(dstWindow.end.timeIntervalSince(dstWindow.start) == 25 * 3600)

        let duringRepeatedHour = Fixture.event(
            start: Fixture.date(cal, 2026, 11, 1, 1, 30),
            end: Fixture.date(cal, 2026, 11, 1, 2, 30)
        )
        #expect(dstWindow.contains(duringRepeatedHour))
    }
}
