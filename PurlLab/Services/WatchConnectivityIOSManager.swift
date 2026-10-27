import Foundation
import WatchConnectivity
import SwiftData
import SwiftUI

extension Notification.Name {
    static let watchDidChangeActiveStep = Notification.Name("PurlLabWatchDidChangeActiveStep")
    static let watchDidUpdateCounter = Notification.Name("PurlLabWatchDidUpdateCounter")
    static let watchDidSelectProject = Notification.Name("PurlLabWatchDidSelectProject")
}

@MainActor
final class WatchConnectivityIOSManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityIOSManager()
    
    private var modelContext: ModelContext?
    public private(set) var activeProjectId: UUID?
    public private(set) var activeStepId: UUID?
    
    override private init() {
        super.init()
        setupWCSession()
    }
    
    // MARK: - Inizializzazione & Selezione Attiva
    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
        syncAllProjectsToWatch()
    }
    
    func setActiveProject(_ project: KnittingProject?) {
        self.activeProjectId = project?.id
        // Resetta lo stepId se cambia progetto
        self.activeStepId = project?.activeWorkingStep()?.id
        syncAllProjectsToWatch()
    }
    
    /// Imposta la scheda operativa attualmente visualizzata o lavorata dall'utente in GuideView
    func setActiveStep(_ step: GuideStep?, for project: KnittingProject?) {
        if let project = project {
            self.activeProjectId = project.id
        }
        self.activeStepId = step?.id
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
            buildProjectSummary(for: p)
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
    
    /// Costruisce il sommario per Apple Watch con la sezione attiva sensata
    private func buildProjectSummary(for p: KnittingProject) -> WatchProjectSummary {
        let sortedSteps = p.guideSteps.sorted(by: { $0.orderIndex < $1.orderIndex })
        let preferredStepId = (p.id == self.activeProjectId ? self.activeStepId : nil)
        let activeStep = p.activeWorkingStep(preferredStepId: preferredStepId)
        let activeStepIdx = activeStep.flatMap { step in sortedSteps.firstIndex(where: { $0.id == step.id }) } ?? 0
        
        let counterLabel: String
        if let lbl = activeStep?.counterLabel, !lbl.trimmingCharacters(in: .whitespaces).isEmpty {
            counterLabel = lbl
        } else if let mainCounter = p.counters.first(where: { $0.title.localizedCaseInsensitiveContains("globale") }) ?? p.counters.first {
            counterLabel = mainCounter.title
        } else {
            counterLabel = "Contatore Globale"
        }
        
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
            activeStepId: activeStep?.id.uuidString,
            currentSectionTitle: activeStep?.sectionTitle ?? "",
            currentStepTitle: activeStep?.title ?? "",
            currentStepIndex: activeStepIdx,
            totalStepsCount: sortedSteps.count,
            isStepCompleted: activeStep?.isCompleted ?? false,
            counterLabel: counterLabel,
            currentCount: currentCount,
            targetCount: targetCount,
            currentStitches: activeStep?.stitchCountAfter ?? activeStep?.stitchCountBefore,
            stitchesBefore: activeStep?.stitchCountBefore,
            stitchesAfter: activeStep?.stitchCountAfter,
            canGoPrevious: activeStepIdx > 0,
            canGoNext: activeStepIdx < max(0, sortedSteps.count - 1),
            totalStitchesWorked: p.totalStitchesWorked,
            totalRowsWorked: p.totalGuideRowsWorked,
            extraCounterLabels: activeStep?.extraCounterLabels ?? [],
            extraCounterValues: activeStep?.extraCounterValues ?? []
        )
    }
    
    // MARK: - Gestione Comandi Ricevuti da Apple Watch
    @discardableResult
    private func handleIncomingCommand(
        commandRaw: String?,
        projectId: String?,
        stepId: String?,
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
        
        let previousActiveProjectId = self.activeProjectId
        self.activeProjectId = project.id
        if previousActiveProjectId != project.id || command == .selectProject {
            NotificationCenter.default.post(
                name: .watchDidSelectProject,
                object: nil,
                userInfo: ["projectId": project.id]
            )
        }
        
        let sortedSteps = project.guideSteps.sorted(by: { $0.orderIndex < $1.orderIndex })
        
        // Risolvi esattamente la scheda da aggiornare:
        // 1. Tramite stepId esplicito passato dall'orologio
        // 2. Tramite activeStepId salvato
        // 3. Tramite activeWorkingStep euristico
        let explicitStepUUID = stepId.flatMap { UUID(uuidString: $0) }
        let currentStep: GuideStep?
        if let explicit = explicitStepUUID, let match = sortedSteps.first(where: { $0.id == explicit }) {
            currentStep = match
            self.activeStepId = match.id
        } else {
            currentStep = project.activeWorkingStep(preferredStepId: self.activeStepId)
            self.activeStepId = currentStep?.id
        }
        
        let currentStepIdx = currentStep.flatMap { step in sortedSteps.firstIndex(where: { $0.id == step.id }) } ?? 0
        
        switch command {
        case .incrementMainCounter:
            if let step = currentStep {
                step.currentStepCount += 1
            } else if let globalCounter = project.counters.first {
                globalCounter.increment()
            }
            // Sincronizza eventuale Contatore Globale in project.counters
            updateGlobalRowCounter(for: project)
            project.updatedAt = Date()
            try? context.save()
            TimerManager.shared.registerInteraction()
            NotificationCenter.default.post(name: .watchDidUpdateCounter, object: nil, userInfo: ["projectId": project.id, "stepId": currentStep?.id as Any])
            
        case .decrementMainCounter:
            if let step = currentStep, step.currentStepCount > 0 {
                step.currentStepCount -= 1
            } else if let globalCounter = project.counters.first {
                globalCounter.decrement()
            }
            updateGlobalRowCounter(for: project)
            project.updatedAt = Date()
            try? context.save()
            TimerManager.shared.registerInteraction()
            NotificationCenter.default.post(name: .watchDidUpdateCounter, object: nil, userInfo: ["projectId": project.id, "stepId": currentStep?.id as Any])
            
        case .setMainCounter:
            if let count = newCount {
                if let step = currentStep {
                    step.currentStepCount = max(0, count)
                } else if let globalCounter = project.counters.first {
                    globalCounter.currentCount = max(0, count)
                }
                updateGlobalRowCounter(for: project)
                project.updatedAt = Date()
                try? context.save()
                TimerManager.shared.registerInteraction()
                NotificationCenter.default.post(name: .watchDidUpdateCounter, object: nil, userInfo: ["projectId": project.id, "stepId": currentStep?.id as Any])
            }
            
        case .nextStep:
            if currentStepIdx + 1 < sortedSteps.count {
                let next = sortedSteps[currentStepIdx + 1]
                self.activeStepId = next.id
                NotificationCenter.default.post(
                    name: .watchDidChangeActiveStep,
                    object: nil,
                    userInfo: ["projectId": project.id, "stepId": next.id, "stepIndex": currentStepIdx + 1]
                )
            }
            
        case .previousStep:
            if currentStepIdx > 0 {
                let prev = sortedSteps[currentStepIdx - 1]
                self.activeStepId = prev.id
                NotificationCenter.default.post(
                    name: .watchDidChangeActiveStep,
                    object: nil,
                    userInfo: ["projectId": project.id, "stepId": prev.id, "stepIndex": currentStepIdx - 1]
                )
            }
            
        case .completeStep:
            if let step = currentStep {
                step.isCompleted = true
                step.completedAt = Date()
                if currentStepIdx + 1 < sortedSteps.count {
                    let next = sortedSteps[currentStepIdx + 1]
                    self.activeStepId = next.id
                    NotificationCenter.default.post(
                        name: .watchDidChangeActiveStep,
                        object: nil,
                        userInfo: ["projectId": project.id, "stepId": next.id, "stepIndex": currentStepIdx + 1]
                    )
                }
                project.updatedAt = Date()
                try? context.save()
                NotificationCenter.default.post(name: .watchDidUpdateCounter, object: nil, userInfo: ["projectId": project.id])
            }
            
        case .selectStep:
            if let idx = index, idx >= 0, idx < sortedSteps.count {
                let target = sortedSteps[idx]
                self.activeStepId = target.id
                NotificationCenter.default.post(
                    name: .watchDidChangeActiveStep,
                    object: nil,
                    userInfo: ["projectId": project.id, "stepId": target.id, "stepIndex": idx]
                )
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
            
        case .selectProject, .requestFullSync:
            self.activeProjectId = project.id
            if command == .selectProject {
                self.activeStepId = project.activeWorkingStep()?.id
            }
            NotificationCenter.default.post(
                name: .watchDidSelectProject,
                object: nil,
                userInfo: ["projectId": project.id]
            )
            
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
        
        let summaries: [WatchProjectSummary] = allProjects.map { p in
            buildProjectSummary(for: p)
        }
        let state = WatchSyncState(
            projects: summaries,
            activeProjectId: self.activeProjectId?.uuidString ?? summaries.first?.id,
            timestamp: Date()
        )
        return try? JSONEncoder().encode(state)
    }
    
    /// Mantiene allineato il Contatore Globale memorizzato in RowCounter (se presente)
    private func updateGlobalRowCounter(for project: KnittingProject) {
        if let global = project.counters.first(where: {
            $0.title.localizedCaseInsensitiveContains("globale") ||
            $0.title.localizedCaseInsensitiveContains("totale")
        }) {
            global.currentCount = project.totalGuideRowsWorked
        }
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
        WCSession.default.activate()
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        let commandRaw = message["command"] as? String
        let projectId = message["projectId"] as? String
        let stepId = message["stepId"] as? String
        let newCount = message["newCount"] as? Int
        let index = message["index"] as? Int
        nonisolated(unsafe) let safeReplyHandler = replyHandler
        
        Task { @MainActor in
            if let replyData = self.handleIncomingCommand(commandRaw: commandRaw, projectId: projectId, stepId: stepId, newCount: newCount, index: index) {
                safeReplyHandler(["syncData": replyData])
            } else {
                safeReplyHandler([:])
            }
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        let commandRaw = userInfo["command"] as? String
        let projectId = userInfo["projectId"] as? String
        let stepId = userInfo["stepId"] as? String
        let newCount = userInfo["newCount"] as? Int
        let index = userInfo["index"] as? Int
        
        Task { @MainActor in
            _ = self.handleIncomingCommand(commandRaw: commandRaw, projectId: projectId, stepId: stepId, newCount: newCount, index: index)
        }
    }
}
