import Foundation
import WatchConnectivity
#if os(watchOS)
import WatchKit
private func playHaptic(_ type: WKHapticType) {
    WKInterfaceDevice.current().play(type)
}
#else
private enum WKHapticType {
    case click, success, directionDown, start, stop
}
private func playHaptic(_ type: WKHapticType) {}
#endif
import SwiftUI
#if !os(watchOS)
@testable import PurlLab
#endif

@MainActor
@Observable
final class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()
    
    var projects: [WatchProjectSummary] = []
    var activeProjectId: String? = nil
    var isConnectedToPhone: Bool = false
    var lastSyncDate: Date? = nil
    private(set) var inFlightCommandsCount: Int = 0
    
    private let userDefaultsKey = "purl_lab_watch_cache_v2"
    
    var activeProject: WatchProjectSummary? {
        if let id = activeProjectId {
            return projects.first(where: { $0.id == id })
        }
        return projects.first
    }
    
    override private init() {
        super.init()
        loadLocalCache()
        setupWCSession()
    }
    
    // MARK: - WCSession Setup
    private func setupWCSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }
    
    // MARK: - Azioni Utente (Apple Watch -> iPhone)
    
    /// Incrementa il contatore della sezione (+1) con risposta aptica istantanea
    func incrementMainCounter() {
        guard var current = activeProject else { return }
        current.currentCount += 1
        current.totalRowsWorked += 1
        if let sts = current.currentStitches, sts > 0 {
            current.totalStitchesWorked += sts
        }
        updateProjectLocally(current)
        
        // Haptic click piacevole per ogni ferro
        if current.isTargetReached {
            playHaptic(.success)
        } else {
            playHaptic(.click)
        }
        
        var payload: [String: Any] = ["newCount": current.currentCount]
        if let stepId = current.activeStepId {
            payload["stepId"] = stepId
        }
        
        sendCommand(.incrementMainCounter, projectId: current.id, data: payload)
    }
    
    /// Decrementa il contatore della sezione (-1)
    func decrementMainCounter() {
        guard var current = activeProject, current.currentCount > 0 else { return }
        current.currentCount -= 1
        if current.totalRowsWorked > 0 { current.totalRowsWorked -= 1 }
        updateProjectLocally(current)
        playHaptic(.directionDown)
        
        var payload: [String: Any] = ["newCount": current.currentCount]
        if let stepId = current.activeStepId {
            payload["stepId"] = stepId
        }
        
        sendCommand(.decrementMainCounter, projectId: current.id, data: payload)
    }
    
    /// Aggiorna il contatore solo in locale (es. per rotazione Digital Crown con aggiornamento immediato UI)
    func updateMainCounterLocally(to value: Int) {
        guard var current = activeProject, value >= 0, current.currentCount != value else { return }
        current.currentCount = value
        updateProjectLocally(current)
    }
    
    /// Invia il comando di impostazione contatore assoluto a iPhone
    func sendSetMainCounterCommand(to value: Int) {
        guard let current = activeProject, value >= 0 else { return }
        var payload: [String: Any] = ["newCount": value]
        if let stepId = current.activeStepId {
            payload["stepId"] = stepId
        }
        sendCommand(.setMainCounter, projectId: current.id, data: payload)
    }
    
    /// Imposta direttamente un valore (es. tramite Digital Crown o input manuale)
    func setMainCounter(to value: Int) {
        guard var current = activeProject, value >= 0, current.currentCount != value else { return }
        current.currentCount = value
        updateProjectLocally(current)
        playHaptic(.click)
        
        var payload: [String: Any] = ["newCount": value]
        if let stepId = current.activeStepId {
            payload["stepId"] = stepId
        }
        
        sendCommand(.setMainCounter, projectId: current.id, data: payload)
    }
    
    /// Passa alla scheda/sezione successiva della guida
    func nextStep() {
        guard let current = activeProject, current.canGoNext else { return }
        playHaptic(.click)
        var payload: [String: Any] = [:]
        if let stepId = current.activeStepId { payload["stepId"] = stepId }
        sendCommand(.nextStep, projectId: current.id, data: payload)
    }
    
    /// Torna alla scheda/sezione precedente della guida
    func previousStep() {
        guard let current = activeProject, current.canGoPrevious else { return }
        playHaptic(.click)
        var payload: [String: Any] = [:]
        if let stepId = current.activeStepId { payload["stepId"] = stepId }
        sendCommand(.previousStep, projectId: current.id, data: payload)
    }
    
    /// Segna la scheda corrente come completata e avanza alla successiva
    func completeStep() {
        guard let current = activeProject else { return }
        playHaptic(.success)
        var payload: [String: Any] = [:]
        if let stepId = current.activeStepId { payload["stepId"] = stepId }
        sendCommand(.completeStep, projectId: current.id, data: payload)
    }
    
    /// Toggle Timer Sessione (Play / Pausa) sincronizzato con iPhone
    func toggleTimer() {
        guard var current = activeProject else { return }
        let newRunningState = !current.isTimerRunning
        current.isTimerRunning = newRunningState
        updateProjectLocally(current)
        
        playHaptic(newRunningState ? .start : .stop)
        
        sendCommand(
            newRunningState ? .startTimer : .pauseTimer,
            projectId: current.id,
            data: [:]
        )
    }
    
    /// Seleziona un progetto attivo
    func selectProject(id: String) {
        activeProjectId = id
        saveLocalCache()
        playHaptic(.click)
        sendCommand(.selectProject, projectId: id, data: [:])
    }
    
    /// Richiede sincronizzazione completa a iPhone
    func requestSyncFromPhone() {
        sendCommand(.requestFullSync, projectId: activeProjectId ?? "", data: [:])
    }
    
    /// Segnala l'inizio del debounce della corona contando il periodo come "in volo" (Patch 2b)
    func beginCrownDebounce() {
        inFlightCommandsCount += 1
    }
    
    /// Segnala la fine del debounce della corona
    func endCrownDebounce() {
        inFlightCommandsCount = max(0, inFlightCommandsCount - 1)
    }
    
    // MARK: - Invio Comandi a iPhone via WatchConnectivity
    private func sendCommand(_ command: WatchCommandType, projectId: String, data: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let commandId = UUID().uuidString
        
        var message: [String: Any] = [
            "commandId": commandId,
            "command": command.rawValue,
            "projectId": projectId,
            "timestamp": Date().timeIntervalSince1970
        ]
        for (k, v) in data { message[k] = v }
        
        inFlightCommandsCount += 1
        
        if session.isReachable {
            Self.sendSessionMessageReachable(session, message: message)
        } else {
            inFlightCommandsCount = max(0, inFlightCommandsCount - 1)
            // Se iPhone è bloccato o in tasca, trasferisce in background
            session.transferUserInfo(message)
        }
    }
    
    /// Helper nonisolated per garantire che i blocchi replyHandler ed errorHandler
    /// non ereditino l'isolamento @MainActor evitando crash EXC_BREAKPOINT (dispatch_assert_queue_fail)
    /// quando WCSession li invoca sulla propria coda in background.
    private nonisolated static func sendSessionMessageReachable(_ session: WCSession, message: [String: Any]) {
        session.sendMessage(message, replyHandler: { reply in
            let syncData = reply["syncData"] as? Data
            Task { @MainActor in
                let manager = WatchConnectivityManager.shared
                manager.inFlightCommandsCount = max(0, manager.inFlightCommandsCount - 1)
                if let syncData = syncData {
                    manager.handleSyncData(syncData)
                }
            }
        }, errorHandler: { _ in
            Task { @MainActor in
                let manager = WatchConnectivityManager.shared
                manager.inFlightCommandsCount = max(0, manager.inFlightCommandsCount - 1)
            }
            // In caso di errore temporaneo, salva e invia in background (deduplicato su iPhone tramite commandId)
            session.transferUserInfo(message)
        })
    }
    
    // MARK: - Aggiornamento Locale & Cache
    func updateProjectLocally(_ updated: WatchProjectSummary) {
        if let idx = projects.firstIndex(where: { $0.id == updated.id }) {
            projects[idx] = updated
        } else {
            projects.append(updated)
        }
        debounceSaveLocalCache()
    }
    
    private var saveCacheTask: Task<Void, Never>?
    
    func debounceSaveLocalCache() {
        saveCacheTask?.cancel()
        saveCacheTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self.saveLocalCache()
        }
    }
    
    func saveLocalCache() {
        let state = WatchSyncState(
            projects: projects,
            activeProjectId: activeProjectId,
            timestamp: Date()
        )
        if let encoded = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    private func loadLocalCache() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let state = try? JSONDecoder().decode(WatchSyncState.self, from: data) else {
            return
        }
        self.projects = state.projects
        self.activeProjectId = state.activeProjectId
    }
    
    func handleSyncData(_ data: Data) {
        guard let state = try? JSONDecoder().decode(WatchSyncState.self, from: data) else {
            return
        }
        // Confronto timestamp (ALTO-05): scarta pacchetti obsoleti arrivati in ritardo
        if let last = self.lastSyncDate, state.timestamp < last {
            return
        }
        
        // Se ci sono comandi in volo residui DOPO il decremento, proteggi il contatore del progetto attivo locale
        // per evitare che risposte intermedie o sync ritardate sovrascrivano i tap rapidi dell'utente (Patch 2a/2b).
        // Se inFlightCommandsCount == 0 (es. reply dell'ultimo comando in volo),
        // accetta integralmente lo stato dell'iPhone riallineando currentCount, totali e step attivo.
        if inFlightCommandsCount > 0, let activeId = self.activeProjectId,
           let localActive = self.projects.first(where: { $0.id == activeId }) {
            var updatedProjects = state.projects
            if let idx = updatedProjects.firstIndex(where: { $0.id == activeId }) {
                updatedProjects[idx].currentCount = localActive.currentCount
                updatedProjects[idx].totalRowsWorked = localActive.totalRowsWorked
                updatedProjects[idx].totalStitchesWorked = localActive.totalStitchesWorked
            }
            self.projects = updatedProjects
        } else {
            self.projects = state.projects
        }
        
        if let newActive = state.activeProjectId {
            self.activeProjectId = newActive
        }
        self.lastSyncDate = state.timestamp
        self.debounceSaveLocalCache()
    }
    
    // MARK: - WCSessionDelegate
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let isReachable = session.isReachable
        Task { @MainActor in
            self.isConnectedToPhone = isReachable
            if isReachable {
                self.requestSyncFromPhone()
            }
        }
    }
    
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        Task { @MainActor in
            self.isConnectedToPhone = isReachable
            if isReachable {
                self.requestSyncFromPhone()
            }
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        let syncData = applicationContext["syncData"] as? Data
        Task { @MainActor in
            if let syncData {
                self.handleSyncData(syncData)
            }
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        let syncData = message["syncData"] as? Data
        Task { @MainActor in
            if let syncData {
                self.handleSyncData(syncData)
            }
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        let syncData = userInfo["syncData"] as? Data
        Task { @MainActor in
            if let syncData {
                self.handleSyncData(syncData)
            }
        }
    }
    
#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
#endif
}
