import Foundation
import WatchConnectivity
import SwiftData
import SwiftUI
import os

private let watchLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.chiara.PurlLab", category: "watch")

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
    private var activeStepIdsByProject: [UUID: UUID] = [:]
    
    // Deduplicazione comandi Watch tramite cache persistente in UserDefaults (CRIT-02)
    private let userDefaults: UserDefaults
    private let userDefaultsKey = "purl_lab_processed_command_ids"
    private var processedCommandIds: [String] = []
    private var processedCommandIdsSet: Set<String> = []
    private let maxProcessedCommands = 200
    
    // Mappa stepId -> ultimo timestamp per ordinamento temporale comandi contatore (Patch 2a)
    private var lastAppliedTimestampByStepId: [String: TimeInterval] = [:]
    
    // Debounce per updateApplicationContext (~200ms) evitando flood del bus WCSession (Patch 2c)
    private var appContextDebounceTask: Task<Void, Never>?
    private var pendingSyncDataForAppContext: Data?
    
    func hasProcessedCommand(_ commandId: String?) -> Bool {
        guard let commandId = commandId, !commandId.isEmpty else { return false }
        return processedCommandIdsSet.contains(commandId)
    }
    
    func isDuplicateCommand(_ commandId: String?) -> Bool {
        guard let commandId = commandId, !commandId.isEmpty else { return false }
        if processedCommandIdsSet.contains(commandId) {
            return true
        }
        processedCommandIds.append(commandId)
        processedCommandIdsSet.insert(commandId)
        if processedCommandIds.count > maxProcessedCommands {
            let overflow = processedCommandIds.count - maxProcessedCommands
            let removed = Array(processedCommandIds.prefix(overflow))
            processedCommandIds.removeFirst(overflow)
            for id in removed {
                if !processedCommandIds.contains(id) {
                    processedCommandIdsSet.remove(id)
                }
            }
        }
        userDefaults.set(processedCommandIds, forKey: userDefaultsKey)
        return false
    }
    
    func isStaleCounterCommand(stepKey: String, timestamp: TimeInterval?) -> Bool {
        guard let timestamp = timestamp else { return false }
        if let lastTimestamp = lastAppliedTimestampByStepId[stepKey], timestamp < lastTimestamp {
            return true
        }
        return false
    }
    
    func recordAppliedTimestamp(stepKey: String, timestamp: TimeInterval?) {
        guard let timestamp = timestamp else { return }
        lastAppliedTimestampByStepId[stepKey] = timestamp
    }
    
    private func scheduleDebouncedApplicationContextUpdate(syncData: Data) {
        pendingSyncDataForAppContext = syncData
        appContextDebounceTask?.cancel()
        appContextDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            guard WCSession.isSupported() else { return }
            let session = WCSession.default
            guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled, let data = self.pendingSyncDataForAppContext else { return }
            try? session.updateApplicationContext(["syncData": data])
        }
    }
    
    private func currentSyncData(for projects: [KnittingProject]) -> Data? {
        let summaries = projects.map { buildProjectSummary(for: $0) }
        let state = WatchSyncState(
            projects: summaries,
            activeProjectId: self.activeProjectId?.uuidString ?? summaries.first?.id,
            timestamp: Date()
        )
        return try? JSONEncoder().encode(state)
    }
    
    public var activeStepId: UUID? {
        get {
            guard let projId = activeProjectId else { return nil }
            return activeStepIdsByProject[projId]
        }
        set {
            if let projId = activeProjectId {
                activeStepIdsByProject[projId] = newValue
            }
        }
    }
    
    init(userDefaults: UserDefaults = .standard, setupSession: Bool = true) {
        self.userDefaults = userDefaults
        let saved = userDefaults.stringArray(forKey: userDefaultsKey) ?? []
        let trimmed = Array(saved.suffix(maxProcessedCommands))
        self.processedCommandIds = trimmed
        self.processedCommandIdsSet = Set(trimmed)
        super.init()
        if setupSession {
            setupWCSession()
        }
    }
    
    // MARK: - Inizializzazione & Selezione Attiva
    func configure(with modelContext: ModelContext?) {
        self.modelContext = modelContext
        if modelContext != nil {
            syncAllProjectsToWatch()
        }
    }
    
    func setActiveProject(_ project: KnittingProject?) {
        guard let project = project else {
            self.activeProjectId = nil
            syncAllProjectsToWatch()
            return
        }
        
        self.activeProjectId = project.id
        
        // Se non abbiamo ancora uno step memorizzato per questo progetto (o se non è più valido),
        // calcola lo step di lavoro iniziale. Altrimenti mantieni rigorosamente quello esistente!
        if let currentStepId = activeStepIdsByProject[project.id],
           project.guideSteps.contains(where: { $0.id == currentStepId }) {
            // Mantiene lo step intatto per Apple Watch senza sovrascriverlo durante la navigazione
        } else {
            activeStepIdsByProject[project.id] = project.activeWorkingStep()?.id
        }
        
        syncAllProjectsToWatch()
    }
    
    /// Imposta la scheda operativa specificamente per il lavoro con Apple Watch
    func setActiveStep(_ step: GuideStep?, for project: KnittingProject?) {
        if let project = project {
            self.activeProjectId = project.id
            activeStepIdsByProject[project.id] = step?.id
        } else if let activeProjId = self.activeProjectId {
            activeStepIdsByProject[activeProjId] = step?.id
        }
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
    func syncAllProjectsToWatch(preferRealtime: Bool = true) {
        guard WCSession.isSupported(), let context = modelContext else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        
        let descriptor = FetchDescriptor<KnittingProject>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        guard let projects = try? context.fetch(descriptor) else { return }
        
        let summaries: [WatchProjectSummary] = projects.compactMap { p in
            guard !p.isDeleted, p.modelContext != nil else { return nil }
            return buildProjectSummary(for: p)
        }
        
        let effectiveActiveId = activeProjectId?.uuidString ?? summaries.first?.id
        let syncState = WatchSyncState(
            projects: summaries,
            activeProjectId: effectiveActiveId,
            timestamp: Date()
        )
        
        guard let syncData = try? JSONEncoder().encode(syncState) else { return }
        
        // Aggiorna l'applicationContext con debounce (~200ms) evitando contesa del canale WCSession
        scheduleDebouncedApplicationContextUpdate(syncData: syncData)
        
        // Se preferRealtime è vero e l'orologio è raggiungibile, trasmette subito via sendMessage
        if preferRealtime && session.isReachable {
            let payload: [String: Any] = ["syncData": syncData]
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            // Se l'orologio non è raggiungibile in tempo reale (o app watch non attiva), garantisce la consegna tramite transferUserInfo
            _ = session.transferUserInfo(["syncData": syncData])
        }
    }
    
    /// Costruisce il sommario per Apple Watch con la sezione attiva sensata
    private func buildProjectSummary(for p: KnittingProject) -> WatchProjectSummary {
        let sortedSteps = p.guideSteps.sorted(by: { $0.orderIndex < $1.orderIndex })
        let preferredStepId = activeStepIdsByProject[p.id]
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
        let sessionStartDate = isRunning ? (TimerManager.shared.sessionStartDate ?? Date()) : nil
        
        return WatchProjectSummary(
            id: p.id.uuidString,
            title: p.title,
            designer: p.designer,
            selectedSize: p.selectedSize,
            totalSecondsWorked: p.totalSecondsWorked,
            isTimerRunning: isRunning,
            timerSessionStartDate: sessionStartDate,
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
            extraCounterLabels: activeStep?.safeExtraCounterLabels ?? [],
            extraCounterValues: activeStep?.safeExtraCounterValues ?? []
        )
    }
    
    // MARK: - Gestione Comandi Ricevuti da Apple Watch
    @discardableResult
    func handleIncomingCommand(
        commandRaw: String?,
        projectId: String?,
        stepId: String?,
        newCount: Int?,
        oldCount: Int? = nil,
        index: Int?,
        commandId: String? = nil,
        timestamp: TimeInterval? = nil
    ) -> [String: Any] {
        guard let context = modelContext else {
            watchLogger.warning("handleIncomingCommand: modelContext è nil (app non ancora pronta)")
            return ["error": "notReady"]
        }
        
        guard let commandRaw = commandRaw,
              let command = WatchCommandType(rawValue: commandRaw) else {
            return ["error": "invalidCommand"]
        }
        
        let descriptor = FetchDescriptor<KnittingProject>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        guard let allProjects = try? context.fetch(descriptor), !allProjects.isEmpty else {
            return ["error": "noProjects"]
        }
        
        // Deduplica comandi tramite ID univoco (idempotenza contro duplicati da retry WCSession)
        if let cmdId = commandId, isDuplicateCommand(cmdId) {
            if let syncData = currentSyncData(for: allProjects) {
                return ["syncData": syncData]
            } else {
                return [:]
            }
        }
        
        // Gestione rapida di requestFullSync: non richiede projectId valido
        if command == .requestFullSync {
            if let pIdString = projectId, !pIdString.isEmpty, let uuid = UUID(uuidString: pIdString), allProjects.contains(where: { $0.id == uuid }) {
                self.activeProjectId = uuid
            } else if self.activeProjectId == nil || !allProjects.contains(where: { $0.id == self.activeProjectId }) {
                self.activeProjectId = allProjects.first?.id
            }
            if let syncData = currentSyncData(for: allProjects) {
                return ["syncData": syncData]
            } else {
                return ["error": "encodingFailed"]
            }
        }
        
        let targetProject: KnittingProject?
        if let pIdString = projectId, !pIdString.isEmpty {
            guard let uuid = UUID(uuidString: pIdString),
                  let match = allProjects.first(where: { $0.id == uuid }) else {
                watchLogger.warning("Comando watch rifiutato: projectId '\(pIdString)' non corrisponde ad alcun progetto valido")
                if let syncData = currentSyncData(for: allProjects) {
                    return ["syncData": syncData]
                } else {
                    return [:]
                }
            }
            targetProject = match
        } else if let activeId = self.activeProjectId, let match = allProjects.first(where: { $0.id == activeId }) {
            targetProject = match
        } else {
            targetProject = allProjects.first
        }
        
        guard let project = targetProject else {
            return ["error": "projectNotFound"]
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
        
        // Ordinamento temporale: sui comandi che impostano un contatore scarta quelli con timestamp obsoleto (Patch 2a)
        let isCounterCommand: Bool
        switch command {
        case .incrementMainCounter, .decrementMainCounter, .setMainCounter:
            isCounterCommand = true
        default:
            isCounterCommand = false
        }
        
        let effectiveStepKey = stepId ?? currentStep?.id.uuidString ?? "project_\(project.id.uuidString)"
        if isCounterCommand, let cmdTimestamp = timestamp {
            // Se oldCount è nil (vecchio formato comandi assoluti), verifica se è obsoleto
            if oldCount == nil, isStaleCounterCommand(stepKey: effectiveStepKey, timestamp: cmdTimestamp) {
                if let syncData = currentSyncData(for: allProjects) {
                    return ["syncData": syncData]
                } else {
                    return [:]
                }
            }
            recordAppliedTimestamp(stepKey: effectiveStepKey, timestamp: cmdTimestamp)
        }
        
        let currentStepIdx = currentStep.flatMap { step in sortedSteps.firstIndex(where: { $0.id == step.id }) } ?? 0
        
        switch command {
        case .incrementMainCounter:
            if let count = newCount {
                let safeCount: Int
                if let old = oldCount {
                    let delta = count - old
                    let currentVal = currentStep?.currentStepCount ?? (project.counters.first?.currentCount ?? 0)
                    safeCount = min(max(0, currentVal + delta), 100_000)
                } else {
                    safeCount = min(max(0, count), 100_000)
                }
                if let step = currentStep {
                    step.currentStepCount = safeCount
                } else if let globalCounter = project.counters.first {
                    globalCounter.currentCount = safeCount
                }
            } else {
                if let step = currentStep {
                    step.currentStepCount = min(step.currentStepCount + 1, 100_000)
                } else if let globalCounter = project.counters.first {
                    globalCounter.increment()
                }
            }
            // Sincronizza eventuale Contatore Globale in project.counters
            updateGlobalRowCounter(for: project)
            project.updatedAt = Date()
            do {
                try context.save()
            } catch {
                watchLogger.error("Errore salvataggio context dopo incrementMainCounter: \(error.localizedDescription)")
            }
            TimerManager.shared.registerInteraction()
            NotificationCenter.default.post(name: .watchDidUpdateCounter, object: nil, userInfo: ["projectId": project.id, "stepId": currentStep?.id as Any])
            
        case .decrementMainCounter:
            if let count = newCount {
                let safeCount: Int
                if let old = oldCount {
                    let delta = count - old
                    let currentVal = currentStep?.currentStepCount ?? (project.counters.first?.currentCount ?? 0)
                    safeCount = min(max(0, currentVal + delta), 100_000)
                } else {
                    safeCount = min(max(0, count), 100_000)
                }
                if let step = currentStep {
                    step.currentStepCount = safeCount
                } else if let globalCounter = project.counters.first {
                    globalCounter.currentCount = safeCount
                }
            } else {
                if let step = currentStep, step.currentStepCount > 0 {
                    step.currentStepCount -= 1
                } else if let globalCounter = project.counters.first {
                    globalCounter.decrement()
                }
            }
            updateGlobalRowCounter(for: project)
            project.updatedAt = Date()
            do {
                try context.save()
            } catch {
                watchLogger.error("Errore salvataggio context dopo decrementMainCounter: \(error.localizedDescription)")
            }
            TimerManager.shared.registerInteraction()
            NotificationCenter.default.post(name: .watchDidUpdateCounter, object: nil, userInfo: ["projectId": project.id, "stepId": currentStep?.id as Any])
            
        case .setMainCounter:
            if let count = newCount {
                let safeCount: Int
                if let old = oldCount {
                    let delta = count - old
                    let currentVal = currentStep?.currentStepCount ?? (project.counters.first?.currentCount ?? 0)
                    safeCount = min(max(0, currentVal + delta), 100_000)
                } else {
                    safeCount = min(max(0, count), 100_000)
                }
                if let step = currentStep {
                    step.currentStepCount = safeCount
                } else if let globalCounter = project.counters.first {
                    globalCounter.currentCount = safeCount
                }
                updateGlobalRowCounter(for: project)
                project.updatedAt = Date()
                do {
                    try context.save()
                } catch {
                    watchLogger.error("Errore salvataggio context dopo setMainCounter: \(error.localizedDescription)")
                }
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
                do {
                    try context.save()
                } catch {
                    watchLogger.error("Errore salvataggio context dopo completeStep: \(error.localizedDescription)")
                }
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
                _ = TimerManager.shared.pause()
            }
            
        case .selectProject, .requestFullSync:
            self.activeProjectId = project.id
            if command == .selectProject {
                if activeStepIdsByProject[project.id] == nil || !project.guideSteps.contains(where: { $0.id == activeStepIdsByProject[project.id] }) {
                    activeStepIdsByProject[project.id] = project.activeWorkingStep()?.id
                }
            }
            NotificationCenter.default.post(
                name: .watchDidSelectProject,
                object: nil,
                userInfo: ["projectId": project.id]
            )
            
        case .incrementExtraCounter, .decrementExtraCounter:
            if let step = currentStep, let idx = index, step.extraCounterValues.indices.contains(idx) {
                let delta = (command == .incrementExtraCounter) ? 1 : -1
                let updated = step.extraCounterValues[idx] + delta
                step.extraCounterValues[idx] = min(max(0, updated), 100_000)
                project.updatedAt = Date()
                do {
                    try context.save()
                } catch {
                    watchLogger.error("Errore salvataggio context dopo extraCounter: \(error.localizedDescription)")
                }
                TimerManager.shared.registerInteraction()
            }
        }
        
        // Costruzione sommari e stato UNA SOLA VOLTA per comando con singola codifica (Patch 2c)
        let summaries: [WatchProjectSummary] = allProjects.map { p in
            buildProjectSummary(for: p)
        }
        let state = WatchSyncState(
            projects: summaries,
            activeProjectId: self.activeProjectId?.uuidString ?? summaries.first?.id,
            timestamp: Date()
        )
        guard let syncData = try? JSONEncoder().encode(state) else {
            return ["error": "encodingFailed"]
        }
        
        // Aggiorna l'applicationContext con debounce (~200ms) evitando flood di WCSession
        scheduleDebouncedApplicationContextUpdate(syncData: syncData)
        
        return ["syncData": syncData]
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
        let commandId = message["commandId"] as? String
        let commandRaw = message["command"] as? String
        let projectId = message["projectId"] as? String
        let stepId = message["stepId"] as? String
        let newCount = message["newCount"] as? Int
        let oldCount = message["oldCount"] as? Int
        let index = message["index"] as? Int
        let timestamp = message["timestamp"] as? TimeInterval
        nonisolated(unsafe) let safeReplyHandler = replyHandler
        
        Task { @MainActor in
            let reply = self.handleIncomingCommand(commandRaw: commandRaw, projectId: projectId, stepId: stepId, newCount: newCount, oldCount: oldCount, index: index, commandId: commandId, timestamp: timestamp)
            safeReplyHandler(reply)
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        if userInfo["syncData"] != nil {
            return
        }
        let commandId = userInfo["commandId"] as? String
        let commandRaw = userInfo["command"] as? String
        let projectId = userInfo["projectId"] as? String
        let stepId = userInfo["stepId"] as? String
        let newCount = userInfo["newCount"] as? Int
        let oldCount = userInfo["oldCount"] as? Int
        let index = userInfo["index"] as? Int
        let timestamp = userInfo["timestamp"] as? TimeInterval
        
        Task { @MainActor in
            let reply = self.handleIncomingCommand(
                commandRaw: commandRaw,
                projectId: projectId,
                stepId: stepId,
                newCount: newCount,
                oldCount: oldCount,
                index: index,
                commandId: commandId,
                timestamp: timestamp
            )
            if reply["syncData"] != nil {
                self.syncAllProjectsToWatch(preferRealtime: true)
            }
        }
    }
}
