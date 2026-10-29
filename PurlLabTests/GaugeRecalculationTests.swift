import XCTest
@testable import PurlLab

final class GaugeRecalculationTests: XCTestCase {
    
    func testGaugeRatioCalculation() {
        let patternStitches = 21.0
        let userStitches = 19.0
        
        let stitchRatio = userStitches / patternStitches
        // 19 / 21 = 0.90476... (maglie più larghe -> meno maglie nei 10 cm)
        XCTAssertEqual(stitchRatio, 19.0 / 21.0, accuracy: 0.0001)
        
        let originalCastOn = 114
        // Per mantenere la stessa larghezza in cm: originalCastOn * stitchRatio
        let recalculatedCastOn = Int(round(Double(originalCastOn) * stitchRatio))
        XCTAssertEqual(recalculatedCastOn, 103)
    }
    
    func testRowRatioCalculation() {
        let patternRows = 28.0
        let userRows = 26.0
        
        let rowRatio = userRows / patternRows
        XCTAssertEqual(rowRatio, 26.0 / 28.0, accuracy: 0.0001)
        
        let originalRows = 60
        let recalculatedRows = Int(round(Double(originalRows) * rowRatio))
        XCTAssertEqual(recalculatedRows, 56)
    }
    
    func testReplaceNumberDoesNotMatchInsideLargerNumber() {
        let original = "Avviare 114 maglie sui ferri. Lavorare 4 maglie a coste."
        // Sostituiamo 4 maglie -> 5 maglie: "114 maglie" non deve essere corrotto in "115 maglie"
        let result = GeminiService.replaceNumbersInText(original, stitchMap: [4: 5])
        XCTAssertEqual(result, "Avviare 114 maglie sui ferri. Lavorare 5 maglie a coste.")
    }
    
    func testReplaceNumberDoesNotConfuseUnitMWithMillimeters() {
        let original = "Lavorare con ferri da 4 mm (4 m rimanenti)."
        // Sostituiamo 4 m -> 5 m: "4 mm" deve rimanere intatto, mentre "(4 m" deve diventare "(5 m"
        let result = GeminiService.replaceNumbersInText(original, stitchMap: [4: 5])
        XCTAssertEqual(result, "Lavorare con ferri da 4 mm (5 m rimanenti).")
    }
    
    func testReplaceNumbersSinglePassAvoidsCollisions() {
        let original = "Iniziare con 10 maglie e terminare a 20 maglie."
        // Se eseguisse sostituzioni sequenziali: 10 -> 20, poi 20 -> 30 (portando la prima a 30!)
        // In una singola passata: 10 diventa 20 e 20 diventa 30 contemporaneamente
        let result = GeminiService.replaceNumbersInText(original, stitchMap: [10: 20, 20: 30])
        XCTAssertEqual(result, "Iniziare con 20 maglie e terminare a 30 maglie.")
    }
    
    func testStitchMapDoesNotAffectRows() {
        let text = "Lavorare 28 ferri a maglia rasata."
        // stitchMap non deve toccare "ferri", deve rimanere invariato
        let result = GeminiService.replaceNumbersInText(text, stitchMap: [28: 26])
        XCTAssertEqual(result, "Lavorare 28 ferri a maglia rasata.")
    }
    
    func testRowMapAffectsBothRowsAndStitches() {
        let textRows = "Lavorare 28 ferri."
        let textStitches = "Avviare 28 maglie."
        let resRows = GeminiService.replaceNumbersInText(textRows, rowMap: [28: 24])
        let resStitches = GeminiService.replaceNumbersInText(textStitches, rowMap: [28: 24])
        XCTAssertEqual(resRows, "Lavorare 24 ferri.")
        XCTAssertEqual(resStitches, "Avviare 24 maglie.")
    }
    
