import SwiftUI

/// Shown for a deep link that could not be resolved: either it did not parse
/// at all (malformed URL) or it parsed but named an event/task that no
/// longer exists. Both cases must never crash and must always show
/// something visible (DW-4.4) - this is that something.
struct NotFoundView: View {
    var kind: String = "item"
    var onDismiss: () -> Void = {}

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "questionmark.folder")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("Couldn't find that \(kind)")
                    .font(.headline)
                Text("It may have been deleted or the link may be out of date.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("Not Found")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", action: onDismiss) } }
        }
    }
}

#Preview {
    NotFoundView()
}
