import Foundation
import SwiftData

@Model
final class RowCounter {
    var id: UUID
    var title: String
    var currentCount: Int
    var targetCount: Int?
    var stepIncrement: Int
    var resetOnTarget: Bool
    var orderIndex: Int
    
    var project: KnittingProject?
    
    init(
        title: String,
        currentCount: Int = 0,
        targetCount: Int? = nil,
        stepIncrement: Int = 1,
        resetOnTarget: Bool = false,
        orderIndex: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.currentCount = currentCount
        self.targetCount = targetCount
        self.stepIncrement = stepIncrement
        self.resetOnTarget = resetOnTarget
        self.orderIndex = orderIndex
    }
    
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
