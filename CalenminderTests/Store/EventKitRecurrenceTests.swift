import Testing
import Foundation
import EventKit
@testable import CalenminderKit

/// Pure translation between `TaskRecurrence` and `EKRecurrenceRule`.
/// `EKRecurrenceRule` needs no `EKEventStore` to construct, so this runs with
/// zero EventKit runtime dependency -- including the "second rule silently
/// dropped" dirty case from the plan's Test Plan (T-3.2).
struct EventKitRecurrenceTests {
    @Test("weeklyRule(weekday:) builds a plain weekly-by-one-weekday rule")
    func weeklyRuleBuildsExpectedShape() {
        let rule = EventKitRecurrence.weeklyRule(weekday: 2)
        #expect(rule?.frequency == .weekly)
        #expect(rule?.interval == 1)
        #expect(rule?.daysOfTheWeek?.map(\.dayOfTheWeek.rawValue) == [2])
    }

    @Test("weeklyRule(weekday:) returns nil for an out-of-range weekday (defensive, no crash)")
    func weeklyRuleReturnsNilForGarbledWeekday() {
        #expect(EventKitRecurrence.weeklyRule(weekday: 0) == nil)
        #expect(EventKitRecurrence.weeklyRule(weekday: 8) == nil)
    }

    @Test("weeklyWeekday(from:) reads back the weekday of a single weekly rule")
    func weeklyWeekdayReadsBackSingleRule() {
        let rule = EventKitRecurrence.weeklyRule(weekday: 5)!
        #expect(EventKitRecurrence.weeklyWeekday(from: [rule]) == 5)
    }

    @Test("weeklyWeekday(from:) returns nil for no rules")
    func weeklyWeekdayReturnsNilForNoRules() {
        #expect(EventKitRecurrence.weeklyWeekday(from: nil) == nil)
        #expect(EventKitRecurrence.weeklyWeekday(from: []) == nil)
    }

    @Test("weeklyWeekday(from:) silently drops a second recurrence rule, reading only the first")
    func weeklyWeekdaySilentlyDropsSecondRule() {
        let first = EventKitRecurrence.weeklyRule(weekday: 3)!
        let second = EventKitRecurrence.weeklyRule(weekday: 6)!
        #expect(EventKitRecurrence.weeklyWeekday(from: [first, second]) == 3)
    }

    @Test("weeklyWeekday(from:) returns nil for a daily rule (not the shape this app writes)")
    func weeklyWeekdayReturnsNilForNonWeeklyRule() {
        let daily = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        #expect(EventKitRecurrence.weeklyWeekday(from: [daily]) == nil)
    }

    @Test("weeklyWeekday(from:) returns nil for a weekly rule spanning multiple weekdays")
    func weeklyWeekdayReturnsNilForMultiWeekdayRule() {
        let rule = EKRecurrenceRule(
            recurrenceWith: .weekly, interval: 1,
            daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday), EKRecurrenceDayOfWeek(.tuesday)],
            daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil
        )
        #expect(EventKitRecurrence.weeklyWeekday(from: [rule]) == nil)
    }

    // MARK: - DW-F1.2: daily

    @Test("DW-F1.2: dailyRule() builds EKRecurrenceRule(.daily, interval: 1)")
    func test_DW_F1_2_dailyRuleBuildsExpectedShape() {
        let rule = EventKitRecurrence.dailyRule()
        #expect(rule.frequency == .daily)
        #expect(rule.interval == 1)
    }

    @Test("DW-F1.2: isDaily(from:) reads back a plain daily rule")
    func test_DW_F1_2_isDailyReadsBackDailyRule() {
        let rule = EventKitRecurrence.dailyRule()
        #expect(EventKitRecurrence.isDaily(from: [rule]) == true)
    }

    @Test("isDaily(from:) returns false for no rules")
    func isDailyReturnsFalseForNoRules() {
        #expect(EventKitRecurrence.isDaily(from: nil) == false)
        #expect(EventKitRecurrence.isDaily(from: []) == false)
    }

    @Test("isDaily(from:) returns false for a weekly rule (not the shape this app writes for daily)")
    func isDailyReturnsFalseForWeeklyRule() {
        let weekly = EventKitRecurrence.weeklyRule(weekday: 2)!
        #expect(EventKitRecurrence.isDaily(from: [weekly]) == false)
    }

    @Test("isDaily(from:) returns false for a daily rule with an interval other than 1")
    func isDailyReturnsFalseForNonUnitInterval() {
        let everyOtherDay = EKRecurrenceRule(recurrenceWith: .daily, interval: 2, end: nil)
        #expect(EventKitRecurrence.isDaily(from: [everyOtherDay]) == false)
    }

    @Test("isDaily(from:) silently drops a second recurrence rule, reading only the first")
    func isDailySilentlyDropsSecondRule() {
        let daily = EventKitRecurrence.dailyRule()
        let weekly = EventKitRecurrence.weeklyRule(weekday: 3)!
        #expect(EventKitRecurrence.isDaily(from: [daily, weekly]) == true)
        #expect(EventKitRecurrence.isDaily(from: [weekly, daily]) == false)
    }
}