    func testRecalculateLocallyReturnsNilForZeroOrNegativeGauge() {
        let project = KnittingProject(title: "Test Zero Gauge")
        let step = GuideStep(
            sectionTitle: "Avvio",
            title: "Avvio Collo",
            instructionText: "Avviare 114 maglie",
            stitchCountBefore: 114,
            stitchCountAfter: 114,
            hasCounter: true,
            currentStepCount: 0
        )
        project.guideSteps.append(step)
        
        // Con input <= 0 deve restituire nil esplicitamente
        let responseZeroPattern = GeminiService.recalculateGuideLocally(
            project: project,
            patternStitches: 0.0,
            patternRows: 28.0,
            userStitches: 19.0,
            userRows: 26.0
        )
        XCTAssertNil(responseZeroPattern)
        
        let responseZeroUser = GeminiService.recalculateGuideLocally(
            project: project,
            patternStitches: 21.0,
            patternRows: 28.0,
            userStitches: 0.0,
            userRows: 26.0
        )
        XCTAssertNil(responseZeroUser)
        
        // Verifica che project.guideSteps non sia stato modificato
        XCTAssertEqual(project.guideSteps.count, 1)
        XCTAssertEqual(project.guideSteps.first?.stitchCountBefore, 114)
    }
    
    func testChainContinuityAcrossNilAfterStep() {
        let project = KnittingProject(title: "Test Catena con Step Info")
        let stepA = GuideStep(
            sectionTitle: "Avvio Collo",
            title: "Avvio",
            instructionText: "Avviare 114 maglie",
            stitchCountBefore: 114,
            stitchCountAfter: 114,
            orderIndex: 0
        )
        let stepInfo = GuideStep(
            sectionTitle: "Avvio Collo",
            title: "Info",
            instructionText: "Posizionare un marcapunto all'inizio del giro.",
            stitchCountBefore: nil,
            stitchCountAfter: nil,
            orderIndex: 1
        )
        let stepB = GuideStep(
            sectionTitle: "Sprone",
            title: "Primo giro raglan",
            instructionText: "Lavorare su 114 maglie",
            stitchCountBefore: 114,
            stitchCountAfter: 122,
            orderIndex: 2
        )
        project.guideSteps.append(contentsOf: [stepA, stepInfo, stepB])
        
        // Ricalcolo locale con ratio 19 / 21:
        // 114 * 19 / 21 = 103.14 -> arrotondato a 103, ma per Collo/Avvio la parità impone 104!
        guard let response = GeminiService.recalculateGuideLocally(
            project: project,
            patternStitches: 21.0,
            patternRows: 28.0,
            userStitches: 19.0,
            userRows: 28.0
        ) else {
            XCTFail("Il ricalcolo locale non dovrebbe restituire nil")
            return
        }
        
        let genSteps = response.sections.flatMap(\.steps)
        XCTAssertEqual(genSteps.count, 3)
        // Step A after ha parità pari: 104
        XCTAssertEqual(genSteps[0].stitchCountAfter, 104)
        // Step info ha nil
        XCTAssertNil(genSteps[1].stitchCountAfter)
        // Step B before deve essere riconciliato con Step A after (104) nonostante il passaggio intermedio nil
        XCTAssertEqual(genSteps[2].stitchCountBefore, genSteps[0].stitchCountAfter)
        XCTAssertEqual(genSteps[2].stitchCountBefore, 104)
    }
    
    func testRecalculateLocallyReconcilesConsecutiveSteps() {
        let project = KnittingProject(title: "Test Continuità Maglie")
        let step1 = GuideStep(
            sectionTitle: "Sprone",
            title: "Passo 1",
            instructionText: "Lavorare 114 maglie fino a 140 maglie",
            stitchCountBefore: 114,
            stitchCountAfter: 140,
            orderIndex: 0
        )
        let step2 = GuideStep(
            sectionTitle: "Sprone",
            title: "Passo 2",
            instructionText: "Lavorare con 140 maglie",
            stitchCountBefore: 140,
            stitchCountAfter: 140,
            orderIndex: 1
        )
        project.guideSteps.append(contentsOf: [step1, step2])
        
        // Ricalcola con ratio 19 / 21
        guard let response = GeminiService.recalculateGuideLocally(
            project: project,
            patternStitches: 21.0,
            patternRows: 28.0,
            userStitches: 19.0,
            userRows: 28.0
        ) else {
            XCTFail("Il ricalcolo locale non dovrebbe restituire nil")
            return
        }
        
        let genSteps = response.sections.flatMap(\.steps)
        XCTAssertEqual(genSteps.count, 2)
        // La continuità topologica garantisce che step2.before == step1.after
        XCTAssertEqual(genSteps[0].stitchCountAfter, genSteps[1].stitchCountBefore)
    }
    
