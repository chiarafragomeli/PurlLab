import XCTest
import SwiftData
@testable import PurlLab

// MARK: - TestClock per test deterministici senza attese reali
final class TestClock: AppClock, @unchecked Sendable {
    private var internalNow: Date
    private let lock = NSLock()
    private var pendingSleeps: [(deadline: Date, continuation: UnsafeContinuation<Void, Never>)] = []
    
    var now: Date {
        get { getNow() }
        set { setNow(newValue) }
    }
    
    private func getNow() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return internalNow
    }
    
    private func setNow(_ date: Date) {
        lock.lock()
        defer { lock.unlock() }
        internalNow = date
    }
    
    init(startDate: Date = Date()) {
        self.internalNow = startDate
    }
    
    func advance(by seconds: TimeInterval) {
        let ready = advanceTimeAndExtractReady(by: seconds)
        for cont in ready {
            cont.resume()
        }
    }
    
    private func advanceTimeAndExtractReady(by seconds: TimeInterval) -> [UnsafeContinuation<Void, Never>] {
        lock.lock()
        defer { lock.unlock() }
        internalNow = internalNow.addingTimeInterval(seconds)
        let current = internalNow
        var remaining: [(deadline: Date, continuation: UnsafeContinuation<Void, Never>)] = []
        var ready: [UnsafeContinuation<Void, Never>] = []
        for item in pendingSleeps {
            if item.deadline <= current {
                ready.append(item.continuation)
            } else {
                remaining.append(item)
            }
        }
        pendingSleeps = remaining
        return ready
    }
    
    private func addSleep(deadline: Date, continuation: UnsafeContinuation<Void, Never>) {
        lock.lock()
        defer { lock.unlock() }
        pendingSleeps.append((deadline: deadline, continuation: continuation))
    }
    
    func sleep(nanoseconds: UInt64) async throws {
        let durationSeconds = Double(nanoseconds) / 1_000_000_000.0
        let currentNow = now
        let deadline = currentNow.addingTimeInterval(durationSeconds)
        
        await withUnsafeContinuation { continuation in
            addSleep(deadline: deadline, continuation: continuation)
        }
        try Task.checkCancellation()
    }
    
    func reset() {
        let all = removeAllPending()
        for cont in all {
            cont.resume()
        }
    }
    
    private func removeAllPending() -> [UnsafeContinuation<Void, Never>] {
        lock.lock()
        defer { lock.unlock() }
        let ready = pendingSleeps.map(\.continuation)
        pendingSleeps.removeAll()
        return ready
    }
}

@MainActor
final class TimerManagerTests: XCTestCase {
    
