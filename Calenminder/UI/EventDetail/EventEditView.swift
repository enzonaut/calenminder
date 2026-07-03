import SwiftUI
import CalenminderKit

struct EventEditView: View {
    @ObservedObject var viewModel: EventEditViewModel
    var onFinished: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $viewModel.title)
                        .accessibilityIdentifier("event-edit-title")
                    Toggle("All day", isOn: $viewModel.isAllDay)
                        .accessibilityIdentifier("event-edit-all-day")
                    DatePicker("Starts", selection: $viewModel.start, displayedComponents: viewModel.isAllDay ? [.date] : [.date, .hourAndMinute])
                        .accessibilityIdentifier("event-edit-start")
                    DatePicker("Ends", selection: $viewModel.end, displayedComponents: viewModel.isAllDay ? [.date] : [.date, .hourAndMinute])
                        .accessibilityIdentifier("event-edit-end")
                }

                if viewModel.isEditing {
                    Section("Apply to") {
                        Picker("Apply to", selection: $viewModel.span) {
                            Text("This Event").tag(EditSpan.thisEvent)
                            Text("This and Future Events").tag(EditSpan.futureEvents)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("event-edit-span")
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("event-edit-error")
                    }
                }
            }
            .navigationTitle(viewModel.isEditing ? "Edit Event" : "New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onFinished)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task {
                                if await viewModel.save() { onFinished() }
                            }
                        }
                        .disabled(!viewModel.canSave)
                        .accessibilityIdentifier("event-edit-save")
                    }
                }
            }
        }
    }
}
