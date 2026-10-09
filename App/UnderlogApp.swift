import SwiftUI
import SwiftData

@main
struct UnderlogApp: App {
    private let container: ModelContainer

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing") {
            // UI tests run against a fresh in-memory log, seeded unless asked to start empty.
            container = SampleData.makeContainer(seeded: !arguments.contains("-empty-log"))
        } else {
            do {
                container = try ModelContainer(for: Schema(ModelSchema.models))
            } catch {
                // The on-disk store could not be opened (for example after an incompatible change during development).
                // Fall back to a temporary store so the app still launches instead of crashing.
                container = SampleData.makeContainer(seeded: false)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
