import SwiftUI
import SwiftData

@main
struct PurlLabApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
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
                .onAppear {
                    let context = sharedModelContainer.mainContext
                    WatchConnectivityIOSManager.shared.configure(with: context)
                    TimerManager.shared.configure(with: context)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
