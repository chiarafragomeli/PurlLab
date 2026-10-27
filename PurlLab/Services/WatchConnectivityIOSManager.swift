import Foundation
import WatchConnectivity
import SwiftData
import SwiftUI

@MainActor
final class WatchConnectivityIOSManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityIOSManager()
    
    private var modelContext: ModelContext?
    private var activeProjectId: UUID?
    
    override private init() {
        super.init()
        setupWCSession()
    }
    
    // MARK: - Inizializzazione
    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
        syncAllProjectsToWatch()
    }
    
    func setActiveProject(_ project: KnittingProject?) {
        self.activeProjectId = project?.id
        syncAllProjectsToWatch()
    }
    
    private func setupWCSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }
    
    // MARK: - Invio Dati a Apple Watch
    
    /// Trasmette lo stato aggiornato di tutti i progetti a Apple Watch
    func syncAllProjectsToWatch() {
        guard WCSession.isSupported(), let context = modelContext else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        
        let descriptor = FetchDescriptor<KnittingProject>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        guard let projects = try? context.fetch(descriptor) else { return }
        
        let summaries: [WatchProjectSummary] = projects.map { p in
            let sortedSteps = p.guideSteps.sorted(by: { $0.orderIndex < $1.orderIndex })
            let activeStep = sortedSteps.first(where: { !$0.isCompleted }) ?? sortedSteps.last
            let activeStepIdx = activeStep.flatMap { step in sortedSteps.firstIndex(where: { $0.id == step.id }) } ?? 0
            
            let counterLabel = activeStep?.counterLabel ?? "Contatore"
            let currentCount = activeStep?.currentStepCount ?? (p.counters.first?.currentCount ?? 0)
            let targetCount = activeStep?.targetStepCount ?? p.counters.first?.targetCount
            
            let isRunning = TimerManager.shared.isRunning && TimerManager.shared.activeProjectId == p.id
            
            return WatchProjectSummary(
                id: p.id.uuidString,
                title: p.title,
                designer: p.designer,
                selectedSize: p.selectedSize,
                totalSecondsWorked: p.totalSecondsWorked + (isRunning ? TimerManager.shared.elapsedSecondsInCurrentSession : 0),
                isTimerRunning: isRunning,
                currentSectionTitle: activeStep?.sectionTitle ?? "",
                currentStepTitle: activeStep?.title ?? "",
                currentStepIndex: activeStepIdx,
                totalStepsCount: sortedSteps.count,
                counterLabel: counterLabel,
                currentCount: currentCount,
                targetCount: targetCount,
                extraCounterLabels: activeStep?.extraCounterLabels ?? [],
                extraCounterValues: activeStep?.extraCounterValues ?? []
            )
        }
        
        let effectiveActiveId = activeProjectId?.uuidString ?? summaries.first?.id
        let syncState = WatchSyncState(
            projects: summaries,
            activeProjectId: effectiveActiveId,
            timestamp: Date()
        )
        
        guard let syncData = try? JSONEncoder().encode(syncState) else { return }
        let payload: [String: Any] = ["syncData": syncData]
        
        // Aggiorna l'applicationContext garantendo che l'orologio riceva sempre lo stato più recente
        try? session.updateApplicationContext(payload)
        
        // Se l'orologio è raggiungibile in tempo reale, invia subito
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }
    
    // MARK: - Gestione Comandi Ricevuti da Apple Watch
    @discardableResult
    private func handleIncomingCommand(
        commandRaw: String?,
        projectId: String?,
        newCount: Int?,
        index: Int?
    ) -> Data? {
        guard let commandRaw = commandRaw,
              let command = WatchCommandType(rawValue: commandRaw),
              let context = modelContext else {
            return nil
        }
        
        let projUUID = projectId.flatMap { UUID(uuidString: $0) }
        
        let descriptor = FetchDescriptor<KnittingProject>()
        guard let allProjects = try? context.fetch(descriptor) else { return nil }
        
        let targetProject: KnittingProject?
        if let uuid = projUUID {
            targetProject = allProjects.first(where: { $0.id == uuid })
        } else {
            targetProject = allProjects.first
        }
        
        guard let project = targetProject else {
            return nil
        }
        
        let sortedSteps = project.guideSteps.sorted(by: { $0.orderIndex < $1.orderIndex })
        let currentStep = sortedSteps.first(where: { !$0.isCompleted }) ?? sortedSteps.last
        
        switch command {
        case .incrementMainCounter:
            if let step = currentStep {
                step.currentStepCount += 1
                if let target = step.targetStepCount, target > 0, step.currentStepCount >= target {
                    // Target raggiunto
                }
            } else if let globalCounter = project.counters.first {
                globalCounter.increment()
            }
            project.updatedAt = Date()
            try? context.save()
            TimerManager.shared.registerInteraction()
            
        case .decrementMainCounter:
            if let step = currentStep, step.currentStepCount > 0 {
                step.currentStepCount -= 1
            } else if let globalCounter = project.counters.first {
                globalCounter.decrement()
            }
            project.updatedAt = Date()
            try? context.save()
            TimerManager.shared.registerInteraction()
            
        case .setMainCounter:
            if let count = newCount {
                if let step = currentStep {
                    step.currentStepCount = max(0, count)
                } else if let globalCounter = project.counters.first {
                    globalCounter.currentCount = max(0, count)
                }
                project.updatedAt = Date()
                try? context.save()
                TimerManager.shared.registerInteraction()
            }
            
        case .startTimer:
            TimerManager.shared.start(for: project.id)
            
        case .pauseTimer:
            if TimerManager.shared.isRunning && TimerManager.shared.activeProjectId == project.id {
                let duration = TimerManager.shared.pause()
                project.totalSecondsWorked += duration
                project.updatedAt = Date()
                try? context.save()
            }
            
        case .selectProject:
            self.activeProjectId = project.id
            
        case .requestFullSync:
            break
            
        case .incrementExtraCounter, .decrementExtraCounter:
            if let step = currentStep, let idx = index, idx < step.extraCounterValues.count {
                let delta = (command == .incrementExtraCounter) ? 1 : -1
                step.extraCounterValues[idx] = max(0, step.extraCounterValues[idx] + delta)
                project.updatedAt = Date()
                try? context.save()
                TimerManager.shared.registerInteraction()
            }
        }
        
        syncAllProjectsToWatch()
        
        // Risposta immediata con i dati sincronizzati
        let summaries: [WatchProjectSummary] = allProjects.map { p in
            let steps = p.guideSteps.sorted(by: { $0.orderIndex < $1.orderIndex })
            let active = steps.first(where: { !$0.isCompleted }) ?? steps.last
            let isRunning = TimerManager.shared.isRunning && TimerManager.shared.activeProjectId == p.id
            return WatchProjectSummary(
                id: p.id.uuidString,
                title: p.title,
                designer: p.designer,
                selectedSize: p.selectedSize,
                totalSecondsWorked: p.totalSecondsWorked,
                isTimerRunning: isRunning,
                currentSectionTitle: active?.sectionTitle ?? "",
                currentStepTitle: active?.title ?? "",
                currentStepIndex: 0,
                totalStepsCount: steps.count,
                counterLabel: active?.counterLabel ?? "Contatore",
                currentCount: active?.currentStepCount ?? 0,
                targetCount: active?.targetStepCount,
                extraCounterLabels: active?.extraCounterLabels ?? [],
                extraCounterValues: active?.extraCounterValues ?? []
            )
        }
        let state = WatchSyncState(
            projects: summaries,
            activeProjectId: self.activeProjectId?.uuidString ?? summaries.first?.id,
            timestamp: Date()
        )
        return try? JSONEncoder().encode(state)
    }
    
    // MARK: - WCSessionDelegate
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let isActivated = (activationState == .activated)
        Task { @MainActor in
            if isActivated {
                self.syncAllProjectsToWatch()
            }
        }
    }
    
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Riattiva per consentire il cambio rapido di orologio (Apple Watch switching)
        WCSession.default.activate()
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        let commandRaw = message["command"] as? String
        let projectId = message["projectId"] as? String
        let newCount = message["newCount"] as? Int
        let index = message["index"] as? Int
        nonisolated(unsafe) let safeReplyHandler = replyHandler
        
        Task { @MainActor in
            if let replyData = self.handleIncomingCommand(commandRaw: commandRaw, projectId: projectId, newCount: newCount, index: index) {
                safeReplyHandler(["syncData": replyData])
            } else {
                safeReplyHandler([:])
            }
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        let commandRaw = userInfo["command"] as? String
        let projectId = userInfo["projectId"] as? String
        let newCount = userInfo["newCount"] as? Int
        let index = userInfo["index"] as? Int
        
        Task { @MainActor in
            _ = self.handleIncomingCommand(commandRaw: commandRaw, projectId: projectId, newCount: newCount, index: index)
        }
    }
}
