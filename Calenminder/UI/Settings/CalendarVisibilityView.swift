import SwiftUI
import CalenminderKit

struct CalendarVisibilityView: View {
    @ObservedObject var viewModel: CalendarVisibilityViewModel
    var onDismiss: () -> Void = {}

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.calendars.isEmpty {
                    ProgressView()
                } else if let errorMessage = viewModel.errorMessage {
                    ContentUnavailableMessage(message: errorMessage)
                        .accessibilityIdentifier("calendar-visibility-error")
                } else {
                    List(viewModel.calendars) { calendarInfo in
                        Toggle(isOn: Binding(
                            get: { calendarInfo.isVisible },
                            set: { newValue in Task { await viewModel.setVisible(newValue, calendarIdentifier: calendarInfo.identifier) } }
                        )) {
                            HStack {
                                Circle()
                                    .fill(Color(red: calendarInfo.colorRed, green: calendarInfo.colorGreen, blue: calendarInfo.colorBlue))
                                    .frame(width: 12, height: 12)
                                Text(calendarInfo.title)
                            }
                        }
                        .accessibilityIdentifier("calendar-visibility-toggle-\(calendarInfo.identifier)")
                    }
                    .accessibilityIdentifier("calendar-visibility-list")
                }
            }
            .navigationTitle("Calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done", action: onDismiss) } }
        }
        .task { await viewModel.load() }
    }
}
