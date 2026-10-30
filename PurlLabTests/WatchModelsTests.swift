import XCTest
import SwiftData
@testable import PurlLab

final class WatchModelsTests: XCTestCase {
    
    override func tearDown() async throws {
        try await super.tearDown()
    }
    
    func testWatchProjectSummaryCodable() throws {
        let summary = WatchProjectSummary(
            id: UUID().uuidString,
            title: "Sophie Scarf",
            designer: "PetiteKnit",
            selectedSize: "Piccola",
            totalSecondsWorked: 320,
            isTimerRunning: true,
            activeStepId: UUID().uuidString,
            currentSectionTitle: "Sciarpa",
            currentStepTitle: "Aumenti",
            currentStepIndex: 1,
            totalStepsCount: 3,
            isStepCompleted: false,
            counterLabel: "Ferri di Aumento",
            currentCount: 15,
            targetCount: 160,
            currentStitches: 25,
            stitchesBefore: 5,
            stitchesAfter: 25,
            canGoPrevious: true,
            canGoNext: true,
            totalStitchesWorked: 246,
            totalRowsWorked: 36,
            extraCounterLabels: ["Ripetizioni"],
            extraCounterValues: [2]
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(summary)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WatchProjectSummary.self, from: data)
        
        XCTAssertEqual(decoded.id, summary.id)
        XCTAssertEqual(decoded.title, summary.title)
        XCTAssertEqual(decoded.currentCount, 15)
        XCTAssertEqual(decoded.targetCount, 160)
        XCTAssertFalse(decoded.isTargetReached)
        XCTAssertEqual(decoded.stitchesDescription, "5 → 25 m (+20)")
        XCTAssertEqual(decoded.displaySubtitle, "Piccola · PetiteKnit")
    }
    
    func testWatchStitchesDescriptionExcludesZeroToStitches() throws {
        let summary = WatchProjectSummary(
            id: UUID().uuidString,
            title: "Test Cast On",
            designer: "PetiteKnit",
            selectedSize: "M",
            totalSecondsWorked: 0,
            isTimerRunning: false,
            activeStepId: nil,
            currentSectionTitle: "Avvio",
            currentStepTitle: "Avvio Maglie",
            currentStepIndex: 0,
            totalStepsCount: 1,
            isStepCompleted: false,
            counterLabel: "Maglie Avviate",
            currentCount: 114,
            targetCount: 114,
            currentStitches: 114,
            stitchesBefore: 0,
            stitchesAfter: 114,
            canGoPrevious: false,
            canGoNext: false,
            totalStitchesWorked: 114,
            totalRowsWorked: 0,
            extraCounterLabels: [],
            extraCounterValues: []
        )
        
        // Non deve mostrare "0 → 114 m (+114)", ma semplicemente "114 maglie"
        XCTAssertEqual(summary.stitchesDescription, "114 maglie")
    }
    
    func testWatchSyncStateCodable() throws {
        let summary = WatchProjectSummary(
            id: UUID().uuidString,
            title: "No Frills Sweater",
            designer: "PetiteKnit",
            selectedSize: "M",
            totalSecondsWorked: 1200,
            isTimerRunning: false,
            activeStepId: nil,
            currentSectionTitle: "Sprone",
            currentStepTitle: "Raglan",
            currentStepIndex: 0,
            totalStepsCount: 1,
            isStepCompleted: false,
            counterLabel: "Ferri",
            currentCount: 20,
            targetCount: 20,
            currentStitches: 154,
            stitchesBefore: 114,
            stitchesAfter: 154,
            canGoPrevious: false,
            canGoNext: false,
            totalStitchesWorked: 2680,
            totalRowsWorked: 20,
            extraCounterLabels: [],
            extraCounterValues: []
        )
        
        let state = WatchSyncState(
            projects: [summary],
            activeProjectId: summary.id,
            timestamp: Date()
        )
        
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WatchSyncState.self, from: data)
        
