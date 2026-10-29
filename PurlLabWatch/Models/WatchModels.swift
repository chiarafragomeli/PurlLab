import Foundation

/// Modello sintetico di un progetto da visualizzare e controllare su Apple Watch
struct WatchProjectSummary: Codable, Identifiable, Sendable {
    let id: String
    var title: String
    var designer: String
    var selectedSize: String
    var totalSecondsWorked: TimeInterval
    var isTimerRunning: Bool
    
    // Scheda e Sezione Operativa Attualmente Lavorata
    var activeStepId: String?
    var currentSectionTitle: String
    var currentStepTitle: String
    var currentStepIndex: Int
    var totalStepsCount: Int
    var isStepCompleted: Bool
    
    // Contatore specifico della sezione
    var counterLabel: String
    var currentCount: Int
    var targetCount: Int?
    
    // Maglie attuali sul ferro per questa sezione
    var currentStitches: Int?
    var stitchesBefore: Int?
    var stitchesAfter: Int?
    
    // Navigazione tra schede
    var canGoPrevious: Bool
    var canGoNext: Bool
    
    // Statistiche globali di progetto (maglie e ferri totali)
    var totalStitchesWorked: Int
    var totalRowsWorked: Int
    
    // Eventuali contatori aggiuntivi sulla scheda
    var extraCounterLabels: [String]
    var extraCounterValues: [Int]
    
    var isTargetReached: Bool {
        if let target = targetCount, target > 0 {
            return currentCount >= target
        }
        return false
    }
    
    var displaySubtitle: String {
        let size = selectedSize.trimmingCharacters(in: .whitespaces)
        return size.isEmpty ? designer : (designer.isEmpty ? size : "\(size) · \(designer)")
    }
    
    /// Testo sintetico sulle maglie (es. "114 maglie" o "4 → 8 maglie", evitando la pill "0 → X")
    var stitchesDescription: String? {
        if let before = stitchesBefore, let after = stitchesAfter, before > 0, before != after {
            let diff = after - before
            let diffStr = diff > 0 ? "+\(diff)" : "\(diff)"
            return "\(before) → \(after) m (\(diffStr))"
        } else if let sts = currentStitches ?? stitchesAfter, sts > 0 {
            return "\(sts) maglie"
        }
        return nil
    }
}

/// Contenitore di sincronizzazione trasmesso via WCSession
struct WatchSyncState: Codable, Sendable {
    var projects: [WatchProjectSummary]
    var activeProjectId: String?
    var timestamp: Date
}

/// Tipi di comandi inviati da Apple Watch a iPhone
enum WatchCommandType: String, Codable {
    case incrementMainCounter
    case decrementMainCounter
    case setMainCounter
    case nextStep
    case previousStep
    case completeStep
    case selectStep
    case incrementExtraCounter
    case decrementExtraCounter
    case startTimer
    case pauseTimer
    case selectProject
    case requestFullSync
}
