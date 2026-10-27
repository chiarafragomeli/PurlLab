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
}
