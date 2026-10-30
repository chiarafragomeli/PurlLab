import Foundation

// MARK: - Clock Abstraction (iniettabile per test deterministici e immediati)
public protocol AppClock: Sendable {
    var now: Date { get }
    func sleep(nanoseconds: UInt64) async throws
}

public struct SystemClock: AppClock {
    public init() {}
    public var now: Date { Date() }
    public func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

// MARK: - Watch Message Payload
struct WatchMessagePayload: @unchecked Sendable {
    let message: [String: Any]
    init(message: [String: Any]) {
        self.message = message
    }
}

// MARK: - Watch Transport Protocol (per testing e disaccoppiamento)
protocol WatchTransport: AnyObject, Sendable {
    var isReachable: Bool { get }
    func sendMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?, errorHandler: ((Error) -> Void)?)
    func transferUserInfoFallback(_ userInfo: [String: Any])
}

// MARK: - Watch Command Coordinator
/// Coordinatore puro (senza dipendenze da WatchKit o WCSession) della logica di invio comandi,
/// tracking comandi in volo, deduplicazione, timeout di 8s con fallback e crown debounce.
@MainActor
final class WatchCommandCoordinator {
    private(set) var inFlightCommandsCount: Int = 0
    var transport: (any WatchTransport)?
    var clock: any AppClock = SystemClock()
    var inFlightCommandTimeoutNanoseconds: UInt64 = 8_000_000_000
    
    private var inFlightTimeoutTasks: [String: Task<Void, Never>] = [:]
    private var activeInFlightCommandIds = Set<String>()
    private var lastCommandDateByProjectId: [String: Date] = [:]
    
    var onFullSyncNeeded: (@MainActor () -> Void)?
    var onSyncDataReceived: (@MainActor (Data) -> Void)?
    
    init(transport: (any WatchTransport)? = nil, clock: any AppClock = SystemClock()) {
        self.transport = transport
        self.clock = clock
    }
    
    func beginCrownDebounce() {
        inFlightCommandsCount += 1
    }
    
    func endCrownDebounce() {
        inFlightCommandsCount = max(0, inFlightCommandsCount - 1)
    }
    
    func completeInFlightCommand(commandId: String) {
        guard activeInFlightCommandIds.remove(commandId) != nil else { return }
        if let task = inFlightTimeoutTasks.removeValue(forKey: commandId) {
            task.cancel()
        }
        inFlightCommandsCount = max(0, inFlightCommandsCount - 1)
    }
    
    func resetForTesting() {
        for (_, task) in inFlightTimeoutTasks {
            task.cancel()
        }
        inFlightTimeoutTasks.removeAll()
        activeInFlightCommandIds.removeAll()
        lastCommandDateByProjectId.removeAll()
        inFlightCommandsCount = 0
        inFlightCommandTimeoutNanoseconds = 8_000_000_000
        clock = SystemClock()
    }
    
    func sendCommand(
        _ command: WatchCommandType,
        projectId: String,
        data: [String: Any] = [:]
    ) {
        guard let transport = self.transport else { return }
        let commandId = UUID().uuidString
        let commandDate = clock.now
        lastCommandDateByProjectId[projectId] = commandDate
        
        var message: [String: Any] = [
            "commandId": commandId,
            "command": command.rawValue,
            "projectId": projectId,
            "timestamp": commandDate.timeIntervalSince1970
        ]
        for (k, v) in data { message[k] = v }
        
        inFlightCommandsCount += 1
        activeInFlightCommandIds.insert(commandId)
        
        let payload = WatchMessagePayload(message: message)
        if transport.isReachable {
            let timeoutTask = Task { @MainActor [weak self] in
                try? await (self?.clock ?? SystemClock()).sleep(nanoseconds: self?.inFlightCommandTimeoutNanoseconds ?? 8_000_000_000)
                guard !Task.isCancelled, let self = self else { return }
                if self.activeInFlightCommandIds.remove(commandId) != nil {
                    self.inFlightTimeoutTasks.removeValue(forKey: commandId)
                    self.inFlightCommandsCount = max(0, self.inFlightCommandsCount - 1)
                    // Fallback transferUserInfo allo scadere del timeout (NON chiama requestFullSync subito)
                    transport.transferUserInfoFallback(message)
                }
            }
            inFlightTimeoutTasks[commandId] = timeoutTask
            Self.sendSessionMessageReachable(transport, payload: payload, coordinator: self)
        } else {
            activeInFlightCommandIds.remove(commandId)
            inFlightCommandsCount = max(0, inFlightCommandsCount - 1)
            transport.transferUserInfoFallback(message)
        }
    }
    
