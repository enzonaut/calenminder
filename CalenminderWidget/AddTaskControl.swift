import AppIntents
import SwiftUI
import WidgetKit

/// Opens Calenminder from Control Center / the Lock Screen's control tray.
/// No deep-navigation payload (landing specifically on the task composer
/// would need an additional App Group flag hand-off) - this is explicitly a
/// best-effort, non-blocking scope item per the plan; it opens the app and
/// stops there.
@available(iOS 18.0, *)
struct OpenAddTaskIntent: AppIntent {
    static var title: LocalizedStringResource { "Add Task" }
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// iOS 18 Control Center / Lock Screen control for adding a task. Best
/// effort, explicitly non-blocking for this phase's gate per the plan - if
/// `ControlWidget` composition into `CalenminderWidgetBundle` ever stops
/// compiling against a future SDK, this file can be dropped without
/// affecting any Done-When item (none reference it).
@available(iOS 18.0, *)
struct AddTaskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.enzonaut.calenminder.addTask") {
            ControlWidgetButton(action: OpenAddTaskIntent()) {
                Label("Add Task", systemImage: "plus.circle")
            }
        }
        .displayName("Add Task")
        .description("Opens Calenminder to add a task.")
    }
}
