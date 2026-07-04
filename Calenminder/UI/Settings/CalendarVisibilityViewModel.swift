import Foundation
import CalenminderKit

@MainActor
final class CalendarVisibilityViewModel: ObservableObject {
    @Published private(set) var calendars: [EventCalendarInfo] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let agenda: AgendaViewModel

    init(agenda: AgendaViewModel) {
        self.agenda = agenda
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            calendars = try await agenda.calendars()
            errorMessage = nil
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    func setVisible(_ visible: Bool, calendarIdentifier: String) async {
        // Optimistic: flip locally first so the toggle feels immediate.
        calendars = calendars.map {
            $0.identifier == calendarIdentifier
                ? EventCalendarInfo(identifier: $0.identifier, title: $0.title, colorRed: $0.colorRed, colorGreen: $0.colorGreen, colorBlue: $0.colorBlue, isVisible: visible)
                : $0
        }
        await agenda.setCalendarVisible(visible, calendarIdentifier: calendarIdentifier)
    }
}
