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
}

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
