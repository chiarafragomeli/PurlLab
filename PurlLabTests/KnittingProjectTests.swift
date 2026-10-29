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
}
