import SwiftUI
import SwiftData

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
    
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: PurlLabSchemaV1.self)
        let modelConfiguration = ModelConfiguration("PurlLabV4", schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, migrationPlan: PurlLabMigrationPlan.self, configurations: [modelConfiguration])
        } catch {
            print("⚠️ [PurlLabApp] Impossibile inizializzare ModelContainer persistente (\(error)). Tentativo di ripristino in memoria...")
            let inMemoryConfig = ModelConfiguration("PurlLabV4_InMemory", schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [inMemoryConfig])
            } catch {
                fatalError("Fallback in memoria fallito: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .onAppear {
                    let context = Self.sharedModelContainer.mainContext
                    WatchConnectivityIOSManager.shared.configure(with: context)
                    TimerManager.shared.configure(with: context)
                }
        }
        .modelContainer(Self.sharedModelContainer)
    }
}