    func testPreservationOfStateAfterInPlaceRecalculation() throws {
        let project = KnittingProject(title: "Maglione Test")
        let step = GuideStep(
            sectionTitle: "Sprone",
            title: "Giro raglan",
            stepType: "single_action",
            instructionText: "Lavorare 114 maglie",
            orderIndex: 0,
            hasCounter: true,
            counterLabel: "Ferro",
            currentStepCount: 15,
            targetStepCount: 30
        )
        step.isCompleted = false
        step.completedAt = nil
        step.extraCounterValues = [15, 2]
        project.guideSteps.append(step)
        
        let genResponse = try XCTUnwrap(GeminiService.recalculateGuideLocally(
            project: project,
            patternStitches: 21.0,
            patternRows: 28.0,
            userStitches: 19.0,
            userRows: 26.0
        ))
        
        try GaugeGuideManager.applyRecalculatedGuide(to: project, result: genResponse)
        
        XCTAssertEqual(project.guideSteps.count, 1)
        let updatedStep = project.guideSteps[0]
        XCTAssertEqual(updatedStep.id, step.id)
        XCTAssertEqual(updatedStep.currentStepCount, 15)
        XCTAssertEqual(updatedStep.extraCounterValues, [15, 2])
        XCTAssertFalse(updatedStep.isCompleted)
        XCTAssertNil(updatedStep.completedAt)
        XCTAssertNotNil(project.originalGuideJSON)
        XCTAssertTrue(project.isGaugeRecalculated)
    }
    
    func testRestoreFromSnapshot() throws {
        let project = KnittingProject(title: "Pattern Qualsiasi")
        let step = GuideStep(
            sectionTitle: "Bordo",
            title: "Coste 2x2",
            stepType: "single_action",
            instructionText: "Avviare 114 maglie",
            stitchCountBefore: 114,
            stitchCountAfter: 114,
            orderIndex: 0,
            hasCounter: true,
            counterLabel: "Ferri",
            currentStepCount: 5,
            targetStepCount: 10
        )
        project.guideSteps.append(step)
        
        let genResponse = try XCTUnwrap(GeminiService.recalculateGuideLocally(
            project: project,
            patternStitches: 21.0,
            patternRows: 28.0,
            userStitches: 19.0,
            userRows: 26.0
        ))
        
        try GaugeGuideManager.applyRecalculatedGuide(to: project, result: genResponse)
        XCTAssertTrue(project.isGaugeRecalculated)
        XCTAssertNotNil(project.originalGuideJSON)
        XCTAssertEqual(project.guideSteps[0].stitchCountBefore, 103)
        
        // Esegui restore da snapshot
        try GaugeGuideManager.restoreOriginalGuide(for: project)
        XCTAssertFalse(project.isGaugeRecalculated)
        XCTAssertNil(project.originalGuideJSON)
        XCTAssertEqual(project.guideSteps[0].stitchCountBefore, 114)
        XCTAssertEqual(project.guideSteps[0].currentStepCount, 5)
    }
    
