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
                    WatchConnectivityIOSManager.shared.configure(with: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                TimerManager.shared.handleAppDidEnterBackground()
            } else if newPhase == .active {
                TimerManager.shared.handleAppWillEnterForeground()
            }
        }
    }
}
