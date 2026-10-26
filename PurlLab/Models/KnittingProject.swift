import Foundation
import SwiftData

@Model
final class KnittingProject {
    var id: UUID
    var title: String
    var designer: String
    var selectedSize: String
    var notes: String
    @Attribute(.externalStorage) var pdfData: Data?
    var createdAt: Date
    var updatedAt: Date
    var totalSecondsWorked: TimeInterval
    
    @Relationship(deleteRule: .cascade) var counters: [RowCounter] = []
    @Relationship(deleteRule: .cascade) var guideSteps: [GuideStep] = []
    @Relationship(deleteRule: .cascade) var timerSessions: [TimerSession] = []
    
    init(
        title: String,
        designer: String = "",
        selectedSize: String = "",
        notes: String = "",
        pdfData: Data? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.designer = designer
        self.selectedSize = selectedSize
        self.notes = notes
        self.pdfData = pdfData
        self.createdAt = Date()
        self.updatedAt = Date()
        self.totalSecondsWorked = 0
    }
}
