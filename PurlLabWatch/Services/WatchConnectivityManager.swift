import Foundation
import WatchConnectivity
import WatchKit
import SwiftUI

@MainActor
@Observable
final class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()
    
    var projects: [WatchProjectSummary] = []
    var activeProjectId: String? = nil
    var isConnectedToPhone: Bool = false
    var lastSyncDate: Date? = nil
    
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
            WKInterfaceDevice.current().play(.success)
        } else {
            WKInterfaceDevice.current().play(.click)
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
        WKInterfaceDevice.current().play(.directionDown)
        
        var payload: [String: Any] = ["newCount": current.currentCount]
        if let stepId = current.activeStepId {
            payload["stepId"] = stepId
        }
        
        sendCommand(.decrementMainCounter, projectId: current.id, data: payload)
    }
    
    /// Imposta direttamente un valore (es. tramite Digital Crown)
    func setMainCounter(to value: Int) {
        guard var current = activeProject, value >= 0, current.currentCount != value else { return }
        current.currentCount = value
        updateProjectLocally(current)
        WKInterfaceDevice.current().play(.click)
        
        var payload: [String: Any] = ["newCount": value]
        if let stepId = current.activeStepId {
            payload["stepId"] = stepId
        }
        
        sendCommand(.setMainCounter, projectId: current.id, data: payload)
    }
    
    /// Passa alla scheda/sezione successiva della guida
    func nextStep() {
        guard let current = activeProject, current.canGoNext else { return }
        WKInterfaceDevice.current().play(.click)
        var payload: [String: Any] = [:]
        if let stepId = current.activeStepId { payload["stepId"] = stepId }
        sendCommand(.nextStep, projectId: current.id, data: payload)
    }
    
    /// Torna alla scheda/sezione precedente della guida
    func previousStep() {
        guard let current = activeProject, current.canGoPrevious else { return }
        WKInterfaceDevice.current().play(.click)
        var payload: [String: Any] = [:]
        if let stepId = current.activeStepId { payload["stepId"] = stepId }
        sendCommand(.previousStep, projectId: current.id, data: payload)
    }
    
    /// Segna la scheda corrente come completata e avanza alla successiva
    func completeStep() {
        guard let current = activeProject else { return }
        WKInterfaceDevice.current().play(.success)
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
        
        WKInterfaceDevice.current().play(newRunningState ? .start : .stop)
        
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
        WKInterfaceDevice.current().play(.click)
        sendCommand(.selectProject, projectId: id, data: [:])
    }
    
    /// Richiede sincronizzazione completa a iPhone
    func requestSyncFromPhone() {
        sendCommand(.requestFullSync, projectId: activeProjectId ?? "", data: [:])
    }
    
    // MARK: - Invio Comandi a iPhone via WatchConnectivity
    nonisolated private func sendCommand(_ command: WatchCommandType, projectId: String, data: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        
        var message: [String: Any] = [
            "command": command.rawValue,
            "projectId": projectId,
            "timestamp": Date().timeIntervalSince1970
        ]
        for (k, v) in data { message[k] = v }
        
        if session.isReachable {
            // Messaggio istantaneo real-time se iPhone è attivo e raggiungibile
            session.sendMessage(message, replyHandler: { [weak self] reply in
                let syncData = reply["syncData"] as? Data
                Task { @MainActor in
                    if let syncData {
                        self?.handleSyncData(syncData)
                    }
                }
            }, errorHandler: { [message] _ in
                // In caso di errore temporaneo, salva e invia in background
                WCSession.default.transferUserInfo(message)
            })
        } else {
            // Se iPhone è bloccato o in tasca, trasferisce in background
            session.transferUserInfo(message)
        }
    }
    
    // MARK: - Aggiornamento Locale & Cache
    private func updateProjectLocally(_ updated: WatchProjectSummary) {
        if let idx = projects.firstIndex(where: { $0.id == updated.id }) {
            projects[idx] = updated
        } else {
            projects.append(updated)
        }
        saveLocalCache()
    }
    
    private func saveLocalCache() {
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
    
    private func handleSyncData(_ data: Data) {
        guard let state = try? JSONDecoder().decode(WatchSyncState.self, from: data) else {
            return
        }
        self.projects = state.projects
        if let newActive = state.activeProjectId {
            self.activeProjectId = newActive
        }
        self.lastSyncDate = state.timestamp
        self.saveLocalCache()
    }
    
    // MARK: - WCSessionDelegate
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let isActivated = (activationState == .activated)
        Task { @MainActor in
            self.isConnectedToPhone = isActivated
            if isActivated {
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
}
