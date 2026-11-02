import SwiftUI
import WatchKit

// MARK: - Extended Runtime Session per mantenere l'app attiva e in primo piano su Apple Watch
@MainActor
final class WatchRuntimeSessionManager: NSObject, WKExtendedRuntimeSessionDelegate {
    static let shared = WatchRuntimeSessionManager()
    
    private var session: WKExtendedRuntimeSession?
    
    func startSession() {
        if let current = session, current.state == .running || current.state == .scheduled {
            return
        }
        session?.invalidate()
        let newSession = WKExtendedRuntimeSession()
        newSession.delegate = self
        self.session = newSession
        newSession.start()
    }
    
    func stopSession() {
        session?.invalidate()
        session = nil
    }
    
    // MARK: - WKExtendedRuntimeSessionDelegate
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        // Sessione avviata con successo: l'app rimane in primo piano e attiva
    }
    
    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            self.stopSession()
            self.startSession()
        }
    }
    
    nonisolated func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: (any Error)?
    ) {
        Task { @MainActor in
            self.session = nil
        }
    }
}

@main
struct PurlLabWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            WatchCounterView()
                .onAppear {
                    WatchRuntimeSessionManager.shared.startSession()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                WatchRuntimeSessionManager.shared.startSession()
            } else if newPhase == .background || newPhase == .inactive {
                WatchConnectivityManager.shared.saveLocalCache()
                WatchRuntimeSessionManager.shared.stopSession()
            }
        }
    }
}
