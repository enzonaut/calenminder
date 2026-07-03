import SwiftUI

struct TaskDetailView: View {
    @ObservedObject var viewModel: TaskDetailViewModel
    var onDismiss: () -> Void = {}

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Task")
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
                .accessibilityIdentifier("task-detail-loading")
        case .notFound:
            NotFoundView(kind: "task")
                .accessibilityIdentifier("task-detail-not-found")
        case .error(let message):
            ContentUnavailableMessage(message: message)
                .accessibilityIdentifier("task-detail-error")
        case .found(let task):
            Form {
                Section {
                    Text(task.title)
                        .font(.title3.bold())
                        .accessibilityIdentifier("task-detail-title")
                    Button {
                        Task { await viewModel.toggleCompletion() }
                    } label: {
                        Label(
                            task.isCompleted ? "Mark Incomplete" : "Mark Complete",
                            systemImage: task.isCompleted ? "circle" : "checkmark.circle"
                        )
                    }
                    .accessibilityIdentifier("task-detail-toggle")
                }
            }
        }
    }
}
