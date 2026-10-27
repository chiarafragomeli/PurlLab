import XCTest
import SwiftData
@testable import PurlLab

final class RowCounterTests: XCTestCase {
    
    func testInitialization() {
        let counter = RowCounter(title: "Contatore Globale")
        XCTAssertEqual(counter.title, "Contatore Globale")
        XCTAssertEqual(counter.currentCount, 0)
        XCTAssertNil(counter.targetCount)
        XCTAssertEqual(counter.stepIncrement, 1)
        XCTAssertFalse(counter.resetOnTarget)
        XCTAssertEqual(counter.orderIndex, 0)
    }
    
    func testIncrementStandard() {
        let counter = RowCounter(title: "Test", currentCount: 5)
        counter.increment()
        XCTAssertEqual(counter.currentCount, 6)
        counter.increment()
        XCTAssertEqual(counter.currentCount, 7)
    }
    
    func testIncrementCustomStep() {
        let counter = RowCounter(title: "Test", currentCount: 0, stepIncrement: 2)
        counter.increment()
        XCTAssertEqual(counter.currentCount, 2)
        counter.increment()
        XCTAssertEqual(counter.currentCount, 4)
    }
    
    func testDecrementStopsAtZero() {
        let counter = RowCounter(title: "Test", currentCount: 1)
        counter.decrement()
        XCTAssertEqual(counter.currentCount, 0)
        counter.decrement()
        XCTAssertEqual(counter.currentCount, 0, "Il contatore non deve diventare negativo")
    }
    
    func testDecrementCustomStep() {
        let counter = RowCounter(title: "Test", currentCount: 5, stepIncrement: 2)
        counter.decrement()
        XCTAssertEqual(counter.currentCount, 3)
        counter.decrement()
        XCTAssertEqual(counter.currentCount, 1)
        counter.decrement()
        XCTAssertEqual(counter.currentCount, 0)
    }
    
    func testReset() {
        let counter = RowCounter(title: "Test", currentCount: 42)
        counter.reset()
        XCTAssertEqual(counter.currentCount, 0)
    }
    
    func testTargetCountWithoutReset() {
        let counter = RowCounter(title: "Test", currentCount: 9, targetCount: 10, resetOnTarget: false)
        counter.increment()
        XCTAssertEqual(counter.currentCount, 10)
        counter.increment()
        XCTAssertEqual(counter.currentCount, 11, "Senza resetOnTarget deve continuare a contare")
    }
    
    func testTargetCountWithResetOnTarget() {
        let counter = RowCounter(title: "Test", currentCount: 9, targetCount: 10, resetOnTarget: true)
        counter.increment()
        XCTAssertEqual(counter.currentCount, 0, "Con resetOnTarget deve azzerarsi una volta raggiunto l'obiettivo")
    }
}
