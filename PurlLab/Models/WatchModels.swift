import Foundation

/// Modello sintetico di un progetto da visualizzare e controllare su Apple Watch
struct WatchProjectSummary: Codable, Identifiable, Sendable {
    let id: String
    var title: String
    var designer: String
    var selectedSize: String
    var totalSecondsWorked: TimeInterval
    var isTimerRunning: Bool
    
    // Stato della guida operativa corrente
    var currentSectionTitle: String
    var currentStepTitle: String
    var currentStepIndex: Int
    var totalStepsCount: Int
    
    // Contatore principale
    var counterLabel: String
    var currentCount: Int
    var targetCount: Int?
    
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
    case incrementExtraCounter
    case decrementExtraCounter
    case startTimer
    case pauseTimer
    case selectProject
    case requestFullSync
}