    /// Verifica se il contatore locale deve rimanere protetto contro sovrascritture da stati non ancora allineati di iPhone.
    /// Il contatore locale resta protetto finché non arriva uno stato dell'iPhone con timestamp successivo all'ultimo comando.
    func shouldProtectLocalCounter(projectId: String, incomingTimestamp: Date) -> Bool {
        if inFlightCommandsCount > 0 { return true }
        if let lastCommandDate = lastCommandDateByProjectId[projectId] {
            return incomingTimestamp <= lastCommandDate
        }
        return false
    }
    
    /// Rilascia la protezione se lo stato dell'iPhone ha un timestamp successivo all'ultimo comando inviato
    func clearProtectionIfSubsequent(projectId: String, incomingTimestamp: Date) {
        if let lastCommandDate = lastCommandDateByProjectId[projectId], incomingTimestamp > lastCommandDate {
            lastCommandDateByProjectId.removeValue(forKey: projectId)
        }
    }
    
    /// Unisce lo stato di sincronizzazione ricevuto da iPhone preservando i contatori locali se protetti
    func mergeSyncState(
        _ state: WatchSyncState,
        into localProjects: inout [WatchProjectSummary]
    ) {
        var updated = state.projects
        for (idx, proj) in updated.enumerated() {
            if shouldProtectLocalCounter(projectId: proj.id, incomingTimestamp: state.timestamp),
               let local = localProjects.first(where: { $0.id == proj.id }) {
                updated[idx].currentCount = local.currentCount
                updated[idx].totalRowsWorked = local.totalRowsWorked
                updated[idx].totalStitchesWorked = local.totalStitchesWorked
            } else {
                clearProtectionIfSubsequent(projectId: proj.id, incomingTimestamp: state.timestamp)
            }
        }
        localProjects = updated
    }
    
    private nonisolated static func sendSessionMessageReachable(
        _ transport: any WatchTransport,
        payload: WatchMessagePayload,
        coordinator: WatchCommandCoordinator?
    ) {
        transport.sendMessage(payload.message, replyHandler: { reply in
            let syncData = reply["syncData"] as? Data
            let error = reply["error"] as? String
            let cmdId = payload.message["commandId"] as? String
            Task { @MainActor in
                guard let coordinator = coordinator else { return }
                if let cmdId = cmdId {
                    coordinator.completeInFlightCommand(commandId: cmdId)
                } else {
                    coordinator.inFlightCommandsCount = max(0, coordinator.inFlightCommandsCount - 1)
                }
                
                if let _ = error {
                    // iPhone ha restituito errore (es. notReady): fallback in background per non perdere il comando
                    transport.transferUserInfoFallback(payload.message)
                } else if let syncData = syncData {
                    coordinator.onSyncDataReceived?(syncData)
                }
            }
        }, errorHandler: { _ in
            let cmdId = payload.message["commandId"] as? String
            Task { @MainActor in
                guard let coordinator = coordinator else { return }
                if let cmdId = cmdId {
                    coordinator.completeInFlightCommand(commandId: cmdId)
                } else {
                    coordinator.inFlightCommandsCount = max(0, coordinator.inFlightCommandsCount - 1)
                }
            }
            transport.transferUserInfoFallback(payload.message)
        })
    }
}

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
