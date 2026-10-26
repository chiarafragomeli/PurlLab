import Foundation
import SwiftData

@Model
final class GuideStep {
    var id: UUID
    var sectionTitle: String
    var instructionText: String
    var stitchCountAfter: Int?
    var targetMeasureCm: Double?
    var sourcePage: Int?
    var sourceQuote: String?
    var isCompleted: Bool
    var orderIndex: Int
    var hasCounter: Bool = false
    var counterLabel: String?
    var currentStepCount: Int = 0
    var targetStepCount: Int?
    
    var project: KnittingProject?
    
    init(
        sectionTitle: String,
        instructionText: String,
        stitchCountAfter: Int? = nil,
        targetMeasureCm: Double? = nil,
        sourcePage: Int? = nil,
        sourceQuote: String? = nil,
        isCompleted: Bool = false,
        orderIndex: Int = 0,
        hasCounter: Bool = false,
        counterLabel: String? = nil,
        currentStepCount: Int = 0,
        targetStepCount: Int? = nil
    ) {
        self.id = UUID()
        self.sectionTitle = sectionTitle
        self.instructionText = instructionText
        self.stitchCountAfter = stitchCountAfter
        self.targetMeasureCm = targetMeasureCm
        self.sourcePage = sourcePage
        self.sourceQuote = sourceQuote
        self.isCompleted = isCompleted
        self.orderIndex = orderIndex
        self.hasCounter = hasCounter
        self.counterLabel = counterLabel
        self.currentStepCount = currentStepCount
        self.targetStepCount = targetStepCount
    }
}
