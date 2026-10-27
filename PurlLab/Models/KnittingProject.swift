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
    var completedAt: Date?
    
    // Gauge (Campione su 10x10 cm)
    var patternGaugeStitches: Double?
    var patternGaugeRows: Double?
    var userGaugeStitches: Double?
    var userGaugeRows: Double?
    var isGaugeRecalculated: Bool = false
    var gaugeRecalculationSummary: String?
    
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

// MARK: - Statistiche e Schede di Lavoro
extension KnittingProject {
    /// Calcola il numero totale di ferri lavorati attraverso tutte le schede della guida
    var totalGuideRowsWorked: Int {
        guideSteps.reduce(0) { $0 + $1.currentStepCount }
    }
    
    /// Calcola il numero totale di maglie lavorate nel progetto finora.
    /// Per ciascuna scheda con ferri lavorati, tiene conto delle maglie per ferro (anche in presenza di aumenti/diminuzioni).
    var totalStitchesWorked: Int {
        var total = 0
        var lastKnownStitches = 0
        
        let sorted = guideSteps.sorted(by: { $0.orderIndex < $1.orderIndex })
        for step in sorted {
            let startSts = step.stitchCountBefore ?? (lastKnownStitches > 0 ? lastKnownStitches : 0)
            let endSts = step.stitchCountAfter ?? startSts
            if endSts > 0 { lastKnownStitches = endSts }
            
            let workedRows = step.currentStepCount
            guard workedRows > 0 else { continue }
            
            if startSts == endSts || startSts == 0 || endSts == 0 {
                let sts = max(startSts, endSts)
                total += workedRows * (sts > 0 ? sts : 1)
            } else {
                let target = max(step.targetStepCount ?? workedRows, workedRows)
                let diff = Double(endSts - startSts)
                for r in 1...workedRows {
                    let progress = Double(r) / Double(target)
                    let stsInRow = Int(round(Double(startSts) + diff * progress))
                    total += max(1, stsInRow)
                }
            }
        }
        
        // Se non ci sono schede guida ma ci sono contatori manuali, stima dalle maglie del campione
        if total == 0 {
            let manualRows = counters.first?.currentCount ?? 0
            if manualRows > 0 {
                let gaugeSts = Int(round(userGaugeStitches ?? patternGaugeStitches ?? 20.0))
                total = manualRows * max(10, gaugeSts * 2)
            }
        }
        
        return total
    }
    
    /// Stima del numero totale di maglie del pattern completo (obiettivo al 100%)
    var targetTotalStitches: Int? {
        var total = 0
        var lastKnownStitches = 0
        let sorted = guideSteps.sorted(by: { $0.orderIndex < $1.orderIndex })
        var hasValidTargets = false
        
        for step in sorted {
            guard let targetRows = step.targetStepCount, targetRows > 0 else { continue }
            hasValidTargets = true
            let startSts = step.stitchCountBefore ?? (lastKnownStitches > 0 ? lastKnownStitches : 0)
            let endSts = step.stitchCountAfter ?? startSts
            if endSts > 0 { lastKnownStitches = endSts }
            
            if startSts == endSts || startSts == 0 || endSts == 0 {
                total += targetRows * max(startSts, endSts)
            } else {
                let diff = Double(endSts - startSts)
                for r in 1...targetRows {
                    let progress = Double(r) / Double(targetRows)
                    let stsInRow = Int(round(Double(startSts) + diff * progress))
                    total += max(1, stsInRow)
                }
            }
        }
        
        return hasValidTargets && total > 0 ? total : nil
    }
    
    /// Totale dei ferri obiettivo in tutto il pattern
    var targetTotalRows: Int? {
        let total = guideSteps.compactMap { $0.targetStepCount }.reduce(0, +)
        return total > 0 ? total : nil
    }
    
    /// Percentuale di avanzamento globale basata sulle maglie lavorate (o sui ferri)
    var globalProgress: Double {
        if let targetSts = targetTotalStitches, targetSts > 0 {
            return min(Double(totalStitchesWorked) / Double(targetSts), 1.0)
        }
        if let targetRows = targetTotalRows, targetRows > 0 {
            return min(Double(totalGuideRowsWorked) / Double(targetRows), 1.0)
        }
        return 0.0
    }
    
    /// Restituisce la scheda operativa attiva (privilegiando schede con contatore effettivo per il lavoro ai ferri)
    func activeWorkingStep(preferredStepId: UUID? = nil) -> GuideStep? {
        let sorted = guideSteps.sorted(by: { $0.orderIndex < $1.orderIndex })
        if let preferred = preferredStepId, let match = sorted.first(where: { $0.id == preferred }) {
            return match
        }
        
        // 1. Prima cerca la prima scheda non completata che possiede un contatore o obiettivo ferri
        if let working = sorted.first(where: { !$0.isCompleted && ($0.hasCounter || ($0.targetStepCount != nil && $0.targetStepCount! > 0)) }) {
            return working
        }
        
        // 2. Se tutte le schede con contatore sono completate, la prima non completata
        if let firstIncomplete = sorted.first(where: { !$0.isCompleted }) {
            return firstIncomplete
        }
        return sorted.first
    }
}
