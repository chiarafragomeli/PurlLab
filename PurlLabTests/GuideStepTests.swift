import XCTest
import SwiftData
@testable import PurlLab

final class GuideStepTests: XCTestCase {
    
    func testRepeatPatternTargetCalculation() {
        let step = GuideStep(
            sectionTitle: "Scollo",
            title: "Ferri Accorciati",
            stepType: "repeat_pattern",
            instructionText: "German Short Rows",
            rowsPerRepeat: 4,
            totalRepeats: 5,
            hasCounter: true
        )
        
        let calculatedTarget = (step.rowsPerRepeat ?? 0) * (step.totalRepeats ?? 0)
        XCTAssertEqual(calculatedTarget, 20)
    }
    
    func testExtraCounters() {
        let step = GuideStep(
            sectionTitle: "Manica",
            title: "Corpo Manica",
            instructionText: "Aumenti ogni 6 ferri",
            hasCounter: true,
            targetStepCount: 60
        )
        
        // Aggiungi contatore extra
        step.extraCounterLabels.append("Calature")
        step.extraCounterValues.append(0)
        
        XCTAssertEqual(step.extraCounterLabels.count, 1)
        XCTAssertEqual(step.extraCounterValues.first, 0)
        
        // Incrementa
        step.extraCounterValues[0] += 1
        XCTAssertEqual(step.extraCounterValues[0], 1)
        
        // Decrementa con blocco a 0
        step.extraCounterValues[0] = max(0, step.extraCounterValues[0] - 2)
        XCTAssertEqual(step.extraCounterValues[0], 0)
    }
    
    func testCompletionToggle() {
        let step = GuideStep(
            sectionTitle: "Bordo",
            instructionText: "Intreccia",
            isCompleted: false
        )
        XCTAssertFalse(step.isCompleted)
        
        step.isCompleted = true
        step.completedAt = Date()
        XCTAssertTrue(step.isCompleted)
        XCTAssertNotNil(step.completedAt)
    }
    
    func testCounterKindAndIsStitchCounter() {
        // 1. Esplicito counterKind = "stitch"
        let stitchStep = GuideStep(
            sectionTitle: "Avvio",
            instructionText: "Avvia 114 maglie",
            counterLabel: "Avvio",
            counterKind: "stitch",
            currentStepCount: 114,
            targetStepCount: 114
        )
        XCTAssertTrue(stitchStep.isStitchCounter)
        
        // 2. Esplicito counterKind = "maglie" o "punto"
        let maglieStep = GuideStep(
            sectionTitle: "Aumenti",
            instructionText: "Aumenta",
            counterKind: "maglie"
        )
        XCTAssertTrue(maglieStep.isStitchCounter)
        
        // 3. counterKind = "row"
        let rowStep = GuideStep(
            sectionTitle: "Sprone",
            instructionText: "Lavora 20 ferri",
            counterLabel: "Ferri Sprone",
            counterKind: "row"
        )
        XCTAssertFalse(rowStep.isStitchCounter)
        
        // 4. Fallback su counterLabel contenente "maglie" quando counterKind è nil
        let legacyStitchStep = GuideStep(
            sectionTitle: "Avvio",
            instructionText: "Avvia",
            counterLabel: "Maglie Avviate",
            counterKind: nil
        )
        XCTAssertTrue(legacyStitchStep.isStitchCounter)
        
        // 5. Fallback su counterLabel ferri quando counterKind è nil
        let legacyRowStep = GuideStep(
            sectionTitle: "Bordo",
            instructionText: "Lavora",
            counterLabel: "Ferri a Coste",
            counterKind: nil
        )
        XCTAssertFalse(legacyRowStep.isStitchCounter)
    }
    
    func testSafeAccessorsPreventDetachedCrashes() {
        let step = GuideStep(
            sectionTitle: "Test Detached",
            instructionText: "Istruzioni",
            subSteps: ["Passo 1", "Passo 2"],
            repeatVariations: ["Var 1"]
        )
        step.extraCounterLabels = ["Contatore 1"]
        step.extraCounterValues = [3]
        
        // Quando non collegato o eliminato, i safe accessors restituiscono liste vuote senza causare crash
        XCTAssertTrue(step.isDetachedOrDeleted)
        XCTAssertEqual(step.safeSubSteps, [])
        XCTAssertEqual(step.safeRepeatVariations, [])
        XCTAssertEqual(step.safeExtraCounterLabels, [])
        XCTAssertEqual(step.safeExtraCounterValues, [])
    }
}