    private var container: ModelContainer!
    private var context: ModelContext!
    private var testClock: TestClock!
    
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
        testClock = TestClock()
        TimerManager.shared.clock = testClock
        TimerManager.shared.configure(with: context)
        WatchConnectivityIOSManager.shared.configure(with: context)
    }
    
    override func tearDown() {
        _ = TimerManager.shared.pause()
        TimerManager.shared.clearPendingSessionsForTesting()
        TimerManager.shared.configure(with: nil)
        WatchConnectivityIOSManager.shared.configure(with: nil)
        TimerManager.shared.autoPauseMinutes = 15.0
        TimerManager.shared.clock = SystemClock()
        testClock?.reset()
        testClock = nil
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
        
        testClock.advance(by: 30)
        
        let duration = TimerManager.shared.pause()
        XCTAssertEqual(duration, 30.0, accuracy: 0.001)
        XCTAssertFalse(TimerManager.shared.isRunning)
        XCTAssertNil(TimerManager.shared.activeProjectId)
        
        XCTAssertEqual(project.timerSessions.count, 1)
        let savedSession = try XCTUnwrap(project.timerSessions.first)
        XCTAssertEqual(savedSession.durationSeconds, 30.0, accuracy: 0.001)
        XCTAssertEqual(project.totalSecondsWorked, 30.0, accuracy: 0.001)
        XCTAssertNotNil(savedSession.endDate)
    }
    
    func testStartNewProjectAutoPausesAndPersistsPreviousProject() async throws {
        let projectA = KnittingProject(title: "Progetto A")
        let projectB = KnittingProject(title: "Progetto B")
        context.insert(projectA)
        context.insert(projectB)
        try context.save()
        
        TimerManager.shared.start(for: projectA.id)
        testClock.advance(by: 30)
        
        // Avviare il timer per il progetto B deve mettere in pausa A e persistere la sessione di A
        TimerManager.shared.start(for: projectB.id)
        XCTAssertEqual(TimerManager.shared.activeProjectId, projectB.id)
        XCTAssertEqual(projectA.timerSessions.count, 1)
        XCTAssertEqual(projectA.totalSecondsWorked, 30.0, accuracy: 0.001)
        XCTAssertEqual(projectB.timerSessions.count, 0)
        
        testClock.advance(by: 45)
        TimerManager.shared.pause()
        
        XCTAssertEqual(projectB.timerSessions.count, 1)
        XCTAssertEqual(projectB.totalSecondsWorked, 45.0, accuracy: 0.001)
    }
    
    func testRecalculateElapsedFromSessionStartDateNotFrozenValue() async throws {
        let project = KnittingProject(title: "Progetto Test Ricalcolo")
        context.insert(project)
        try context.save()
        
        TimerManager.shared.start(for: project.id)
        // Simula il timer congelato a 0 (es. tick non ancora scattato o app in background)
        TimerManager.shared.elapsedSecondsInCurrentSession = 0
        
        testClock.advance(by: 40)
        
        let duration = TimerManager.shared.pause()
        // Deve ricalcolare da sessionStartDate e non usare il valore 0 congelato
        XCTAssertEqual(duration, 40.0, accuracy: 0.001)
        XCTAssertEqual(project.totalSecondsWorked, 40.0, accuracy: 0.001)
    }
    
    func testAutoPausePersistsSessionWhenInactivityTimeoutExceeded() async throws {
        let project = KnittingProject(title: "Progetto Auto Pause")
        context.insert(project)
        try context.save()
        
        TimerManager.shared.autoPauseMinutes = 1.0 // 60s
        TimerManager.shared.start(for: project.id)
        
        // Simula sessione iniziata 5 minuti fa, con ultima interazione 2 minuti fa
        let now = testClock.now
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
        let expectedEnd = now.addingTimeInterval(-60)
        XCTAssertEqual(session.endDate?.timeIntervalSince1970 ?? 0, expectedEnd.timeIntervalSince1970, accuracy: 1.0)
    }
    
    func testPausePreservesSessionAsPendingOnPersistFailureAndRetriesOnStartFlushOrForeground() async throws {
        let project = KnittingProject(title: "Progetto Test Pending")
        context.insert(project)
        try context.save()
        
        TimerManager.shared.start(for: project.id)
        testClock.advance(by: 30)
        
        // Simula disconnessione / assenza del modelContext durante la pausa
        TimerManager.shared.configure(with: nil)
        
        let duration = TimerManager.shared.pause()
        XCTAssertEqual(duration, 30.0, accuracy: 0.001)
        XCTAssertFalse(TimerManager.shared.isRunning)
        
        // La sessione non deve essere andata perduta: deve trovarsi in pendingSessions
        XCTAssertEqual(TimerManager.shared.pendingSessions.count, 1)
        XCTAssertEqual(project.timerSessions.count, 0)
        
        // 1. Test recupero al foreground
        TimerManager.shared.configure(with: context)
        // Riconfigurando il context senza chiamare foreground la sessione viene già retriata da configure
        XCTAssertEqual(TimerManager.shared.pendingSessions.count, 0)
        XCTAssertEqual(project.timerSessions.count, 1)
        
        // 2. Test recupero al prossimo start
        TimerManager.shared.clearPendingSessionsForTesting()
        TimerManager.shared.start(for: project.id)
        testClock.advance(by: 20)
        TimerManager.shared.configure(with: nil)
        _ = TimerManager.shared.pause()
        XCTAssertEqual(TimerManager.shared.pendingSessions.count, 1)
        
        TimerManager.shared.configure(with: context)
        // Crea nuovo progetto e chiama start: deve svuotare le pendenti
        let project2 = KnittingProject(title: "Progetto 2")
        context.insert(project2)
        try context.save()
        TimerManager.shared.start(for: project2.id)
        XCTAssertEqual(TimerManager.shared.pendingSessions.count, 0)
        _ = TimerManager.shared.pause()
    }
    
    func testCancelTimerStopsTimerWithoutSavingDuration() async throws {
        let project = KnittingProject(title: "Progetto Test Cancel")
        context.insert(project)
        try context.save()
        
        TimerManager.shared.start(for: project.id)
        XCTAssertTrue(TimerManager.shared.isRunning)
        XCTAssertEqual(TimerManager.shared.activeProjectId, project.id)
        
        testClock.advance(by: 30)
        
        TimerManager.shared.cancelTimer(for: project.id)
        
        XCTAssertFalse(TimerManager.shared.isRunning)
        XCTAssertNil(TimerManager.shared.activeProjectId)
        XCTAssertEqual(TimerManager.shared.elapsedSecondsInCurrentSession, 0)
        XCTAssertEqual(project.totalSecondsWorked, 0)
        XCTAssertTrue(project.timerSessions.isEmpty)
    }
    
    func testFlushElapsedToTotalPreservesStartDateOnSaveFailure() async throws {
        let project = KnittingProject(title: "Progetto Test Flush Error")
        context.insert(project)
        try context.save()
        
        TimerManager.shared.start(for: project.id)
        guard let originalStart = TimerManager.shared.sessionStartDate else {
            XCTFail("sessionStartDate non impostato")
            return
        }
        
        testClock.advance(by: 20)
        
        // Simula disconnessione / assenza del modelContext (save impossibile)
        TimerManager.shared.configure(with: nil)
        
        let flushed = TimerManager.shared.flushElapsedToTotal()
        XCTAssertEqual(flushed, 0, "Se il save fallisce, flushElapsedToTotal deve restituire 0")
        XCTAssertEqual(TimerManager.shared.sessionStartDate, originalStart, "sessionStartDate non deve essere avanzato se il salvataggio fallisce")
        
        // Ripristina il modelContext: ora il flush deve avere successo e avanzare la data
        TimerManager.shared.configure(with: context)
        testClock.advance(by: 10)
        let successFlush = TimerManager.shared.flushElapsedToTotal()
        XCTAssertEqual(successFlush, 30.0, accuracy: 0.001)
        XCTAssertNotEqual(TimerManager.shared.sessionStartDate, originalStart)
        XCTAssertEqual(project.timerSessions.count, 1)
    }
    
    func testRetryPendingSessionsDiscardsSessionIfProjectDeleted() async throws {
        let project = KnittingProject(title: "Progetto Da Eliminare")
        context.insert(project)
        try context.save()
        let projId = project.id
        
        TimerManager.shared.start(for: projId)
        testClock.advance(by: 25)
        
        // Simula disconnessione / assenza del modelContext durante la pausa
        TimerManager.shared.configure(with: nil)
        _ = TimerManager.shared.pause()
        
        // La sessione è trattenuta in pendingSessions per errore temporaneo
        XCTAssertEqual(TimerManager.shared.pendingSessions.count, 1)
        XCTAssertEqual(TimerManager.shared.pendingSessions.first?.projectId, projId)
        
        // Ora l'utente elimina il progetto dall'archivio
        context.delete(project)
        try context.save()
        
        // Quando il modelContext torna disponibile, retryPendingSessions deve rilevare che il progetto non esiste più
        // e SCARTARE la sessione invece di trattenerla all'infinito
        TimerManager.shared.configure(with: context)
        
        XCTAssertTrue(TimerManager.shared.pendingSessions.isEmpty, "La sessione pendente per un progetto inesistente deve essere scartata dalla coda")
    }
}
