import XCTest
@testable import PurlLab

final class WatchModelsTests: XCTestCase {
    
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
        let watchManager = WatchConnectivityManager.shared
        let projId = UUID().uuidString
        let step1Id = UUID().uuidString
        let step2Id = UUID().uuidString
        
        let initialSummary = WatchProjectSummary(
            id: projId,
            title: "Maglione Test",
            designer: "Designer Test",
            selectedSize: "M",
            totalSecondsWorked: 0,
            isTimerRunning: false,
            activeStepId: step1Id,
            currentSectionTitle: "Avvio",
            currentStepTitle: "Giro 1",
            currentStepIndex: 0,
            totalStepsCount: 2,
            isStepCompleted: false,
            counterLabel: "Ferri",
            currentCount: 10,
            targetCount: 20,
            currentStitches: 100,
            stitchesBefore: 100,
            stitchesAfter: 100,
            canGoPrevious: false,
            canGoNext: true,
            totalStitchesWorked: 1000,
            totalRowsWorked: 10,
            extraCounterLabels: [],
            extraCounterValues: []
        )
        
        watchManager.projects = [initialSummary]
        watchManager.activeProjectId = projId
        watchManager.lastSyncDate = Date(timeIntervalSince1970: 1000)
        
        // Simula 3 comandi utente consecutivi in volo (es. tap rapidi +1, +1, +1)
        var localProj = watchManager.activeProject!
        localProj.currentCount = 11
        localProj.totalRowsWorked = 11
        watchManager.updateProjectLocally(localProj)
        
        localProj.currentCount = 12
        localProj.totalRowsWorked = 12
        watchManager.updateProjectLocally(localProj)
        
        localProj.currentCount = 13
        localProj.totalRowsWorked = 13
        watchManager.updateProjectLocally(localProj)
        
        // Simula l'invio: 3 comandi in volo
        watchManager.beginCrownDebounce() // +1 -> inFlight: 1
        watchManager.beginCrownDebounce() // +1 -> inFlight: 2
        watchManager.beginCrownDebounce() // +1 -> inFlight: 3
        XCTAssertEqual(watchManager.inFlightCommandsCount, 3)
        XCTAssertEqual(watchManager.activeProject?.currentCount, 13)
        
        // Reply 1 arriva da iPhone: iPhone conferma il primo tap (count: 11)
        // Nel replyHandler, decrementa PRIMA di chiamare handleSyncData:
        watchManager.endCrownDebounce() // inFlight: 3 -> 2
        XCTAssertEqual(watchManager.inFlightCommandsCount, 2)
        
        var iphoneSummary1 = initialSummary
        iphoneSummary1.currentCount = 11
        iphoneSummary1.totalRowsWorked = 11
        let state1 = WatchSyncState(projects: [iphoneSummary1], activeProjectId: projId, timestamp: Date(timeIntervalSince1970: 1001))
        let data1 = try JSONEncoder().encode(state1)
        watchManager.handleSyncData(data1)
        
        // Poiché inFlightCommandsCount è 2 (> 0), il Watch PROTEGGE il valore locale 13 e non salta indietro a 11!
        XCTAssertEqual(watchManager.activeProject?.currentCount, 13)
        XCTAssertEqual(watchManager.activeProject?.totalRowsWorked, 13)
        
        // Reply 2 arriva da iPhone: iPhone ha scartato il comando 2 per timestamp obsoleto, iPhone ha ancora count: 11
        watchManager.endCrownDebounce() // inFlight: 2 -> 1
        XCTAssertEqual(watchManager.inFlightCommandsCount, 1)
        
        let state2 = WatchSyncState(projects: [iphoneSummary1], activeProjectId: projId, timestamp: Date(timeIntervalSince1970: 1002))
        let data2 = try JSONEncoder().encode(state2)
        watchManager.handleSyncData(data2)
        
        // Poiché inFlightCommandsCount è ancora 1 (> 0), il Watch continua a proteggere il valore locale 13
        XCTAssertEqual(watchManager.activeProject?.currentCount, 13)
        
        // Reply 3 (ultima reply) arriva da iPhone:
        // Su iPhone l'utente ha completato lo step o il comando 3 ha fatto avanzare lo step a step 2 con count: 0, totali: 12
        watchManager.endCrownDebounce() // inFlight: 1 -> 0
        XCTAssertEqual(watchManager.inFlightCommandsCount, 0)
        
        var iphoneSummaryFinal = initialSummary
        iphoneSummaryFinal.activeStepId = step2Id
        iphoneSummaryFinal.currentStepIndex = 1
        iphoneSummaryFinal.currentCount = 0
        iphoneSummaryFinal.totalRowsWorked = 12
        let stateFinal = WatchSyncState(projects: [iphoneSummaryFinal], activeProjectId: projId, timestamp: Date(timeIntervalSince1970: 1003))
        let dataFinal = try JSONEncoder().encode(stateFinal)
        watchManager.handleSyncData(dataFinal)
        
        // Essendo inFlightCommandsCount == 0, la reply dell'ULTIMO comando riallinea TOTALMENTE
        // il Watch allo stato definitivo dell'iPhone (inclusi currentCount, totalRowsWorked e activeStepId)
        XCTAssertEqual(watchManager.activeProject?.currentCount, 0)
        XCTAssertEqual(watchManager.activeProject?.totalRowsWorked, 12)
        XCTAssertEqual(watchManager.activeProject?.activeStepId, step2Id)
        XCTAssertEqual(watchManager.activeProject?.currentStepIndex, 1)
    }
    
    @MainActor
    func testCrownDebounceProtectsLocalCounterDuringRotation() throws {
        let watchManager = WatchConnectivityManager.shared
        let projId = UUID().uuidString
        let summary = WatchProjectSummary(
            id: projId,
            title: "Sciarpa",
            designer: "PetiteKnit",
            selectedSize: "U",
            totalSecondsWorked: 0,
            isTimerRunning: false,
            activeStepId: nil,
            currentSectionTitle: "",
            currentStepTitle: "",
            currentStepIndex: 0,
            totalStepsCount: 1,
            isStepCompleted: false,
            counterLabel: "Ferri",
            currentCount: 5,
            targetCount: 10,
            currentStitches: nil,
            stitchesBefore: nil,
            stitchesAfter: nil,
            canGoPrevious: false,
            canGoNext: false,
            totalStitchesWorked: 0,
            totalRowsWorked: 5,
            extraCounterLabels: [],
            extraCounterValues: []
        )
        watchManager.projects = [summary]
        watchManager.activeProjectId = projId
        watchManager.lastSyncDate = Date(timeIntervalSince1970: 2000)
        
        // Utente gira la corona: scatto 1 (count diventa 8) e scatta il debounce
        watchManager.updateMainCounterLocally(to: 8)
        watchManager.beginCrownDebounce()
        XCTAssertEqual(watchManager.inFlightCommandsCount, 1)
        XCTAssertEqual(watchManager.activeProject?.currentCount, 8)
        
        // Durante la rotazione della corona (mentre debounce è attivo), arriva una sync intermedia da iPhone con count: 5
        let staleState = WatchSyncState(projects: [summary], activeProjectId: projId, timestamp: Date(timeIntervalSince1970: 2001))
        let data = try JSONEncoder().encode(staleState)
        watchManager.handleSyncData(data)
        
        // Il debounce conta come in volo: il contatore locale resta 8, NON viene riportato indietro a 5
        XCTAssertEqual(watchManager.activeProject?.currentCount, 8)
        
        // Fine debounce
        watchManager.endCrownDebounce()
        XCTAssertEqual(watchManager.inFlightCommandsCount, 0)
    }
}
