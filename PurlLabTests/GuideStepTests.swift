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
}
