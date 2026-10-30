import Foundation
import SwiftData

// MARK: - Statistiche e Schede di Lavoro
extension KnittingProject {
    /// Calcola il numero totale di ferri lavorati attraverso tutte le schede della guida (o del contatore globale),
    /// escludendo esplicitamente i contatori di maglie (ALTO-08)
    var totalGuideRowsWorked: Int {
        let rowSteps = guideSteps.filter { !$0.isStitchCounter }
        if !rowSteps.isEmpty {
            return rowSteps.reduce(0) { $0 + $1.currentStepCount }
        }
        return counters.first(where: { $0.title.localizedCaseInsensitiveContains("globale") })?.currentCount ?? counters.first?.currentCount ?? 0
    }
    
    /// Calcola il numero totale di maglie lavorate nel progetto finora.
    /// Per ciascuna scheda con ferri lavorati, tiene conto delle maglie per ferro (anche in presenza di aumenti/diminuzioni).
    /// Per le schede che contano maglie (isStitchCounter, es. Avvio maglie), somma direttamente le maglie lavorate.
    var totalStitchesWorked: Int {
        var total = 0
        var lastKnownStitches = 0
        
        let sorted = guideSteps.sorted(by: { $0.orderIndex < $1.orderIndex })
        for step in sorted {
            if step.isStitchCounter {
                // Per le schede che contano maglie (es. Avvio maglie, aumenti singoli), il contatore È già il numero di maglie lavorate!
                let sts = step.currentStepCount
                total += sts
                if sts > 0 {
                    lastKnownStitches = max(lastKnownStitches, step.stitchCountAfter ?? sts)
                } else if let target = step.targetStepCount, target > 0 {
                    lastKnownStitches = max(lastKnownStitches, target)
                }
            } else {
                // Per le schede che contano ferri/giri
                let startSts = step.stitchCountBefore ?? (lastKnownStitches > 0 ? lastKnownStitches : 0)
                let endSts = step.stitchCountAfter ?? startSts
                let meaningfulStitches = max(startSts, endSts)
                if meaningfulStitches > 0 { lastKnownStitches = endSts }
                
                let workedRows = step.currentStepCount
                guard workedRows > 0 else { continue }
                guard meaningfulStitches > 0 else { continue }
                
                if startSts == endSts || startSts == 0 || endSts == 0 {
                    total += workedRows * meaningfulStitches
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
        }
        
        // Includi anche eventuali contatori personalizzati esplicitamente dedicati alle maglie
        for counter in counters {
            let title = counter.title.lowercased()
            if title.contains("magli") || title.contains("punti") || title.contains("stitch") {
                total += counter.currentCount
            }
        }
        
        // Se non ci sono schede guida ma ci sono contatori manuali, stima dalle maglie del campione
        if total == 0 && guideSteps.isEmpty {
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
            guard let targetRows = step.effectiveTargetCount, targetRows > 0 else { continue }
            
            if step.isStitchCounter {
                hasValidTargets = true
                total += targetRows
                lastKnownStitches = max(lastKnownStitches, step.stitchCountAfter ?? targetRows)
            } else {
                let startSts = step.stitchCountBefore ?? (lastKnownStitches > 0 ? lastKnownStitches : 0)
                let endSts = step.stitchCountAfter ?? startSts
                let meaningfulStitches = max(startSts, endSts)
                if meaningfulStitches > 0 { lastKnownStitches = endSts }
                guard meaningfulStitches > 0 else { continue }
                hasValidTargets = true
                
                if startSts == endSts || startSts == 0 || endSts == 0 {
                    total += targetRows * meaningfulStitches
                } else {
                    let diff = Double(endSts - startSts)
                    for r in 1...targetRows {
                        let progress = Double(r) / Double(targetRows)
                        let stsInRow = Int(round(Double(startSts) + diff * progress))
                        total += max(1, stsInRow)
                    }
                }
            }
        }
        
        return hasValidTargets && total > 0 ? total : nil
    }
    
    /// Totale dei ferri obiettivo in tutto il pattern, escludendo i contatori di maglie (ALTO-08)
    var targetTotalRows: Int? {
        let total = guideSteps.filter { !$0.isStitchCounter }.compactMap { $0.effectiveTargetCount }.reduce(0, +)
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
    
    /// Annulla tutti i progressi fatti nel progetto e lo riavvia da capo:
    /// azzera i contatori delle schede guida, i contatori manuali, le sessioni e il tempo lavorato,
    /// e riapre tutti i passaggi come non completati.
    @MainActor
    func resetAllProgress(modelContext: ModelContext? = nil) {
        completedAt = nil
        totalSecondsWorked = 0
        updatedAt = Date()
        
        // Azzera timer attivo se associato a questo progetto
        TimerManager.shared.cancelTimer(for: id)
        
        // Elimina le sessioni del timer registrate finora
        let context = modelContext ?? self.modelContext
        if let context = context {
            for session in timerSessions {
                context.delete(session)
            }
        }
        timerSessions.removeAll()
        
        // Azzera i progressi di ogni scheda della guida
        for step in guideSteps {
            step.currentStepCount = 0
            step.isCompleted = false
            step.completedAt = nil
            if !step.extraCounterLabels.isEmpty {
                step.extraCounterValues = Array(repeating: 0, count: step.extraCounterLabels.count)
            } else {
                step.extraCounterValues.removeAll()
            }
        }
        
        // Azzera tutti i contatori del progetto
        for counter in counters {
            counter.currentCount = 0
        }
        
        // Reset indice salvato in UserDefaults
        UserDefaults.standard.removeObject(forKey: "purl_lab_last_guide_step_\(id)")
        
        try? context?.save()
        
        // Aggiorna step attivo e sincronizza con Apple Watch
        let firstStep = guideSteps.sorted(by: { $0.orderIndex < $1.orderIndex }).first
        WatchConnectivityIOSManager.shared.setActiveStep(firstStep, for: self)
    }
}
