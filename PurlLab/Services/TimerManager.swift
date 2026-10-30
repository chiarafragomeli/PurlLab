import Foundation
import UIKit
import SwiftData
import os

private let timerLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.chiara.PurlLab", category: "timer")

// MARK: - Modello Sessione Pending in attesa di salvataggio
struct PendingTimerSession: Sendable, Equatable {
    let projectId: UUID
    let start: Date
    let end: Date
    let duration: TimeInterval
}

// MARK: - Risultato del Salvataggio Sessione
private enum PersistSessionResult {
    case success
    case temporaryError
    case projectNotFound
}

@MainActor
@Observable
final class TimerManager {
    static let shared = TimerManager()
    
    var isRunning: Bool = false
    var activeProjectId: UUID?
    var elapsedSecondsInCurrentSession: TimeInterval = 0
    private(set) var pendingSessions: [PendingTimerSession] = []
    
    private var timer: Timer?
    var sessionStartDate: Date?
    var lastInteractionDate: Date = Date()
    private var backgroundEntryDate: Date?
    private nonisolated(unsafe) var observerTokens: [NSObjectProtocol] = []
    private var modelContext: ModelContext?
    
    var autoPauseMinutes: Double = 15.0
    var clock: any AppClock = SystemClock()
    
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
        if modelContext != nil {
            retryPendingSessions()
        }
    }
    
    /// Ritenta il salvataggio di eventuali sessioni rimaste pendenti a causa di errori o assenza di context.
    /// Scarta dalla coda le sessioni il cui progetto non esiste più e trattiene solo quelle fallite per errori temporanei.
    @discardableResult
    func retryPendingSessions() -> Int {
        guard !pendingSessions.isEmpty else { return 0 }
        var remaining: [PendingTimerSession] = []
        var succeededCount = 0
        var discardedCount = 0
        
        for pending in pendingSessions {
            switch persistSession(projectId: pending.projectId, start: pending.start, end: pending.end, duration: pending.duration) {
            case .success:
                succeededCount += 1
            case .projectNotFound:
                // Scarta dalla coda le sessioni il cui progetto non esiste più
                discardedCount += 1
            case .temporaryError:
                // Trattieni solo quelle fallite per errori temporanei (es. context assente o store occupato)
                remaining.append(pending)
            }
        }
        pendingSessions = remaining
        if succeededCount > 0 {
            timerLogger.info("retryPendingSessions: salvate con successo \(succeededCount) sessioni pendenti")
        }
        if discardedCount > 0 {
            timerLogger.info("retryPendingSessions: scartate \(discardedCount) sessioni pendenti per progetti non più esistenti")
        }
        return succeededCount
    }
    
    func clearPendingSessionsForTesting() {
        pendingSessions.removeAll()
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
        backgroundEntryDate = clock.now
        stopTicker()
        _ = flushElapsedToTotal()
    }
    
    /// Quando l'app torna in primo piano:
    /// Ricalcola matematicamente il tempo trascorso senza aver tenuto la CPU attiva in background.
    func handleAppWillEnterForeground() {
        retryPendingSessions()
        guard isRunning, let start = sessionStartDate else { return }
        
        let now = clock.now
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
    @discardableResult
    private func persistSession(projectId: UUID, start: Date, end: Date, duration: TimeInterval) -> PersistSessionResult {
        guard duration > 0 else { return .success }
        guard let modelContext else { return .temporaryError }
        let descriptor = FetchDescriptor<KnittingProject>(
            predicate: #Predicate { $0.id == projectId }
        )
        guard let projects = try? modelContext.fetch(descriptor) else {
            timerLogger.warning("persistSession: fetch fallito temporaneamente per progetto \(projectId)")
            return .temporaryError
        }
        guard let project = projects.first else {
            timerLogger.warning("persistSession: progetto \(projectId) non più esistente in archivio, sessione scartata")
            return .projectNotFound
        }
        
        let session = TimerSession(startDate: start, endDate: end, durationSeconds: duration)
        session.project = project
        project.timerSessions.append(session)
        project.totalSecondsWorked += duration
        project.updatedAt = clock.now
        do {
            try modelContext.save()
            return .success
        } catch {
            timerLogger.error("Errore salvataggio sessione timer in SwiftData: \(error.localizedDescription)")
            if let idx = project.timerSessions.firstIndex(where: { $0.id == session.id }) {
                project.timerSessions.remove(at: idx)
            }
            project.totalSecondsWorked -= duration
            modelContext.delete(session)
            return .temporaryError
        }
    }
    
    // MARK: - Controlli Sessione
    func start(for projectId: UUID) {
        retryPendingSessions()
        if isRunning && activeProjectId == projectId { return }
        if isRunning { _ = pause() }
        
        activeProjectId = projectId
        isRunning = true
        sessionStartDate = clock.now
        lastInteractionDate = clock.now
        elapsedSecondsInCurrentSession = 0
        
        startTicker()
        WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
    }
    
    @discardableResult
    func pause() -> TimeInterval {
        stopTicker()
        guard isRunning else { return 0 }
        isRunning = false
        
        let now = clock.now
        let start = sessionStartDate ?? now
        
        // Ricalcola matematicamente l'elapsed da sessionStartDate invece di usare il valore congelato
        let rawElapsed = max(0, now.timeIntervalSince(start))
        let maxAllowed = autoPauseMinutes * 60.0
        let timeSinceInteraction = now.timeIntervalSince(lastInteractionDate)
        
        let duration: TimeInterval
        let endDate: Date
        if timeSinceInteraction > maxAllowed {
            let effectiveEnd = lastInteractionDate.addingTimeInterval(maxAllowed)
            duration = max(0, min(rawElapsed, effectiveEnd.timeIntervalSince(start)))
            endDate = effectiveEnd
        } else {
            duration = rawElapsed
            endDate = now
        }
        
        if let projectId = activeProjectId, duration > 0 {
            let result = persistSession(projectId: projectId, start: start, end: endDate, duration: duration)
            switch result {
            case .success:
                break
            case .temporaryError:
                timerLogger.warning("pause: persistSession fallito temporaneamente per progetto \(projectId), conservata in coda pending")
                pendingSessions.append(PendingTimerSession(projectId: projectId, start: start, end: endDate, duration: duration))
            case .projectNotFound:
                timerLogger.warning("pause: progetto \(projectId) non più esistente in archivio, sessione scartata e non accodata")
            }
        }
        
        elapsedSecondsInCurrentSession = 0
        sessionStartDate = nil
        activeProjectId = nil
        backgroundEntryDate = nil
        
        WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
        return duration
    }
    
    /// Annulla il timer attivo per un determinato progetto senza salvarne il tempo lavorato
    func cancelTimer(for projectId: UUID) {
        guard activeProjectId == projectId else { return }
        stopTicker()
        isRunning = false
        elapsedSecondsInCurrentSession = 0
        sessionStartDate = nil
        activeProjectId = nil
        backgroundEntryDate = nil
        WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
    }
    
    /// Scarica i secondi lavorati finora per consentire il salvataggio immediato in SwiftData
    /// reimpostando la data di riferimento per i secondi successivi, senza interrompere la sessione attiva.
    @discardableResult
    func flushElapsedToTotal() -> TimeInterval {
        retryPendingSessions()
        guard isRunning, let start = sessionStartDate, let projectId = activeProjectId else { return 0 }
        let now = clock.now
        let duration = max(0, now.timeIntervalSince(start))
        guard duration > 0 else { return 0 }
        
        let result = persistSession(projectId: projectId, start: start, end: now, duration: duration)
        switch result {
        case .success:
            sessionStartDate = now
            elapsedSecondsInCurrentSession = 0
            return duration
        case .temporaryError:
            timerLogger.warning("flushElapsedToTotal: salvataggio fallito temporaneamente, sessionStartDate mantenuto per non perdere il tempo lavorato")
            return 0
        case .projectNotFound:
            timerLogger.warning("flushElapsedToTotal: progetto \(projectId) non più esistente in archivio, sessione azzerata")
            sessionStartDate = nil
            isRunning = false
            return 0
        }
    }
    
    func registerInteraction() {
        lastInteractionDate = clock.now
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
        let now = clock.now
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
