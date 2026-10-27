import XCTest
@testable import PurlLab

@MainActor
final class TimerManagerTests: XCTestCase {
    
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
}
