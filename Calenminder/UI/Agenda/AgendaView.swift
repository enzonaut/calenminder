import SwiftUI
import CalenminderKit

struct AgendaView: View {
    @ObservedObject var viewModel: AgendaViewModel

    @State private var selectedEvent: Event?
    @State private var showingEventComposer = false
    @State private var showingTaskComposer = false
    @State private var showingCalendarSettings = false

    var body: some View {
        NavigationStack {
            List {
                if viewModel.snapshot.events.isEmpty && viewModel.snapshot.tasks.isEmpty && viewModel.completedToday.isEmpty {
                    emptyState
                }

                if !viewModel.snapshot.events.isEmpty {
                    Section("Events") {
                        ForEach(viewModel.snapshot.events) { event in
                            EventRow(event: event)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedEvent = event }
                        }
                    }
                    .accessibilityIdentifier("agenda-events-section")
                }

                if !viewModel.snapshot.tasks.isEmpty {
                    Section("Tasks") {
                        ForEach(viewModel.snapshot.tasks) { task in
                            TaskRow(task: task, isOverdue: task.dueDay < viewModel.day) {
                                Task { await viewModel.toggleTaskCompletion(task) }
                            }
                        }
                    }
                    .accessibilityIdentifier("agenda-tasks-section")
                }

                if !viewModel.completedToday.isEmpty {
                    DisclosureGroup("Completed") {
                        ForEach(viewModel.completedToday) { task in
                            TaskRow(task: task, isOverdue: false) {
                                Task { await viewModel.toggleTaskCompletion(task) }
                            }
                        }
                    }
                    .accessibilityIdentifier("agenda-completed-section")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(dayTitle)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button { viewModel.goToPreviousDay() } label: { Image(systemName: "chevron.left") }
                        .accessibilityIdentifier("agenda-previous-day")
                    Button("Today") { viewModel.goToToday() }
                        .accessibilityIdentifier("agenda-today")
                    Button { viewModel.goToNextDay() } label: { Image(systemName: "chevron.right") }
                        .accessibilityIdentifier("agenda-next-day")
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showingCalendarSettings = true } label: { Image(systemName: "calendar.badge.clock") }
                        .accessibilityIdentifier("agenda-calendar-settings")
                    Menu {
                        Button("New Event") { showingEventComposer = true }
                        Button("New Task") { showingTaskComposer = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("agenda-add-menu")
                }
            }
            .refreshable { await viewModel.refresh() }
            .overlay {
                if viewModel.isLoading && viewModel.snapshot.events.isEmpty && viewModel.snapshot.tasks.isEmpty {
                    ProgressView().accessibilityIdentifier("agenda-loading")
                }
            }
        }
        .task { await viewModel.load() }
        .sheet(item: $selectedEvent) { event in
            EventDetailView(
                viewModel: EventDetailViewModel(agenda: viewModel, externalIdentifier: event.externalIdentifier, occurrenceDate: event.occurrenceDate),
                agenda: viewModel,
                onDismiss: { selectedEvent = nil }
            )
        }
        .sheet(isPresented: $showingEventComposer) {
            EventEditView(
                viewModel: EventEditViewModel(agenda: viewModel, mode: .create),
                onFinished: { showingEventComposer = false }
            )
        }
        .sheet(isPresented: $showingTaskComposer) {
            TaskComposerView(
                viewModel: TaskComposerViewModel(agenda: viewModel, dueDay: viewModel.day),
                onFinished: { showingTaskComposer = false }
            )
        }
        .sheet(isPresented: $showingCalendarSettings) {
            CalendarVisibilityView(
                viewModel: CalendarVisibilityViewModel(agenda: viewModel),
                onDismiss: { showingCalendarSettings = false }
            )
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(.secondary)
            Text("Nothing on the agenda").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .accessibilityIdentifier("agenda-empty-state")
        .listRowSeparator(.hidden)
    }

    private var dayTitle: String {
        guard let date = viewModel.day.startOfDay(in: .current) else { return "Agenda" }
        return date.formatted(.dateTime.weekday(.wide).month().day())
    }
}

private struct EventRow: View {
    let event: Event

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.body)
                Text(timeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if event.participation == .needsAction {
                Text("Pending")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.2)))
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("event-row-pending-marker")
            }
        }
        .accessibilityIdentifier("event-row-\(event.externalIdentifier)")
    }

    private var timeLabel: String {
        event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened)
    }
}

private struct TaskRow: View {
    let task: DayTask
    let isOverdue: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("task-row-toggle-\(task.externalIdentifier)")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                if isOverdue {
                    Text("Overdue")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
        }
        .accessibilityIdentifier("task-row-\(task.externalIdentifier)")
    }
}
