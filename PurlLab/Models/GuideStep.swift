import Foundation
import SwiftData

// MARK: - GuideStep Metodi e Proprietà Calcolate
extension GuideStep {
    var isDetachedOrDeleted: Bool {
        isDeleted || modelContext == nil
    }
    
    var safeSubSteps: [String] {
        guard !isDetachedOrDeleted else { return [] }
        return subSteps
    }
    
    var safeRepeatVariations: [String] {
        guard !isDetachedOrDeleted else { return [] }
        return repeatVariations
    }
    
    var safeExtraCounterLabels: [String] {
        guard !isDetachedOrDeleted else { return [] }
        return extraCounterLabels
    }
    
    var safeExtraCounterValues: [Int] {
        guard !isDetachedOrDeleted else { return [] }
        return extraCounterValues
    }
    
    /// Determina se questo contatore tiene traccia di maglie invece che di ferri/giri
    var isStitchCounter: Bool {
        if let kind = counterKind?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !kind.isEmpty {
            return kind == "stitch" || kind == "maglia" || kind == "maglie" || kind == "punto" || kind == "punti"
        }
        let label = (counterLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return label.contains("magli") || label.contains("punti") || label.contains("stitch")
    }
    
    /// Calcola l'obiettivo effettivo (se pattern ripetuto moltiplica ferri × ripetizioni)
    var effectiveTargetCount: Int? {
        if let rows = rowsPerRepeat, let reps = totalRepeats, rows > 0, reps > 0 {
            return rows * reps
        }
        return targetStepCount
    }
}
