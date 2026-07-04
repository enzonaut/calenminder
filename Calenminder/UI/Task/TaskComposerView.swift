import SwiftUI

struct TaskComposerView: View {
    @ObservedObject var viewModel: TaskComposerViewModel
    var onFinished: () -> Void

    private static let weekdaySymbols = Calendar.current.weekdaySymbols

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $viewModel.title)
                        .accessibilityIdentifier("task-composer-title")
                }

                Section {
                    Toggle("Every day", isOn: $viewModel.repeatsDaily)
                        .accessibilityIdentifier("task-composer-repeats-daily")
                    Toggle("Repeats weekly", isOn: $viewModel.repeatsWeekly)
                        .accessibilityIdentifier("task-composer-repeats")
                    if viewModel.repeatsWeekly {
                        Picker("Weekday", selection: $viewModel.weekday) {
                            ForEach(1...7, id: \.self) { weekday in
                                Text(Self.weekdaySymbols[weekday - 1]).tag(weekday)
                            }
                        }
                        .accessibilityIdentifier("task-composer-weekday")
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("task-composer-error")
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onFinished)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button("Add") {
                            Task {
                                if await viewModel.save() != nil { onFinished() }
                            }
                        }
                        .disabled(!viewModel.canSave)
                        .accessibilityIdentifier("task-composer-save")
                    }
                }
            }
        }
    }
}
