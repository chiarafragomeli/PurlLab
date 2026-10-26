import Foundation
import SwiftData

@Model
final class GuideStep {
    var id: UUID
    var sectionTitle: String
    var title: String = ""
    var stepType: String = "single_action" // "info", "single_action", "repeat_pattern", "work_to_measure"
    var instructionText: String
    var subSteps: [String] = []
    var repeatVariations: [String] = []
    var rowsPerRepeat: Int?
    var totalRepeats: Int?
    var stitchCountBefore: Int?
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
        title: String = "",
        stepType: String = "single_action",
        instructionText: String,
        subSteps: [String] = [],
        repeatVariations: [String] = [],
        rowsPerRepeat: Int? = nil,
        totalRepeats: Int? = nil,
        stitchCountBefore: Int? = nil,
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
        self.title = title
        self.stepType = stepType
        self.instructionText = instructionText
        self.subSteps = subSteps
        self.repeatVariations = repeatVariations
        self.rowsPerRepeat = rowsPerRepeat
        self.totalRepeats = totalRepeats
        self.stitchCountBefore = stitchCountBefore
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
