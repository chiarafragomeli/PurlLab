import SwiftUI
import SwiftData
import os

private let storageLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.chiara.PurlLab", category: "storage")

// MARK: - Versioned Schema & Migration Plan (CRIT-04)

enum PurlLabSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [
            KnittingProject.self,
            RowCounter.self,
            GuideStep.self,
            TimerSession.self
        ]
    }
    
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
        @Attribute(.externalStorage) var originalGuideJSON: Data? = nil
        
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
    
    @Model
    final class GuideStep {
        var id: UUID
        var sectionTitle: String
        var title: String = ""
        var stepType: String = "single_action"
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
        var counterKind: String? = nil
        var currentStepCount: Int = 0
        var targetStepCount: Int?
        var extraCounterLabels: [String] = []
        var extraCounterValues: [Int] = []
        var completedAt: Date?
        
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
            counterKind: String? = nil,
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
            self.counterKind = counterKind
            self.currentStepCount = currentStepCount
            self.targetStepCount = targetStepCount
        }
    }
    
    @Model
    final class RowCounter {
        var id: UUID
        var title: String
        var currentCount: Int
        var targetCount: Int?
        var stepIncrement: Int
        var resetOnTarget: Bool
        var orderIndex: Int
        
        var project: KnittingProject?
        
        init(
            title: String,
            currentCount: Int = 0,
            targetCount: Int? = nil,
            stepIncrement: Int = 1,
            resetOnTarget: Bool = false,
            orderIndex: Int = 0
        ) {
            self.id = UUID()
            self.title = title
            self.currentCount = currentCount
            self.targetCount = targetCount
            self.stepIncrement = stepIncrement
            self.resetOnTarget = resetOnTarget
            self.orderIndex = orderIndex
        }
    }
    
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
}

typealias KnittingProject = PurlLabSchemaV1.KnittingProject
typealias GuideStep = PurlLabSchemaV1.GuideStep
typealias RowCounter = PurlLabSchemaV1.RowCounter
typealias TimerSession = PurlLabSchemaV1.TimerSession

enum PurlLabMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PurlLabSchemaV1.self]
    }
    
    static var stages: [MigrationStage] {
        []
    }
}

@main
struct PurlLabApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    static func createPersistentContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: PurlLabSchemaV1.self)
        let modelConfiguration = ModelConfiguration("PurlLabV4", schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, migrationPlan: PurlLabMigrationPlan.self, configurations: [modelConfiguration])
    }
    
    static func createTemporaryInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: PurlLabSchemaV1.self)
        let inMemoryConfig = ModelConfiguration("PurlLabV4_InMemory", schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [inMemoryConfig])
    }
    
    static let initialStorageResult: Result<ModelContainer, Error> = {
        do {
            let container = try createPersistentContainer()
            storageLogger.info("ModelContainer persistente inizializzato con successo")
            return .success(container)
        } catch {
            storageLogger.error("Impossibile inizializzare ModelContainer persistente: \(error.localizedDescription)")
            return .failure(error)
        }
    }()
    
    static var sharedModelContainer: ModelContainer? {
        try? initialStorageResult.get()
    }
    
    @State private var storageResult: Result<ModelContainer, Error> = PurlLabApp.initialStorageResult
    @State private var showingTemporaryStoreAlert: Bool = false
    
    init() {
        if let container = PurlLabApp.sharedModelContainer {
            let context = container.mainContext
            WatchConnectivityIOSManager.shared.configure(with: context)
            TimerManager.shared.configure(with: context)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            switch storageResult {
            case .success(let container):
                ProjectListView()
                    .modelContainer(container)
                    .onAppear {
                        UIApplication.shared.isIdleTimerDisabled = true
                    }
                
            case .failure(let error):
                StorageErrorBlockingView(
                    error: error,
                    onRetry: {
                        do {
                            let container = try Self.createPersistentContainer()
                            storageLogger.info("Riprova: ModelContainer persistente inizializzato con successo")
                            let context = container.mainContext
                            WatchConnectivityIOSManager.shared.configure(with: context)
                            TimerManager.shared.configure(with: context)
                            storageResult = .success(container)
                        } catch {
                            storageLogger.error("Riprova fallita: \(error.localizedDescription)")
                            storageResult = .failure(error)
                        }
                    },
                    onRequestTemporaryStore: {
                        showingTemporaryStoreAlert = true
                    }
                )
                .alert("Usa archivio temporaneo?", isPresented: $showingTemporaryStoreAlert) {
                    Button("Annulla", role: .cancel) { }
                    Button("Usa archivio temporaneo", role: .destructive) {
                        do {
                            let inMemoryContainer = try Self.createTemporaryInMemoryContainer()
                            storageLogger.warning("Avvio con archivio temporaneo in memoria confermato dall'utente")
                            let context = inMemoryContainer.mainContext
                            WatchConnectivityIOSManager.shared.configure(with: context)
                            TimerManager.shared.configure(with: context)
                            storageResult = .success(inMemoryContainer)
                        } catch {
                            storageLogger.error("Inizializzazione archivio temporaneo fallita: \(error.localizedDescription)")
                            storageResult = .failure(error)
                        }
                    }
                } message: {
                    Text("I dati creati in questa sessione NON verranno salvati su disco e andranno persi alla chiusura dell'applicazione. Nessun dato esistente verrà toccato o cancellato.")
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                UIApplication.shared.isIdleTimerDisabled = true
                WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
            } else {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }
}

// MARK: - Schermata Bloccante Errore Archivio Dati
struct StorageErrorBlockingView: View {
    let error: Error
    let onRetry: () -> Void
    let onRequestTemporaryStore: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.orange)
                
                Text("Errore Archivio Dati")
                    .font(.title2.bold())
                
                Text("Non è stato possibile aprire l'archivio locale dei progetti. I tuoi dati su disco non sono stati modificati né cancellati.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 24)
                
                ScrollView {
                    Text(error.localizedDescription)
                        .font(.caption.monospaced())
                        .foregroundColor(.primary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .frame(maxHeight: 120)
                .padding(.horizontal, 24)
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button(action: onRetry) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Riprova")
                        }
                        .bold()
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    
                    Button(action: onRequestTemporaryStore) {
                        Text("Usa archivio temporaneo (i dati non verranno salvati)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationBarHidden(true)
        }
    }
}
