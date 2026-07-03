import SwiftUI
import CalenminderKit

struct EventDetailView: View {
    @ObservedObject var viewModel: EventDetailViewModel
    let agenda: AgendaViewModel
    var onDismiss: () -> Void = {}

    @State private var showingEdit = false
    @State private var showingDeleteConfirmation = false
    @State private var deleteSpan: EditSpan = .thisEvent

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Event")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", action: onDismiss) } }
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .accessibilityIdentifier("event-detail-loading")
        case .notFound:
            NotFoundView(kind: "event")
                .accessibilityIdentifier("event-detail-not-found")
        case .error(let message):
            ContentUnavailableMessage(message: message)
                .accessibilityIdentifier("event-detail-error")
        case .found(let event):
            Form {
                Section {
                    Text(event.title)
                        .font(.title3.bold())
                        .accessibilityIdentifier("event-detail-title")
                    timeRow(for: event)
                    participationRow(for: event)
                }

                Section {
                    Button("Edit") { showingEdit = true }
                        .accessibilityIdentifier("event-detail-edit")
                    Button("Delete", role: .destructive) { showingDeleteConfirmation = true }
                        .accessibilityIdentifier("event-detail-delete")
                }
            }
            .confirmationDialog("Delete this event?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("This Event", role: .destructive) { Task { await delete(span: .thisEvent) } }
                Button("This and Future Events", role: .destructive) { Task { await delete(span: .futureEvents) } }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingEdit) {
                EventEditView(
                    viewModel: EventEditViewModel(agenda: agenda, mode: .edit(original: event)),
                    onFinished: { showingEdit = false; Task { await viewModel.load() } }
                )
            }
        }
    }

    private func delete(span: EditSpan) async {
        if await viewModel.delete(span: span) {
            onDismiss()
        }
    }

    private func timeRow(for event: Event) -> some View {
        HStack {
            Image(systemName: "clock").foregroundStyle(.secondary)
            if event.isAllDay {
                Text("All day")
            } else {
                Text(event.start, style: .date) + Text(" · ") + Text(event.start, style: .time) + Text(" – ") + Text(event.end, style: .time)
            }
        }
        .accessibilityIdentifier("event-detail-time")
    }

    private func participationRow(for event: Event) -> some View {
        HStack {
            Image(systemName: "person.crop.circle").foregroundStyle(.secondary)
            Text(participationLabel(event.participation))
                .foregroundStyle(event.participation == .declined ? .red : .primary)
        }
        .accessibilityIdentifier("event-detail-participation")
    }

    private func participationLabel(_ status: ParticipationStatus) -> String {
        switch status {
        case .accepted: return "Accepted"
        case .tentative: return "Tentative"
        case .declined: return "Declined"
        case .needsAction: return "Pending invite"
        case .notInvited: return "Your event"
        }
    }
}

/// Small shared "nothing here" body, used both for a not-found detail
/// screen and (via `NotFoundView`) a malformed deep link.
struct ContentUnavailableMessage: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
