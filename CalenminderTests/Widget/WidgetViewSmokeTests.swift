import Testing
import Foundation
import SwiftUI
import CalenminderKit

/// DW-5.4's pragmatic substitute for image-diff snapshot tests (no
/// snapshot-testing library is installable in this sandbox - see the Phase
/// 4 discovery doc, which established `ViewRenderProbe` for exactly this).
/// `CalenminderWidget`'s real interactive layout cannot be linked into this
/// test target at all (an app-extension product cannot link into a
/// unit-test bundle - confirmed Phase 1), so these render the
/// non-interactive `CalenminderKit` row/state content that the real widget
/// composes verbatim (see `WidgetAgendaViews.swift`'s doc comment).
@MainActor
struct WidgetViewSmokeTests {
    @Test("DW-5.4: EmptyAgendaView renders without crashing")
    func emptyAgendaViewRenders() {
        let size = ViewRenderProbe.renderedSize(EmptyAgendaView().frame(width: 160, height: 60))
        #expect(size != nil && size!.width > 0 && size!.height > 0)
    }

    @Test("DW-5.4: PermissionMissingView renders for every unavailable reason without crashing")
    func test_DW_5_4_permissionMissingViewRendersForEveryReason() {
        let reasons: [WidgetUnavailableReason] = [.remindersAccessDenied, .calendarsAccessDenied, .loadFailed]
        for reason in reasons {
            let size = ViewRenderProbe.renderedSize(PermissionMissingView(reason: reason).frame(width: 160, height: 60))
            #expect(size != nil && size!.width > 0 && size!.height > 0, "PermissionMissingView failed to render for \(reason)")
        }
    }

    @Test("DW-5.4: EventRowContentView renders for both timed and all-day events without crashing")
    func eventRowContentViewRenders() {
        let cal = Fixture.calendar("America/New_York")
        let timed = Fixture.event(id: "e1", title: "Standup", start: Fixture.date(cal, 2026, 7, 3, 9), end: Fixture.date(cal, 2026, 7, 3, 9, 30))
        let allDay = Fixture.event(id: "e2", title: "Holiday", start: Fixture.date(cal, 2026, 7, 3), end: Fixture.date(cal, 2026, 7, 4), allDay: true)
        for event in [timed, allDay] {
            let size = ViewRenderProbe.renderedSize(EventRowContentView(event: event).frame(width: 160, height: 30))
            #expect(size != nil && size!.width > 0 && size!.height > 0)
        }
    }

    @Test("DW-5.4: TaskRowContentView renders without crashing")
    func taskRowContentViewRenders() {
        let task = Fixture.task(id: "t1", title: "Water plants", due: DayStamp(year: 2026, month: 7, day: 3))
        let size = ViewRenderProbe.renderedSize(TaskRowContentView(task: task).frame(width: 160, height: 30))
        #expect(size != nil && size!.width > 0 && size!.height > 0)
    }

    @Test("DW-5.4: OverflowRowView renders for singular and plural counts without crashing")
    func overflowRowViewRenders() {
        for count in [1, 3] {
            let size = ViewRenderProbe.renderedSize(OverflowRowView(count: count, noun: "task").frame(width: 160, height: 20))
            #expect(size != nil && size!.width > 0 && size!.height > 0)
        }
    }
}
