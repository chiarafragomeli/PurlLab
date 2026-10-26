import Foundation
import SwiftUI
import Combine

@MainActor
@Observable
final class TimerManager {
    static let shared = TimerManager()
    
    var isRunning: Bool = false
    var activeProjectId: UUID?
    var elapsedSecondsInCurrentSession: TimeInterval = 0
    
    private var timer: AnyCancellable?
    private var sessionStartDate: Date?
    private var lastInteractionDate: Date = Date()
    
    var autoPauseMinutes: Double = 15.0
    
    private init() {}
    
    func start(for projectId: UUID) {
        if isRunning && activeProjectId == projectId { return }
        if isRunning { pause() }
        
        activeProjectId = projectId
        isRunning = true
        sessionStartDate = Date()
        lastInteractionDate = Date()
        elapsedSecondsInCurrentSession = 0
        
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }
    
    func pause() -> TimeInterval {
        guard isRunning else { return 0 }
        isRunning = false
        timer?.cancel()
        timer = nil
        
        let sessionDuration = elapsedSecondsInCurrentSession
        elapsedSecondsInCurrentSession = 0
        sessionStartDate = nil
        return sessionDuration
    }
    
    func registerInteraction() {
        lastInteractionDate = Date()
    }
    
    private func tick() {
        guard let start = sessionStartDate else { return }
        elapsedSecondsInCurrentSession = Date().timeIntervalSince(start)
        
        // Auto-pause if inactive for > autoPauseMinutes
        if Date().timeIntervalSince(lastInteractionDate) > (autoPauseMinutes * 60) {
            _ = pause()
        }
    }
    
    func formatTime(_ totalSeconds: TimeInterval) -> String {
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60
        
        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, seconds)
        } else {
            return String(format: "%02dm %02ds", minutes, seconds)
        }
    }
}
