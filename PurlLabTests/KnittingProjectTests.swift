import XCTest
import SwiftData
@testable import PurlLab

@MainActor
final class KnittingProjectTests: XCTestCase {
    
    private var container: ModelContainer!
    private var context: ModelContext!
    
    override func setUp() async throws {
        let schema = Schema([
            KnittingProject.self,
            GuideStep.self,
            RowCounter.self,
            TimerSession.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = container.mainContext
    }
    
    override func tearDown() async throws {
        WatchConnectivityIOSManager.shared.configure(with: nil)
        container = nil
        context = nil
    }
    
    func testTotalGuideRowsWorkedWithSteps() {
        let project = KnittingProject(title: "Test Sciarpa")
        context.insert(project)
        
        let step1 = GuideStep(sectionTitle: "Avvio", instructionText: "Avvia 4 m", orderIndex: 0, hasCounter: true, currentStepCount: 6, targetStepCount: 6)
        let step2 = GuideStep(sectionTitle: "Aumenti", instructionText: "Aumenta", orderIndex: 1, hasCounter: true, currentStepCount: 24, targetStepCount: 160)
        
        step1.project = project
        step2.project = project
        project.guideSteps = [step1, step2]
        
        XCTAssertEqual(project.totalGuideRowsWorked, 30)
    }
    
    func testTotalGuideRowsWorkedExcludesStitchCounters() {
        let project = KnittingProject(title: "Test Esclusione Maglie da Ferri")
        context.insert(project)
        
        // Step 1: Avvio maglie con counterKind = "stitch" (114 maglie avviate)
        let step1 = GuideStep(
            sectionTitle: "Avvio",
            instructionText: "Avvia 114 maglie",
            orderIndex: 0,
            hasCounter: true,
            counterLabel: "Avvio",
            counterKind: "stitch",
            currentStepCount: 114,
            targetStepCount: 114
        )
        
        // Step 2: Bordo collo con counterKind = "row" (10 ferri lavorati su 20)
        let step2 = GuideStep(
            sectionTitle: "Bordo Collo",
            instructionText: "Lavora a coste 1x1",
            orderIndex: 1,
            hasCounter: true,
            counterLabel: "Ferri",
            counterKind: "row",
            currentStepCount: 10,
            targetStepCount: 20
        )
        
        // Step 3: Ripresa maglie con counterKind nil ma counterLabel "Maglie Riprese"
        let step3 = GuideStep(
            sectionTitle: "Bordo Manica",
            instructionText: "Riprendi 54 maglie",
            orderIndex: 2,
            hasCounter: true,
            counterLabel: "Maglie Riprese",
            counterKind: nil,
            currentStepCount: 54,
            targetStepCount: 54
        )
        
        step1.project = project
        step2.project = project
        step3.project = project
        project.guideSteps = [step1, step2, step3]
        
        // totalGuideRowsWorked deve contare SOLO i ferri (step2 = 10), escludendo step1 (114 maglie) e step3 (54 maglie)
        XCTAssertEqual(project.totalGuideRowsWorked, 10, "I contatori di maglie non devono essere sommati al totale dei ferri lavorati")
        
        // targetTotalRows deve contare SOLO l'obiettivo ferri (step2 = 20), escludendo step1 e step3
        XCTAssertEqual(project.targetTotalRows, 20, "I contatori di maglie non devono essere inclusi nell'obiettivo ferri totale")
    }
    
    func testTotalGuideRowsWorkedFallbackToGlobalCounter() {
        let project = KnittingProject(title: "Test Progetto Manuale")
        context.insert(project)
        
        let globalCounter = RowCounter(title: "Contatore Globale", currentCount: 45)
        globalCounter.project = project
        project.counters.append(globalCounter)
        
        XCTAssertTrue(project.guideSteps.isEmpty)
        XCTAssertEqual(project.totalGuideRowsWorked, 45, "Se non ci sono schede guida, deve fare fallback sul Contatore Globale")
    }
    
    func testTotalStitchesWorkedConstantStitches() {
        let project = KnittingProject(title: "Bordo a Coste")
        context.insert(project)
        
        // 10 ferri lavorati, sempre a 100 maglie
        let step = GuideStep(
            sectionTitle: "Bordo",
            instructionText: "Lavora in tondo",
            stitchCountBefore: 100,
            stitchCountAfter: 100,
            orderIndex: 0,
            hasCounter: true,
            currentStepCount: 10,
            targetStepCount: 20
        )
        step.project = project
        project.guideSteps = [step]
        
        // 10 ferri * 100 maglie = 1000 maglie
        XCTAssertEqual(project.totalStitchesWorked, 1000)
    }
    
    func testTotalStitchesWorkedWithIncreases() {
        let project = KnittingProject(title: "Aumenti Raglan")
        context.insert(project)
        
        // Da 100 a 140 maglie in 20 ferri, lavorati tutti e 20 i ferri
        let step = GuideStep(
            sectionTitle: "Sprone",
            instructionText: "Aumenti raglan",
            stitchCountBefore: 100,
            stitchCountAfter: 140,
            orderIndex: 0,
            hasCounter: true,
            currentStepCount: 20,
            targetStepCount: 20
        )
        step.project = project
        project.guideSteps = [step]
        
        let total = project.totalStitchesWorked
        // Media ~120 maglie per 20 ferri = ~2400 maglie lavorate
        XCTAssertGreaterThan(total, 2300)
        XCTAssertLessThan(total, 2500)
    }
    
    func testTotalStitchesWorkedIgnoresStepsWithoutMeaningfulStitchCounts() {
        let project = KnittingProject(title: "Scheda senza maglie note")
        context.insert(project)
        
        let step = GuideStep(
            sectionTitle: "Info",
            title: "Nota",
            instructionText: "Lavorare a mano senza riferimenti di maglie.",
            stitchCountBefore: 0,
            stitchCountAfter: 0,
            orderIndex: 0,
            hasCounter: true,
            currentStepCount: 5,
            targetStepCount: 10
        )
        step.project = project
        project.guideSteps = [step]
        
        XCTAssertEqual(project.totalStitchesWorked, 0)
        XCTAssertNil(project.targetTotalStitches)
    }
    
    func testTargetTotalRowsAndStitches() {
        let project = KnittingProject(title: "Top-Down Sweater")
        context.insert(project)
        
        let step1 = GuideStep(
            sectionTitle: "Collo",
            instructionText: "Coste 1/1",
            stitchCountBefore: 114,
            stitchCountAfter: 114,
            orderIndex: 0,
            hasCounter: true,
            currentStepCount: 0,
            targetStepCount: 20
        )
        let step2 = GuideStep(
            sectionTitle: "Sprone",
            stepType: "repeat_pattern",
            instructionText: "Ripetizioni",
            rowsPerRepeat: 4,
            totalRepeats: 5, // 20 ferri
            stitchCountBefore: 114,
            stitchCountAfter: 154,
            orderIndex: 1,
            hasCounter: true,
            currentStepCount: 0
        )
        
        step1.project = project
        step2.project = project
        project.guideSteps = [step1, step2]
        
        XCTAssertEqual(project.targetTotalRows, 40)
        XCTAssertNotNil(project.targetTotalStitches)
        XCTAssertGreaterThan(project.targetTotalStitches ?? 0, 4000)
    }
    
    func testGlobalProgress() {
        let project = KnittingProject(title: "Test Progresso")
        context.insert(project)
        
        let step = GuideStep(
            sectionTitle: "Lavoro",
            instructionText: "Corpo",
            stitchCountBefore: 100,
            stitchCountAfter: 100,
            orderIndex: 0,
            hasCounter: true,
            currentStepCount: 50,
            targetStepCount: 100
        )
        step.project = project
        project.guideSteps = [step]
        
        // 50 ferri su 100 con maglie costanti -> esattamente 50%
        XCTAssertEqual(project.globalProgress, 0.5, accuracy: 0.01)
    }
    
    func testActiveWorkingStepPriority() {
        let project = KnittingProject(title: "Test Priorità Scheda Attiva")
        context.insert(project)
        
        // Scheda 0: Info (senza contatore, non completata)
        let step0 = GuideStep(sectionTitle: "Info", title: "Dettagli", instructionText: "Info testo", orderIndex: 0, hasCounter: false)
        // Scheda 1: Operativa completata
        let step1 = GuideStep(sectionTitle: "Avvio", title: "Avvio", instructionText: "Avvia", isCompleted: true, orderIndex: 1, hasCounter: true, currentStepCount: 4, targetStepCount: 4)
        // Scheda 2: Operativa in corso (ha contatore, non completata)
        let step2 = GuideStep(sectionTitle: "Lavoro", title: "Aumenti", instructionText: "Aumenta", isCompleted: false, orderIndex: 2, hasCounter: true, currentStepCount: 12, targetStepCount: 64)
        // Scheda 3: Operativa futura
        let step3 = GuideStep(sectionTitle: "Chiusura", title: "Bordo", instructionText: "Chiudi", isCompleted: false, orderIndex: 3, hasCounter: true, currentStepCount: 0, targetStepCount: 8)
        
        step0.project = project
        step1.project = project
        step2.project = project
        step3.project = project
        project.guideSteps = [step0, step1, step2, step3]
        
        // 1. Deve privilegiare step2 (prima scheda non completata con contatore) rispetto a step0 (info)
        guard let active = project.activeWorkingStep() else {
            XCTFail("activeWorkingStep() non deve essere nil")
            return
        }
        XCTAssertEqual(active.id, step2.id)
        
        // 2. Se viene specificato un preferredStepId, deve rispettarlo
        guard let preferred = project.activeWorkingStep(preferredStepId: step3.id) else {
            XCTFail("preferred activeWorkingStep() non deve essere nil")
            return
        }
        XCTAssertEqual(preferred.id, step3.id)
    }
    
    func testWatchConnectivityManagerPreservesActiveStepAcrossNavigation() {
        let project = KnittingProject(title: "Maglione Test")
        context.insert(project)
        
        let step1 = GuideStep(sectionTitle: "Collo", instructionText: "Lavora il collo", orderIndex: 0, hasCounter: true)
        let step2 = GuideStep(sectionTitle: "Sprone", instructionText: "Lavora gli aumenti", orderIndex: 1, hasCounter: true)
        let step3 = GuideStep(sectionTitle: "Corpo", instructionText: "Lavora il corpo", orderIndex: 2, hasCounter: true)
        
        step1.project = project
        step2.project = project
        step3.project = project
        project.guideSteps = [step1, step2, step3]
        
        let manager = WatchConnectivityIOSManager.shared
        manager.configure(with: context)
        
        // 1. Inizializza sul progetto
        manager.setActiveProject(project)
        XCTAssertEqual(manager.activeProjectId, project.id)
        XCTAssertEqual(manager.activeStepId, step1.id)
        
        // 2. L'utente o Apple Watch imposta lo step 2
        manager.setActiveStep(step2, for: project)
        XCTAssertEqual(manager.activeStepId, step2.id)
        
        // 3. Navigazione nell'app (es. apre tab Contatori o rientra nella schermata)
        manager.setActiveProject(project)
        
        // Deve rimanere rigorosamente su step2, senza azzerarsi a step1
        XCTAssertEqual(manager.activeStepId, step2.id, "setActiveProject non deve sovrascrivere lo step attivo se il progetto non è cambiato")
    }
    
    func testResetAllProgressRestartsProjectFromBeginning() {
        let project = KnittingProject(title: "Maglione Test Restart")
        project.completedAt = Date()
        project.totalSecondsWorked = 3600
        context.insert(project)
        
        let session = TimerSession(startDate: Date().addingTimeInterval(-3600), endDate: Date(), durationSeconds: 3600)
        session.project = project
        project.timerSessions.append(session)
        
        let counter = RowCounter(title: "Contatore Globale", currentCount: 25)
        counter.project = project
        project.counters.append(counter)
        
        let step1 = GuideStep(
            sectionTitle: "Avvio",
            instructionText: "Avvia 100 maglie",
            isCompleted: true,
            orderIndex: 0,
            hasCounter: true,
            counterLabel: "Avvio",
            counterKind: "stitch",
            currentStepCount: 100,
            targetStepCount: 100
        )
        step1.extraCounterLabels = ["Ripetizioni"]
        step1.extraCounterValues = [4]
        step1.completedAt = Date()
        
        let step2 = GuideStep(
            sectionTitle: "Corpo",
            instructionText: "Lavora 50 ferri",
            isCompleted: true,
            orderIndex: 1,
            hasCounter: true,
            currentStepCount: 50,
            targetStepCount: 50
        )
        step2.completedAt = Date()
        
        step1.project = project
        step2.project = project
        project.guideSteps = [step1, step2]
        
        try? context.save()
        
        XCTAssertNotNil(project.completedAt)
        XCTAssertEqual(project.totalSecondsWorked, 3600)
        XCTAssertEqual(project.timerSessions.count, 1)
        XCTAssertEqual(project.counters.first?.currentCount, 25)
        XCTAssertEqual(step1.currentStepCount, 100)
        XCTAssertTrue(step1.isCompleted)
        XCTAssertEqual(step1.extraCounterValues, [4])
        
        // Esegui reset completo dei progressi
        project.resetAllProgress(modelContext: context)
        
        // Verifica azzeramento totale
        XCTAssertNil(project.completedAt, "completedAt deve essere resettato a nil")
        XCTAssertEqual(project.totalSecondsWorked, 0, "totalSecondsWorked deve essere 0")
        XCTAssertTrue(project.timerSessions.isEmpty, "timerSessions deve essere svuotato")
        XCTAssertEqual(counter.currentCount, 0, "I contatori manuali devono essere azzerati")
        
        XCTAssertEqual(step1.currentStepCount, 0, "Il contatore dello step 1 deve essere 0")
        XCTAssertFalse(step1.isCompleted, "Lo step 1 non deve risultare completato")
        XCTAssertNil(step1.completedAt, "completedAt dello step 1 deve essere nil")
        XCTAssertEqual(step1.extraCounterValues, [0], "Gli extra contatori devono essere azzerati a 0")
        
        XCTAssertEqual(step2.currentStepCount, 0, "Il contatore dello step 2 deve essere 0")
        XCTAssertFalse(step2.isCompleted, "Lo step 2 non deve risultare completato")
        XCTAssertNil(step2.completedAt, "completedAt dello step 2 deve essere nil")
        
        XCTAssertEqual(project.totalGuideRowsWorked, 0, "I ferri lavorati totali devono essere 0")
        XCTAssertEqual(project.totalStitchesWorked, 0, "Le maglie lavorate totali devono essere 0")
        XCTAssertEqual(project.globalProgress, 0.0, "Il progresso globale deve essere 0%")
        
        // Lo step attivo calcolato deve ritornare al primo step
        XCTAssertEqual(project.activeWorkingStep()?.id, step1.id, "Lo step attivo deve tornare al primo step")
    }
    
    func testHandleIncomingCommandNegativeOrOutOfBoundsExtraIndexDoesNotCrash() {
        let project = KnittingProject(title: "Test Extra Index Safety")
        context.insert(project)
        
        let step = GuideStep(sectionTitle: "Bordo", instructionText: "Ripeti", orderIndex: 0, hasCounter: true)
        step.extraCounterLabels = ["Giri Extra"]
        step.extraCounterValues = [5]
        step.project = project
        project.guideSteps = [step]
        try? context.save()
        
        let manager = WatchConnectivityIOSManager.shared
        manager.configure(with: context)
        manager.setActiveProject(project)
        
        // 1. Indice negativo: NON deve mandare in crash l'app
        _ = manager.handleIncomingCommand(
            commandRaw: WatchCommandType.incrementExtraCounter.rawValue,
            projectId: project.id.uuidString,
            stepId: step.id.uuidString,
            newCount: nil,
            index: -1
        )
        XCTAssertEqual(step.extraCounterValues[0], 5, "Un indice negativo non deve alterare i contatori né causare crash")
        
        // 2. Indice fuori limite superiore: NON deve mandare in crash l'app
        _ = manager.handleIncomingCommand(
            commandRaw: WatchCommandType.incrementExtraCounter.rawValue,
            projectId: project.id.uuidString,
            stepId: step.id.uuidString,
            newCount: nil,
            index: 99
        )
        XCTAssertEqual(step.extraCounterValues[0], 5, "Un indice out-of-bounds non deve alterare i contatori")
        
        // 3. Indice valido: incrementa correttamente
        _ = manager.handleIncomingCommand(
            commandRaw: WatchCommandType.incrementExtraCounter.rawValue,
            projectId: project.id.uuidString,
            stepId: step.id.uuidString,
            newCount: nil,
            index: 0
        )
        XCTAssertEqual(step.extraCounterValues[0], 6)
    }
    
    func testHandleIncomingCommandClampsCountersToReasonableBounds() {
        let project = KnittingProject(title: "Test Clamp Safety")
        context.insert(project)
        
        let step = GuideStep(sectionTitle: "Corpo", instructionText: "Lavora", orderIndex: 0, hasCounter: true, currentStepCount: 0)
        step.extraCounterLabels = ["Extra"]
        step.extraCounterValues = [100_000]
        step.project = project
        project.guideSteps = [step]
        try? context.save()
        
        let manager = WatchConnectivityIOSManager.shared
        manager.configure(with: context)
        manager.setActiveProject(project)
        
        // Imposta valore astronomico oltre 100_000: deve essere limitato a 100_000
        _ = manager.handleIncomingCommand(
            commandRaw: WatchCommandType.setMainCounter.rawValue,
            projectId: project.id.uuidString,
            stepId: step.id.uuidString,
            newCount: 999_999,
            index: nil
        )
        XCTAssertEqual(step.currentStepCount, 100_000)
        
        // Imposta valore negativo: deve essere limitato a 0
        _ = manager.handleIncomingCommand(
            commandRaw: WatchCommandType.setMainCounter.rawValue,
            projectId: project.id.uuidString,
            stepId: step.id.uuidString,
            newCount: -42,
            index: nil
        )
        XCTAssertEqual(step.currentStepCount, 0)
        
        // Incremento su extraCounter già a 100_000: non deve superare 100_000
        _ = manager.handleIncomingCommand(
            commandRaw: WatchCommandType.incrementExtraCounter.rawValue,
            projectId: project.id.uuidString,
            stepId: step.id.uuidString,
            newCount: nil,
            index: 0
        )
        XCTAssertEqual(step.extraCounterValues[0], 100_000)
    }
    
    func testHandleIncomingCommandRejectsNonExistentProjectIdWithoutApplying() {
        let project = KnittingProject(title: "Progetto Attivo Esistente")
        context.insert(project)
        
        let step = GuideStep(sectionTitle: "Avvio", instructionText: "Avvia", orderIndex: 0, hasCounter: true, currentStepCount: 10)
        step.project = project
        project.guideSteps = [step]
        try? context.save()
        
        let manager = WatchConnectivityIOSManager.shared
        manager.configure(with: context)
        manager.setActiveProject(project)
        
        let fakeUUID = UUID().uuidString
        
        // Invia comando con un projectId che non corrisponde ad alcun progetto
        let syncData = manager.handleIncomingCommand(
            commandRaw: WatchCommandType.incrementMainCounter.rawValue,
            projectId: fakeUUID,
            stepId: step.id.uuidString,
            newCount: nil,
            index: nil
        )
        
        // Deve ritornare syncData corrente e non applicare nulla
        XCTAssertNotNil(syncData["syncData"])
        XCTAssertEqual(step.currentStepCount, 10, "Il contatore del progetto non deve essere toccato quando il projectId non corrisponde")
        XCTAssertEqual(manager.activeProjectId, project.id, "activeProjectId non deve essere mutato verso un progetto inesistente")
    }
    
    func testHandleIncomingCommandReturnsNotReadyWhenModelContextIsNil() {
        let manager = WatchConnectivityIOSManager.shared
        manager.configure(with: nil)
        
        let reply = manager.handleIncomingCommand(
            commandRaw: WatchCommandType.incrementMainCounter.rawValue,
            projectId: "some-project-id",
            stepId: nil,
            newCount: nil,
            index: nil
        )
        
        XCTAssertEqual(reply["error"] as? String, "notReady")
    }
    
    func testDeviceStoreCompatibility() throws {
        let storePath = "/tmp/purl_lab_test_store"
        guard FileManager.default.fileExists(atPath: storePath) else {
            throw XCTSkip("Store reale non trovato in \(storePath). Per ricrearlo da dispositivo collegato eseguire: xcrun devicectl device copy from --device <DEVICE_UUID> --domain-type appDataContainer --domain-identifier com.chiara.PurlLab --source Library/Application\\ Support/PurlLabV4.store --destination /tmp/purl_lab_test_store")
        }
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let destinationStore = tempDir.appendingPathComponent("PurlLabV4.store")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: storePath), to: destinationStore)
        
        let schema = Schema(versionedSchema: PurlLabSchemaV1.self)
        let config = ModelConfiguration("PurlLabV4", schema: schema, url: destinationStore)
        
        let testContainer = try ModelContainer(for: schema, configurations: [config])
        let fetchContext = testContainer.mainContext
        let projects = try fetchContext.fetch(FetchDescriptor<KnittingProject>())
        XCTAssertFalse(projects.isEmpty, "Lo store reale dell'iPhone deve caricare i progetti senza errori")
    }
}
