import SwiftUI

@main
struct PurlLabWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            WatchCounterView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                WatchConnectivityManager.shared.saveLocalCache()
            }
        }
    }
}
