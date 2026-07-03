import WidgetKit
import SwiftUI

@main
struct CalenminderWidgetBundle: WidgetBundle {
    var body: some Widget {
        AgendaWidget()
        if #available(iOS 18.0, *) {
            AddTaskControl()
        }
    }
}
