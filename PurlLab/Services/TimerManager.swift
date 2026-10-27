import Foundation
import SwiftUI
import Combine

@MainActor
@Observable
final class TimerManager {
    static let shared = TimerManager()
    
    var isRunning: Bool = false
    var activeProjectId: UUID?
    var elapsedSecondsInCurrentSession: TimeInterval = 0
    
    private var timer: Timer?
    private var sessionStartDate: Date?
    private var lastInteractionDate: Date = Date()
    private var backgroundEntryDate: Date?
    
    var autoPauseMinutes: Double = 15.0
    
    private init() {
        setupLifecycleObservers()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Gestione Ciclo di Vita per Ottimizzazione Batteria
    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppDidEnterBackground()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppWillEnterForeground()
            }
        }
    }
    
    /// Quando l'app va in background o lo schermo si spegne:
    /// Invalida il timer hardware per azzerare il risveglio periodico della CPU (consumo batteria 0%),
    /// memorizzando il timestamp di uscita.
    func handleAppDidEnterBackground() {
        guard isRunning else { return }
        backgroundEntryDate = Date()
        stopTicker()
    }
    
    /// Quando l'app torna in primo piano:
    /// Ricalcola matematicamente il tempo trascorso senza aver tenuto la CPU attiva in background.
    func handleAppWillEnterForeground() {
        guard isRunning, let start = sessionStartDate else { return }
        
        let now = Date()
        let timeSinceLastInteraction = now.timeIntervalSince(lastInteractionDate)
        let maxAllowedInactiveSeconds = autoPauseMinutes * 60.0
        
        if timeSinceLastInteraction > maxAllowedInactiveSeconds {
            // L'utente è stato assente troppo a lungo: applica l'auto-pausa
            // calcolando il tempo fino al timeout di inattività
            let effectiveDuration = max(0, min(now.timeIntervalSince(start), lastInteractionDate.addingTimeInterval(maxAllowedInactiveSeconds).timeIntervalSince(start)))
            elapsedSecondsInCurrentSession = effectiveDuration
            _ = pause()
        } else {
            // Ancora all'interno della finestra di sessione attiva: aggiorna e riavvia il ticker
            elapsedSecondsInCurrentSession = now.timeIntervalSince(start)
            startTicker()
        }
        backgroundEntryDate = nil
    }
    
    // MARK: - Controlli Sessione
    func start(for projectId: UUID) {
        if isRunning && activeProjectId == projectId { return }
        if isRunning { _ = pause() }
        
        activeProjectId = projectId
        isRunning = true
        sessionStartDate = Date()
        lastInteractionDate = Date()
        elapsedSecondsInCurrentSession = 0
        
        startTicker()
        WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
    }
    
    func pause() -> TimeInterval {
        guard isRunning else { return 0 }
        isRunning = false
        stopTicker()
        
        let sessionDuration = elapsedSecondsInCurrentSession
        elapsedSecondsInCurrentSession = 0
        sessionStartDate = nil
        backgroundEntryDate = nil
        WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
        return sessionDuration
    }
    
    /// Scarica i secondi lavorati finora per consentire il salvataggio immediato in SwiftData
    /// reimpostando la data di riferimento per i secondi successivi, senza interrompere la sessione attiva.
    func flushElapsedToTotal() -> TimeInterval {
        guard isRunning, let _ = sessionStartDate else { return 0 }
        let currentElapsed = elapsedSecondsInCurrentSession
        elapsedSecondsInCurrentSession = 0
        sessionStartDate = Date()
        return currentElapsed
    }
    
    func registerInteraction() {
        lastInteractionDate = Date()
    }
    
    // MARK: - Timer con Coalescing per Risparmio Energetico
    private func startTicker() {
        stopTicker()
        
        // Timer con tolleranza per consentire a iOS di accorpare i risvegli della CPU (Energy Coalescing)
        let newTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        newTimer.tolerance = 0.25 // 250ms di tolleranza raccomandata da Apple
        RunLoop.main.add(newTimer, forMode: .common)
        self.timer = newTimer
    }
    
    private func stopTicker() {
        timer?.invalidate()
        timer = nil
    }
    
    private func tick() {
        guard let start = sessionStartDate else { return }
        let now = Date()
        elapsedSecondsInCurrentSession = now.timeIntervalSince(start)
        
        // Auto-pause se inattivo da più di autoPauseMinutes
        if now.timeIntervalSince(lastInteractionDate) > (autoPauseMinutes * 60) {
            _ = pause()
        }
    }
    
    func formatTime(_ totalSeconds: TimeInterval) -> String {
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60
        
        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, seconds)
        } else {
            return String(format: "%02dm %02ds", minutes, seconds)
        }
    }
}
