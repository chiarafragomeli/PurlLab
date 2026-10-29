import Foundation
import UIKit
import SwiftData

@MainActor
@Observable
final class TimerManager {
    static let shared = TimerManager()
    
    var isRunning: Bool = false
    var activeProjectId: UUID?
    var elapsedSecondsInCurrentSession: TimeInterval = 0
    
    private var timer: Timer?
    var sessionStartDate: Date?
    var lastInteractionDate: Date = Date()
    private var backgroundEntryDate: Date?
    private nonisolated(unsafe) var observerTokens: [NSObjectProtocol] = []
    private var modelContext: ModelContext?
    
    var autoPauseMinutes: Double = 15.0
    
    private init() {
        setupLifecycleObservers()
    }
    
    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens.removeAll()
    }
    
    func configure(with modelContext: ModelContext?) {
        self.modelContext = modelContext
    }
    
    // MARK: - Gestione Ciclo di Vita Centralizzata
    private func setupLifecycleObservers() {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens.removeAll()
        
        let bgToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppDidEnterBackground()
            }
        }
        observerTokens.append(bgToken)
        
        let fgToken = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppWillEnterForeground()
            }
        }
        observerTokens.append(fgToken)
    }
    
    /// Quando l'app va in background o lo schermo si spegne:
    /// Invalida il timer hardware per azzerare il risveglio periodico della CPU (consumo batteria 0%),
    /// persiste in sicurezza il chunk lavorato finora per prevenire perdite se iOS chiude l'app in background.
    func handleAppDidEnterBackground() {
        guard isRunning else { return }
        backgroundEntryDate = Date()
        stopTicker()
        _ = flushElapsedToTotal()
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
    
    // MARK: - Persistenza Sessione
    private func persistSession(projectId: UUID, start: Date, end: Date, duration: TimeInterval) {
        guard duration > 0, let modelContext else { return }
        let descriptor = FetchDescriptor<KnittingProject>(
            predicate: #Predicate { $0.id == projectId }
        )
        guard let project = try? modelContext.fetch(descriptor).first else { return }
        
        let session = TimerSession(startDate: start, endDate: end, durationSeconds: duration)
        session.project = project
        project.timerSessions.append(session)
        project.totalSecondsWorked += duration
        project.updatedAt = Date()
        try? modelContext.save()
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
    
    @discardableResult
    func pause() -> TimeInterval {
        stopTicker()
        guard isRunning else { return 0 }
        isRunning = false
        
        let now = Date()
        let start = sessionStartDate ?? now
        
        // Ricalcola matematicamente l'elapsed da sessionStartDate invece di usare il valore congelato
        let rawElapsed = max(0, now.timeIntervalSince(start))
        let maxAllowed = autoPauseMinutes * 60.0
        let timeSinceInteraction = now.timeIntervalSince(lastInteractionDate)
        
        let duration: TimeInterval
        if timeSinceInteraction > maxAllowed {
            let effectiveEnd = lastInteractionDate.addingTimeInterval(maxAllowed)
            duration = max(0, min(rawElapsed, effectiveEnd.timeIntervalSince(start)))
        } else {
            duration = rawElapsed
        }
        
        if let projectId = activeProjectId, duration > 0 {
            persistSession(projectId: projectId, start: start, end: now, duration: duration)
        }
        
        elapsedSecondsInCurrentSession = 0
        sessionStartDate = nil
        activeProjectId = nil
        backgroundEntryDate = nil
        
        WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
        return duration
    }
    
    /// Scarica i secondi lavorati finora per consentire il salvataggio immediato in SwiftData
    /// reimpostando la data di riferimento per i secondi successivi, senza interrompere la sessione attiva.
    @discardableResult
    func flushElapsedToTotal() -> TimeInterval {
        guard isRunning, let start = sessionStartDate, let projectId = activeProjectId else { return 0 }
        let now = Date()
        let duration = max(0, now.timeIntervalSince(start))
        guard duration > 0 else { return 0 }
        
        persistSession(projectId: projectId, start: start, end: now, duration: duration)
        
        sessionStartDate = now
        elapsedSecondsInCurrentSession = 0
        return duration
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