        XCTAssertEqual(decoded.projects.count, 1)
        XCTAssertEqual(decoded.activeProjectId, summary.id)
        XCTAssertTrue(decoded.projects[0].isTargetReached)
    }
    
    func testWatchCommandTypes() throws {
        let commands: [WatchCommandType] = [
            .incrementMainCounter,
            .decrementMainCounter,
            .setMainCounter,
            .nextStep,
            .previousStep,
            .completeStep,
            .selectStep,
            .incrementExtraCounter,
            .decrementExtraCounter,
            .startTimer,
            .pauseTimer,
            .selectProject,
            .requestFullSync
        ]
        
        for cmd in commands {
            let data = try JSONEncoder().encode(cmd)
            let decoded = try JSONDecoder().decode(WatchCommandType.self, from: data)
            XCTAssertEqual(decoded, cmd)
        }
    }
    
    @MainActor
    func testWatchCommandDeduplication() {
        let manager = WatchConnectivityIOSManager.shared
        let commandId = UUID().uuidString
        
        // Primo arrivo del comando: non deve essere duplicato
        let isFirstDuplicate = manager.isDuplicateCommand(commandId)
        XCTAssertFalse(isFirstDuplicate)
        
        // Secondo arrivo con lo stesso commandId (es. da retry transferUserInfo): deve essere identificato come duplicato
        let isSecondDuplicate = manager.isDuplicateCommand(commandId)
        XCTAssertTrue(isSecondDuplicate)
    }
    
    @MainActor
    func testWatchCounterCommandTimestampOrdering() {
        let manager = WatchConnectivityIOSManager.shared
        let stepKey = "test_step_\(UUID().uuidString)"
        
        let initialTimestamp: TimeInterval = 1000.0
        manager.recordAppliedTimestamp(stepKey: stepKey, timestamp: initialTimestamp)
        
        // Comando più recente (timestamp 1005 > 1000): NON obsoleto
        let isStaleNewer = manager.isStaleCounterCommand(stepKey: stepKey, timestamp: 1005.0)
        XCTAssertFalse(isStaleNewer)
        
        // Registra il nuovo timestamp
        manager.recordAppliedTimestamp(stepKey: stepKey, timestamp: 1005.0)
        
        // Comando ritardato arrivato fuori ordine (timestamp 1002 < 1005): DEVE essere scartato come obsoleto
        let isStaleOlder = manager.isStaleCounterCommand(stepKey: stepKey, timestamp: 1002.0)
        XCTAssertTrue(isStaleOlder)
    }
    
    @MainActor
    func testThreeInFlightCommandsRealignOnFinalReply() throws {
        let coordinator = WatchCommandCoordinator()
        let fakeTransport = FakeWatchTransport()
        fakeTransport.isReachable = true
        coordinator.transport = fakeTransport
        
        // Simula 3 comandi utente consecutivi in volo (es. tap rapidi +1, +1, +1)
        coordinator.sendCommand(.incrementMainCounter, projectId: "p1", data: ["newCount": 11])
        coordinator.sendCommand(.incrementMainCounter, projectId: "p1", data: ["newCount": 12])
        coordinator.sendCommand(.incrementMainCounter, projectId: "p1", data: ["newCount": 13])
        
        XCTAssertEqual(coordinator.inFlightCommandsCount, 3)
        XCTAssertEqual(fakeTransport.sentMessages.count, 3)
        
        // Simula la ricezione delle reply per ciascun comando
        let cmd1 = fakeTransport.sentMessages[0]["commandId"] as! String
        let cmd2 = fakeTransport.sentMessages[1]["commandId"] as! String
        let cmd3 = fakeTransport.sentMessages[2]["commandId"] as! String
        
        coordinator.completeInFlightCommand(commandId: cmd1)
        XCTAssertEqual(coordinator.inFlightCommandsCount, 2)
        
        coordinator.completeInFlightCommand(commandId: cmd2)
        XCTAssertEqual(coordinator.inFlightCommandsCount, 1)
        
        coordinator.completeInFlightCommand(commandId: cmd3)
        XCTAssertEqual(coordinator.inFlightCommandsCount, 0)
    }
    
    @MainActor
    func testCrownDebounceProtectsLocalCounterDuringRotation() throws {
        let coordinator = WatchCommandCoordinator()
        
        // Utente gira la corona: scatta il debounce
        coordinator.beginCrownDebounce()
        XCTAssertEqual(coordinator.inFlightCommandsCount, 1)
        
        // Durante la rotazione della corona (mentre debounce è attivo), inFlightCommandsCount > 0
        XCTAssertTrue(coordinator.inFlightCommandsCount > 0)
        
        // Fine debounce
        coordinator.endCrownDebounce()
        XCTAssertEqual(coordinator.inFlightCommandsCount, 0)
    }
    
    @MainActor
    func testWatchTransportErrorNotReadyFallbacksToTransferUserInfo() async throws {
        let coordinator = WatchCommandCoordinator()
        let fakeTransport = FakeWatchTransport()
        fakeTransport.isReachable = true
        fakeTransport.replyToReturn = ["error": "notReady"]
        coordinator.transport = fakeTransport
        
        let projId = UUID().uuidString
        coordinator.sendCommand(.incrementMainCounter, projectId: projId, data: ["newCount": 1])
        
        // Cede l'esecuzione al Task asincrono di risposta su MainActor senza attese reali
        for _ in 0..<5 {
            await Task.yield()
        }
        
        // 1. Il messaggio è stato inviato via sendMessage
        XCTAssertEqual(fakeTransport.sentMessages.count, 1)
        // 2. Poiché la risposta ha restituito error: notReady, deve essere scattato il fallback transferUserInfo
        XCTAssertEqual(fakeTransport.transferredUserInfos.count, 1)
        XCTAssertEqual(fakeTransport.transferredUserInfos.first?["command"] as? String, WatchCommandType.incrementMainCounter.rawValue)
        // 3. Il contatore in volo deve essere riallineato a 0
        XCTAssertEqual(coordinator.inFlightCommandsCount, 0)
    }
    
    @MainActor
    func testInFlightCommandTimeoutDecrementsCountAndRequestsFullSync() async throws {
        let coordinator = WatchCommandCoordinator()
        let fakeTransport = FakeWatchTransport()
        fakeTransport.isReachable = true
        // Non impostiamo né replyToReturn né errorToReturn: il trasporto simula un blocco / mancata risposta
        fakeTransport.replyToReturn = nil
        fakeTransport.errorToReturn = nil
        coordinator.transport = fakeTransport
        let testClock = TestClock()
        coordinator.clock = testClock
        
        var fullSyncRequested = false
        coordinator.onFullSyncNeeded = {
            fullSyncRequested = true
        }
        
        let projId = UUID().uuidString
        coordinator.sendCommand(.incrementMainCounter, projectId: projId, data: ["newCount": 1])
        
        // Subito dopo l'invio, il comando è in volo
        XCTAssertEqual(coordinator.inFlightCommandsCount, 1)
        XCTAssertEqual(fakeTransport.sentMessages.count, 1)
        let originalCommandId = fakeTransport.sentMessages.first?["commandId"] as? String
        XCTAssertNotNil(originalCommandId)
        XCTAssertEqual(fakeTransport.sentMessages.first?["command"] as? String, WatchCommandType.incrementMainCounter.rawValue)
        
        // Cede l'esecuzione per consentire al timeoutTask di avviare l'attesa su clock.sleep
        for _ in 0..<5 {
            await Task.yield()
        }
        
        // Fai avanzare il TestClock di 8 secondi (tempo di timeout): nessuna attesa reale
        testClock.advance(by: 8.0)
        
        // Cede l'esecuzione per consentire l'elaborazione su MainActor del task di timeout
        for _ in 0..<5 {
            await Task.yield()
        }
        
        // Allo scadere:
        // 1. Il comando originale deve risultare reinviato via fallback (transferUserInfoFallback) con lo stesso commandId
        XCTAssertEqual(fakeTransport.transferredUserInfos.count, 1)
        XCTAssertEqual(fakeTransport.transferredUserInfos.first?["commandId"] as? String, originalCommandId)
        XCTAssertEqual(fakeTransport.transferredUserInfos.first?["command"] as? String, WatchCommandType.incrementMainCounter.rawValue)
        
        // 2. Viene poi invocato il callback onFullSyncNeeded per riallineare lo stato
        XCTAssertTrue(fullSyncRequested)
        
        // 3. Il contatore comandi in volo è decrementato
        XCTAssertEqual(coordinator.inFlightCommandsCount, 0)
        
        // Ripristina timeout di default a 8s e cancella comandi pendenti
        coordinator.resetForTesting()
    }
    
    @MainActor
    func testLostUpdateCounterDeltaHandling() {
        let testClock = TestClock()
        let fakeTransport = FakeWatchTransport()
        let coordinator = WatchCommandCoordinator(transport: fakeTransport, clock: testClock)
        
        let schema = Schema([KnittingProject.self, GuideStep.self, RowCounter.self, TimerSession.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        let project = KnittingProject(title: "Delta Test")
        let step = GuideStep(sectionTitle: "Sezione", instructionText: "Lavora", orderIndex: 0, hasCounter: true, currentStepCount: 6, targetStepCount: 50)
        project.guideSteps.append(step)
        context.insert(project)
        try! context.save()
        
        let manager = WatchConnectivityIOSManager.shared
        manager.configure(with: context)
        manager.setActiveProject(project)
        manager.setActiveStep(step, for: project)
        
        // (a) Watch genera comando incremento quando vedeva 6 (oldCount: 6, newCount: 7)
        // Viene accodato tramite fallback (es. trasporto offline o timeout)
        fakeTransport.isReachable = false
        coordinator.sendCommand(
            .incrementMainCounter,
            projectId: project.id.uuidString,
            data: ["newCount": 7, "oldCount": 6, "stepId": step.id.uuidString]
        )
        
        XCTAssertEqual(fakeTransport.transferredUserInfos.count, 1)
        let queuedMessage = fakeTransport.transferredUserInfos[0]
        let cmdId = queuedMessage["commandId"] as! String
        
        // Nel frattempo l'iPhone passa da 6 a 20
        step.currentStepCount = 20
        try! context.save()
        
        // Il comando in coda viene consegnato a iPhone
        _ = manager.handleIncomingCommand(
            commandRaw: queuedMessage["command"] as? String,
            projectId: queuedMessage["projectId"] as? String,
            stepId: queuedMessage["stepId"] as? String,
            newCount: queuedMessage["newCount"] as? Int,
            oldCount: queuedMessage["oldCount"] as? Int,
            index: queuedMessage["index"] as? Int,
            commandId: cmdId,
            timestamp: queuedMessage["timestamp"] as? TimeInterval
        )
        
        // Risultato deve essere 21 (20 + (7 - 6)), NON 6 o 7
        XCTAssertEqual(step.currentStepCount, 21, "Il comando in coda consegnato dopo che l'iPhone è passato da 6 a 20 deve risultare in 21")
        
        // (b) Stesso comando consegnato due volte -> applicato una sola volta
        _ = manager.handleIncomingCommand(
            commandRaw: queuedMessage["command"] as? String,
            projectId: queuedMessage["projectId"] as? String,
            stepId: queuedMessage["stepId"] as? String,
            newCount: queuedMessage["newCount"] as? Int,
            oldCount: queuedMessage["oldCount"] as? Int,
            index: queuedMessage["index"] as? Int,
            commandId: cmdId,
            timestamp: queuedMessage["timestamp"] as? TimeInterval
        )
        XCTAssertEqual(step.currentStepCount, 21, "Il comando ripetuto con lo stesso commandId deve essere applicato una sola volta")
        
        // (c) Corona 3->8 in ritardo con iPhone a 20 -> 25
        step.currentStepCount = 20
        try! context.save()
        
        let crownCmdId = UUID().uuidString
        _ = manager.handleIncomingCommand(
            commandRaw: WatchCommandType.setMainCounter.rawValue,
            projectId: project.id.uuidString,
            stepId: step.id.uuidString,
            newCount: 8,
            oldCount: 3,
            index: nil,
            commandId: crownCmdId,
            timestamp: testClock.now.timeIntervalSince1970
        )
        // 20 + (8 - 3) = 25
        XCTAssertEqual(step.currentStepCount, 25, "Rotazione corona 3->8 in ritardo con iPhone a 20 deve produrre 25")
    }
}

// MARK: - FakeWatchTransport per testing disaccoppiato da WCSession
final class FakeWatchTransport: @unchecked Sendable, WatchTransport {
    var isReachable: Bool = true
    var sentMessages: [[String: Any]] = []
    var transferredUserInfos: [[String: Any]] = []
    var replyToReturn: [String: Any]?
    var errorToReturn: Error?
    
    func sendMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?, errorHandler: ((Error) -> Void)?) {
        sentMessages.append(message)
        if let error = errorToReturn {
            errorHandler?(error)
        } else if let reply = replyToReturn {
            replyHandler?(reply)
        }
    }
    
    func transferUserInfoFallback(_ userInfo: [String: Any]) {
        transferredUserInfos.append(userInfo)
    }
}
