import SwiftUI
import SwiftData

@main
struct PurlLabApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            KnittingProject.self,
            RowCounter.self,
            GuideStep.self,
            TimerSession.self
        ])
        let modelConfiguration = ModelConfiguration("PurlLabV4", schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ProjectListView()
        }
        .modelContainer(sharedModelContainer)
    }
}
