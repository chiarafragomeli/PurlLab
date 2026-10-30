import Foundation
import SwiftData

// MARK: - RowCounter Metodi Comportamentali
extension RowCounter {
    func increment() {
        currentCount += stepIncrement
        if let target = targetCount, target > 0, currentCount >= target && resetOnTarget {
            currentCount = 0
        }
    }
    
    func decrement() {
        if currentCount >= stepIncrement {
            currentCount -= stepIncrement
        } else {
            currentCount = 0
        }
    }
    
    func reset() {
        currentCount = 0
    }
}