    func testRestoreWithoutSnapshotFailsOnNonNoFrillsProject() {
        let project = KnittingProject(title: "Sciarpa Semplice")
        let step = GuideStep(
            sectionTitle: "Inizio",
            title: "Avvio",
            instructionText: "Avviare 40 maglie",
            stitchCountBefore: 40,
            stitchCountAfter: 40,
            orderIndex: 0
        )
        project.guideSteps.append(step)
        project.originalGuideJSON = nil
        
        XCTAssertThrowsError(try GaugeGuideManager.restoreOriginalGuide(for: project)) { error in
            guard let gaugeError = error as? GaugeRecalculationError,
                  case .noSnapshotAvailable = gaugeError else {
                XCTFail("Atteso errore noSnapshotAvailable, ricevuto: \(error)")
                return
            }
        }
        
        // Verifica che gli step non siano stati toccati
        XCTAssertEqual(project.guideSteps.count, 1)
        XCTAssertEqual(project.guideSteps[0].stitchCountBefore, 40)
    }
    
    func testReorderedStepsWithSameCountDoesNotSwapCounters() throws {
        let project = KnittingProject(title: "Test Step Riordinati")
        let stepA = GuideStep(
            sectionTitle: "Sezione 1",
            title: "Passo A",
            stepType: "single_action",
            instructionText: "Lavorare 100 maglie",
            orderIndex: 0,
            hasCounter: true,
            currentStepCount: 10,
            targetStepCount: 20
        )
        let stepB = GuideStep(
            sectionTitle: "Sezione 2",
            title: "Passo B",
            stepType: "single_action",
            instructionText: "Lavorare 120 maglie",
            orderIndex: 1,
            hasCounter: true,
            currentStepCount: 50,
            targetStepCount: 60
        )
        project.guideSteps.append(contentsOf: [stepA, stepB])
        
        // Simula una risposta in cui i passaggi sono invertiti nell'array result, ma hanno stepId identici
        let genB = GeneratedStep(
            stepId: stepB.id.uuidString,
            title: "Passo B Ricalcolato",
            stepType: "single_action",
            instruction: "Lavorare 110 maglie",
            subSteps: [],
            repeatVariations: [],
            rowsPerRepeat: nil,
            totalRepeats: nil,
            stitchCountBefore: 110,
            stitchCountAfter: 110,
            targetMeasureCm: nil,
            hasCounter: true,
            counterLabel: "Ferri",
            targetStepCount: 55,
            sourcePage: nil,
            sourceQuote: nil
        )
        let genA = GeneratedStep(
            stepId: stepA.id.uuidString,
            title: "Passo A Ricalcolato",
            stepType: "single_action",
            instruction: "Lavorare 90 maglie",
            subSteps: [],
            repeatVariations: [],
            rowsPerRepeat: nil,
            totalRepeats: nil,
            stitchCountBefore: 90,
            stitchCountAfter: 90,
            targetMeasureCm: nil,
            hasCounter: true,
            counterLabel: "Ferri",
            targetStepCount: 18,
            sourcePage: nil,
            sourceQuote: nil
        )
        
        let invertedResponse = GeneratedGuideResponse(
            patternTitle: project.title,
            designer: project.designer,
            targetSize: project.selectedSize,
            gauge: nil,
            needles: nil,
            recalculationSummary: "Test Inverted",
            changedStepTitles: ["Passo B", "Passo A"],
            sections: [
                GeneratedSection(name: "Sezione 2", steps: [genB]),
                GeneratedSection(name: "Sezione 1", steps: [genA])
            ]
        )
        
        try GaugeGuideManager.applyRecalculatedGuide(to: project, result: invertedResponse)
        
        // Verifica che l'identità per stepId abbia mantenuto i contatori sui rispettivi step
        XCTAssertEqual(stepA.currentStepCount, 10)
        XCTAssertEqual(stepA.targetStepCount, 18)
        XCTAssertEqual(stepA.title, "Passo A Ricalcolato")
        
        XCTAssertEqual(stepB.currentStepCount, 50)
        XCTAssertEqual(stepB.targetStepCount, 55)
        XCTAssertEqual(stepB.title, "Passo B Ricalcolato")
    }
}
