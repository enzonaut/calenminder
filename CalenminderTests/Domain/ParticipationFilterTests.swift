import Testing
import Foundation
@testable import CalenminderKit

/// DW-2.3: every participation status through BOTH filters.
/// `.agenda`: accepted/tentative/needsAction/notInvited kept, declined excluded.
/// `.widget`: accepted/tentative/notInvited only (declined + needsAction excluded).
struct ParticipationFilterTests {

    /// (status, agenda-includes, widget-includes) for all five statuses.
    static let table: [(ParticipationStatus, Bool, Bool)] = [
        (.accepted,    true,  true),
        (.tentative,   true,  true),
        (.notInvited,  true,  true),
        (.needsAction, true,  false),
        (.declined,    false, false),
    ]

    @Test("DW-2.3: each participation status resolves correctly through both filters", arguments: table)
    func test_DW_2_3_eachParticipationStatusThroughBothFilters(
        _ row: (status: ParticipationStatus, agenda: Bool, widget: Bool)
    ) {
        #expect(AgendaFilter.agenda.includes(row.status) == row.agenda)
        #expect(AgendaFilter.widget.includes(row.status) == row.widget)
    }

    @Test("The table covers every ParticipationStatus case")
    func tableCoversAllStatuses() {
        let covered = Set(Self.table.map(\.0))
        #expect(covered == Set(ParticipationStatus.allCases))
        #expect(ParticipationStatus.allCases.count == 5)
    }

    @Test("Declined is the only status excluded from the in-app agenda")
    func onlyDeclinedExcludedFromAgenda() {
        let excluded = ParticipationStatus.allCases.filter { !AgendaFilter.agenda.includes($0) }
        #expect(excluded == [.declined])
    }

    @Test("Widget excludes exactly declined and needsAction")
    func widgetExcludesDeclinedAndNeedsAction() {
        let excluded = Set(ParticipationStatus.allCases.filter { !AgendaFilter.widget.includes($0) })
        #expect(excluded == [.declined, .needsAction])
    }
}
