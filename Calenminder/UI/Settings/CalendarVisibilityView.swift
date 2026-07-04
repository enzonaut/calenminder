import SwiftUI
import CalenminderKit

struct CalendarVisibilityView: View {
    @ObservedObject var viewModel: CalendarVisibilityViewModel
    var onDismiss: () -> Void = {}
    /// Item 1 (App Store prep): folded into this existing settings sheet
    /// rather than a separate screen, so there is one settings destination
    /// instead of two near-empty ones. Defaults to the real app bundle;
    /// tests inject a fixed `AppAboutInfo` instead of relying on
    /// `Bundle.main`, which resolves to the *test* bundle inside
    /// `CalenminderTests`, not the app's.
    var about: AppAboutInfo = .fromBundle(.main)

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.calendars.isEmpty {
                    ProgressView()
                } else if let errorMessage = viewModel.errorMessage {
                    ContentUnavailableMessage(message: errorMessage)
                        .accessibilityIdentifier("calendar-visibility-error")
                } else {
                    List {
                        Section("Calendars") {
                            ForEach(viewModel.calendars) { calendarInfo in
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
                        }
                        .accessibilityIdentifier("calendar-visibility-list")

                        Section("About") {
                            Text(about.versionLabel)
                                .accessibilityIdentifier("about-version-label")
                            Text(about.privacyStatement)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("about-privacy-statement")
                            Link("View on GitHub", destination: about.githubURL)
                                .accessibilityIdentifier("about-github-link")
                            Link("Privacy Policy", destination: about.privacyPolicyURL)
                                .accessibilityIdentifier("about-privacy-policy-link")
                        }
                        .accessibilityIdentifier("about-section")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done", action: onDismiss) } }
        }
        .task { await viewModel.load() }
    }
}
