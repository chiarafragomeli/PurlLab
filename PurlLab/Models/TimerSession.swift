import Foundation
import SwiftData

@Model
final class TimerSession {
    var id: UUID
    var startDate: Date
    var endDate: Date?
    var durationSeconds: TimeInterval
    
    var project: KnittingProject?
    
    init(
        startDate: Date = Date(),
        endDate: Date? = nil,
        durationSeconds: TimeInterval = 0
    ) {
        self.id = UUID()
        self.startDate = startDate
        self.endDate = endDate
        self.durationSeconds = durationSeconds
    }
}
