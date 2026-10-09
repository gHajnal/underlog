import SwiftUI
import SwiftData

@main
struct UnderlogApp: App {
    /// Nil when the dive log on disk could not be opened.
    private let container: ModelContainer?
    private let storeError: String?

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing") {
            // UI tests run against a fresh in-memory log, seeded unless asked to start empty.
            container = SampleData.makeContainer(seeded: !arguments.contains("-empty-log"))
            storeError = nil
        } else {
            do {
                container = try ModelContainer(for: Schema(ModelSchema.models))
                storeError = nil
            } catch {
                // Never fall back to a temporary log: dives entered there would silently vanish on the next launch.
                container = nil
                storeError = error.localizedDescription
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootView()
                    .modelContainer(container)
            } else {
                StoreErrorView(details: storeError ?? "Unknown error")
            }
        }
    }
}

/// Shown instead of the log when the saved dives can't be opened, so nothing new is entered that couldn't be saved.
struct StoreErrorView: View {
    let details: String

    var body: some View {
        ContentUnavailableView {
            Label("Your dive log couldn't be opened", systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 12) {
                Text("Your dives haven't been deleted. Close Underlog completely and open it again. If this keeps happening, update the app to the latest version.")
                Text(details)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}
