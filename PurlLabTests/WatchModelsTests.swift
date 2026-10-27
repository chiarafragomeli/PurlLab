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
}
