import XCTest
import SwiftData
@testable import PurlLab

@MainActor
final class TimerManagerTests: XCTestCase {
    
    private var container: ModelContainer!
    private var context: ModelContext!
    
    override func setUp() {
        super.setUp()
        let schema = Schema([
            KnittingProject.self,
            TimerSession.self,
            RowCounter.self,
            GuideStep.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        TimerManager.shared.configure(with: context)
        WatchConnectivityIOSManager.shared.configure(with: context)
    }
    
    override func tearDown() {
        _ = TimerManager.shared.pause()
        TimerManager.shared.configure(with: nil)
        WatchConnectivityIOSManager.shared.configure(with: nil)
        TimerManager.shared.autoPauseMinutes = 15.0
        container = nil
        context = nil
        super.tearDown()
    }
    
    func testFormatTimeUnderOneHour() {
        let manager = TimerManager.shared
        // 5 minuti e 22 secondi = 322s
        let formatted = manager.formatTime(322)
        XCTAssertEqual(formatted, "05m 22s")
    }
    
    func testFormatTimeOverOneHour() {
        let manager = TimerManager.shared
        // 1 ora, 15 minuti e 30 secondi = 4530s
        let formatted = manager.formatTime(4530)
        XCTAssertEqual(formatted, "1h 15m 30s")
    }
    
    func testFormatTimeZero() {
        let manager = TimerManager.shared
        let formatted = manager.formatTime(0)
        XCTAssertEqual(formatted, "00m 00s")
    }
    
    func testPausePersistsTimerSessionAndUpdatesProjectTotalSecondsWorked() async throws {
        let project = KnittingProject(title: "Timer Test Progetto")
        context.insert(project)
        try context.save()
        
        TimerManager.shared.start(for: project.id)
        XCTAssertTrue(TimerManager.shared.isRunning)
        XCTAssertEqual(TimerManager.shared.activeProjectId, project.id)
        
        try await Task.sleep(nanoseconds: 30_000_000) // 30ms
        
        let duration = TimerManager.shared.pause()
        XCTAssertGreaterThan(duration, 0)
        XCTAssertFalse(TimerManager.shared.isRunning)
        XCTAssertNil(TimerManager.shared.activeProjectId)
        
        XCTAssertEqual(project.timerSessions.count, 1)
        let savedSession = try XCTUnwrap(project.timerSessions.first)
        XCTAssertEqual(savedSession.durationSeconds, duration, accuracy: 0.001)
        XCTAssertEqual(project.totalSecondsWorked, duration, accuracy: 0.001)
        XCTAssertNotNil(savedSession.endDate)
    }
    
    func testStartNewProjectAutoPausesAndPersistsPreviousProject() async throws {
        let projectA = KnittingProject(title: "Progetto A")
        let projectB = KnittingProject(title: "Progetto B")
        context.insert(projectA)
        context.insert(projectB)
        try context.save()
        
        TimerManager.shared.start(for: projectA.id)
        try await Task.sleep(nanoseconds: 30_000_000)
        
        // Avviare il timer per il progetto B deve mettere in pausa A e persistere la sessione di A
        TimerManager.shared.start(for: projectB.id)
        XCTAssertEqual(TimerManager.shared.activeProjectId, projectB.id)
        XCTAssertEqual(projectA.timerSessions.count, 1)
        XCTAssertGreaterThan(projectA.totalSecondsWorked, 0)
        XCTAssertEqual(projectB.timerSessions.count, 0)
        
        try await Task.sleep(nanoseconds: 30_000_000)
        TimerManager.shared.pause()
        
        XCTAssertEqual(projectB.timerSessions.count, 1)
        XCTAssertGreaterThan(projectB.totalSecondsWorked, 0)
    }
    
    func testRecalculateElapsedFromSessionStartDateNotFrozenValue() async throws {
        let project = KnittingProject(title: "Progetto Test Ricalcolo")
        context.insert(project)
        try context.save()
        
        TimerManager.shared.start(for: project.id)
        // Simula il timer congelato a 0 (es. tick non ancora scattato o app in background)
        TimerManager.shared.elapsedSecondsInCurrentSession = 0
        
        try await Task.sleep(nanoseconds: 40_000_000)
        
        let duration = TimerManager.shared.pause()
        // Deve ricalcolare da sessionStartDate e non usare il valore 0 congelato
        XCTAssertGreaterThan(duration, 0.02)
        XCTAssertEqual(project.totalSecondsWorked, duration, accuracy: 0.001)
    }
    
    func testAutoPausePersistsSessionWhenInactivityTimeoutExceeded() async throws {
        let project = KnittingProject(title: "Progetto Auto Pause")
        context.insert(project)
        try context.save()
        
        TimerManager.shared.autoPauseMinutes = 1.0 // 60s
        TimerManager.shared.start(for: project.id)
        
        // Simula sessione iniziata 5 minuti fa, con ultima interazione 2 minuti fa
        let now = Date()
        TimerManager.shared.sessionStartDate = now.addingTimeInterval(-300) // 5 min fa
        TimerManager.shared.lastInteractionDate = now.addingTimeInterval(-120) // 2 min fa
        
        // Simula il risveglio foreground che rileva il superamento del timeout (inattivo da 120s > 60s)
        TimerManager.shared.handleAppWillEnterForeground()
        
        XCTAssertFalse(TimerManager.shared.isRunning)
        XCTAssertEqual(project.timerSessions.count, 1)
        let session = try XCTUnwrap(project.timerSessions.first)
        // Lavoro accreditato: da -300s fino a (-120s + 60s) = -60s => 240s
        XCTAssertEqual(session.durationSeconds, 240, accuracy: 1.0)
        XCTAssertEqual(project.totalSecondsWorked, 240, accuracy: 1.0)
    }
}
