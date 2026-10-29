import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ProjectListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \KnittingProject.updatedAt, order: .reverse) private var projects: [KnittingProject]
    
    @State private var showingFilePicker = false
    @State private var showingSettings = false
    @State private var showingManualNewProject = false
    @State private var newProjectTitle = ""
    @State private var newProjectDesigner = ""
    @State private var projectToRename: KnittingProject?
    @State private var renameTitle = ""
    @State private var showingRenameAlert = false
    @State private var projectToDelete: KnittingProject?
    @State private var showingDeleteAlert = false
    @State private var navigationPath: [UUID] = []
    @AppStorage("didAutoLoadSampleV4") private var didAutoLoadSampleV4 = false
    
    private var activeProjectToResume: KnittingProject? {
        projects.first(where: { $0.completedAt == nil }) ?? projects.first
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if projects.isEmpty {
                    ContentUnavailableView {
                        Label("Nessun Progetto", systemImage: "sparkles.rectangle.stack")
                    } description: {
                        Text("Importa un pattern PDF da File per iniziare a lavorare con la guida AI e i contatori.")
                    } actions: {
                        VStack(spacing: 12) {
                            Button {
                                loadSamplePattern()
                            } label: {
                                Label("Carica No Frills Sweater (Test)", systemImage: "sparkles")
                                    .bold()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button {
                                showingFilePicker = true
                            } label: {
                                Label("Importa Altro Pattern da File", systemImage: "doc.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.horizontal, 32)
                    }
                } else {
                    List {
                        if let resumeProject = activeProjectToResume {
                            Section {
                                ResumeProjectHeroCard(project: resumeProject) {
                                    navigationPath = [resumeProject.id]
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        projectToDelete = resumeProject
                                        showingDeleteAlert = true
                                    } label: {
                                        Label("Elimina", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        projectToRename = resumeProject
                                        renameTitle = resumeProject.title
                                        showingRenameAlert = true
                                    } label: {
                                        Label("Rinomina", systemImage: "pencil")
                                    }
                                    .tint(.indigo)
                                }
                                .contextMenu {
                                    Button {
                                        projectToRename = resumeProject
                                        renameTitle = resumeProject.title
                                        showingRenameAlert = true
                                    } label: {
                                        Label("Rinomina Progetto", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        projectToDelete = resumeProject
                                        showingDeleteAlert = true
                                    } label: {
                                        Label("Elimina Progetto", systemImage: "trash")
                                    }
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                        
                        Section {
                            HStack(spacing: 12) {
                                Button {
                                    showingFilePicker = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "doc.badge.plus")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(.accentColor)
                                        Text("Importa PDF")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(.primary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                
                                Button {
                                    showingManualNewProject = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundColor(.indigo)
                                        Text("Nuovo Progetto")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(.primary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        
                        let otherProjects = projects.filter { $0.id != activeProjectToResume?.id }
                        if !otherProjects.isEmpty {
                            Section("Altri Progetti (\(otherProjects.count))") {
                                ForEach(otherProjects) { project in
                                    NavigationLink(value: project.id) {
                                        ProjectRowView(project: project)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            projectToDelete = project
                                            showingDeleteAlert = true
                                        } label: {
                                            Label("Elimina", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            projectToRename = project
                                            renameTitle = project.title
                                            showingRenameAlert = true
                                        } label: {
                                            Label("Rinomina", systemImage: "pencil")
                                        }
                                        .tint(.indigo)
                                    }
                                    .contextMenu {
                                        Button {
                                            projectToRename = project
                                            renameTitle = project.title
                                            showingRenameAlert = true
                                        } label: {
                                            Label("Rinomina Progetto", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            projectToDelete = project
                                            showingDeleteAlert = true
                                        } label: {
                                            Label("Elimina Progetto", systemImage: "trash")
                                        }
                                    }
                                }
                                .onDelete(perform: deleteProjects)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("I Miei Progetti")
            .navigationDestination(for: UUID.self) { projectId in
                if let project = projects.first(where: { $0.id == projectId }) {
                    ProjectDetailView(project: project)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .watchDidSelectProject)) { notification in
                if let projectId = notification.userInfo?["projectId"] as? UUID {
                    navigationPath = [projectId]
                }
            }
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-openFirstProject") {
                    if let first = projects.first {
                        navigationPath = [first.id]
                    }
                }
                
                // Rimuovi eventuali vecchi contatori del raglan dalla scheda contatori
                for project in projects {
                    let raglanCounters = project.counters.filter { $0.title.localizedCaseInsensitiveContains("raglan") }
                    for rc in raglanCounters {
                        if let idx = project.counters.firstIndex(where: { $0.id == rc.id }) {
                            project.counters.remove(at: idx)
                            modelContext.delete(rc)
                        }
                    }
                    
                    // Aggiorna vecchi nomi nel nuovo nome "Contatore Globale"
                    for counter in project.counters {
                        if counter.title == "Ferri Principali" || counter.title == "Ferro" || counter.title == "Ferri" {
                            counter.title = "Contatore Globale"
                        }
                    }
                }
                
                if projects.isEmpty && !didAutoLoadSampleV4 {
                    didAutoLoadSampleV4 = true
                    loadSamplePattern()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            loadSamplePattern()
                        } label: {
                            Label("Carica No Frills Sweater (Test)", systemImage: "sparkles")
                        }
                        
                        Button {
                            showingFilePicker = true
                        } label: {
                            Label("Importa PDF Pattern da File", systemImage: "doc.badge.plus")
                        }
                        
                        Button {
                            showingManualNewProject = true
                        } label: {
                            Label("Nuovo Progetto Vuoto", systemImage: "plus.rectangle")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                handlePdfImport(result)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .alert("Nuovo Progetto", isPresented: $showingManualNewProject) {
                TextField("Nome Progetto", text: $newProjectTitle)
                TextField("Designer (opzionale)", text: $newProjectDesigner)
                Button("Annulla", role: .cancel) {
                    newProjectTitle = ""
                    newProjectDesigner = ""
                }
                Button("Crea") {
                    let project = KnittingProject(
                        title: newProjectTitle.isEmpty ? "Nuovo Lavoro" : newProjectTitle,
                        designer: newProjectDesigner
                    )
                    let defaultCounter = RowCounter(title: "Contatore Globale")
                    defaultCounter.project = project
                    project.counters.append(defaultCounter)
                    
                    modelContext.insert(project)
                    newProjectTitle = ""
                    newProjectDesigner = ""
                }
            }
            .alert("Rinomina Progetto", isPresented: $showingRenameAlert) {
                TextField("Nome del Progetto", text: $renameTitle)
                Button("Annulla", role: .cancel) {
                    projectToRename = nil
                }
                Button("Salva") {
                    if let p = projectToRename {
                        let clean = renameTitle.trimmingCharacters(in: .whitespaces)
                        if !clean.isEmpty {
                            p.title = clean
                            p.updatedAt = Date()
                        }
                    }
                    projectToRename = nil
                }
            }
            .alert("Elimina Progetto", isPresented: $showingDeleteAlert) {
                Button("Annulla", role: .cancel) {
                    projectToDelete = nil
                }
                Button("Elimina", role: .destructive) {
                    if let p = projectToDelete {
                        deleteProject(p)
                    }
                    projectToDelete = nil
                }
            } message: {
                Text("Sei sicuro di voler eliminare \"\(projectToDelete?.title ?? "questo progetto")\"? L'azione è irreversibile e cancellerà tutte le schede e i contatori associati.")
            }
        }
    }
    
    private func deleteProject(_ project: KnittingProject) {
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            modelContext.delete(projects[idx])
            try? modelContext.save()
            WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
        }
    }
    
    private func deleteProjects(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(projects[index])
        }
        try? modelContext.save()
        WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
    }
    
    private func loadSamplePattern() {
        guard let sampleUrl = Bundle.main.url(forResource: "NoFrillsSweater", withExtension: "pdf"),
              let pdfData = try? Data(contentsOf: sampleUrl) else {
            print("PDF di test non trovato nel bundle.")
            return
        }
        
        let project = KnittingProject(
            title: "No Frills Sweater",
            designer: "PetiteKnit",
            selectedSize: "M",
            pdfData: pdfData
        )
        
        let c1 = RowCounter(title: "Contatore Globale")
        c1.project = project
        project.counters.append(c1)
        
        if let guideUrl = Bundle.main.url(forResource: "NoFrillsGuide_M", withExtension: "json"),
           let guideData = try? Data(contentsOf: guideUrl),
           let guide = try? JSONDecoder().decode(GeneratedGuideResponse.self, from: guideData) {
            var stepOrder = 0
            for section in guide.sections {
                for stepData in section.steps {
                    let step = GuideStep(
                        sectionTitle: GeminiService.cleanSectionName(section.name),
                        title: stepData.title ?? "",
                        stepType: stepData.stepType ?? "single_action",
                        instructionText: stepData.instruction,
                        subSteps: stepData.subSteps ?? [],
                        repeatVariations: stepData.repeatVariations ?? [],
                        rowsPerRepeat: stepData.rowsPerRepeat,
                        totalRepeats: stepData.totalRepeats,
                        stitchCountBefore: stepData.stitchCountBefore,
                        stitchCountAfter: stepData.stitchCountAfter,
                        targetMeasureCm: stepData.targetMeasureCm,
                        sourcePage: stepData.sourcePage,
                        sourceQuote: stepData.sourceQuote,
                        orderIndex: stepOrder,
                        hasCounter: stepData.hasCounter ?? (stepData.targetStepCount != nil && stepData.targetStepCount! > 0),
                        counterLabel: stepData.counterLabel,
                        targetStepCount: stepData.targetStepCount
                    )
                    step.project = project
                    project.guideSteps.append(step)
                    stepOrder += 1
                }
            }
        }
        
        modelContext.insert(project)
    }
    
    private func handlePdfImport(_ result: Result<[URL], Error>) {
        do {
            guard let selectedUrl = try result.get().first else { return }
            
            let canAccess = selectedUrl.startAccessingSecurityScopedResource()
            defer {
                if canAccess { selectedUrl.stopAccessingSecurityScopedResource() }
            }
            
            let pdfData = try Data(contentsOf: selectedUrl)
            let filename = selectedUrl.deletingPathExtension().lastPathComponent
            
            let project = KnittingProject(
                title: filename.replacingOccurrences(of: "_", with: " ").capitalized,
                pdfData: pdfData
            )
            
            let counter = RowCounter(title: "Contatore Globale")
            counter.project = project
            project.counters.append(counter)
            
            modelContext.insert(project)
        } catch {
            print("Errore importazione PDF: \(error.localizedDescription)")
        }
    }
}

// MARK: - Hero Card per Riprendere il Progetto Attivo
struct ResumeProjectHeroCard: View {
    let project: KnittingProject
    let onResume: () -> Void
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    
    private var activeStep: GuideStep? {
        project.activeWorkingStep()
    }
    
    private var progressPercentage: Double {
        let total = project.guideSteps.count
        guard total > 0 else { return 0 }
        let completed = project.guideSteps.filter { $0.isCompleted }.count
        return Double(completed) / Double(total)
    }
    

    var body: some View {
        Button {
            haptic.impactOccurred()
            onResume()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                // Header riga: Stato e tempo
                HStack(alignment: .center) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 7, height: 7)
                        Text("In Lavorazione")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.accentColor)
                    }
                    
                    Spacer()
                    
                    if project.totalSecondsWorked > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text(TimerManager.shared.formatTime(project.totalSecondsWorked))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                    }
                }
                
                // Titolo e dettagli progetto
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.title)
                            .font(.title3.bold())
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 6) {
                            if !project.designer.isEmpty {
                                Text(project.designer)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            if !project.selectedSize.isEmpty {
                                Text("• Taglia \(project.selectedSize)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Callout discreto Riprendi
                    HStack(spacing: 4) {
                        Text("Riprendi")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundColor(.accentColor)
                }
                
                // Sezione / Scheda attiva & avanzamento
                if let step = activeStep {
                    VStack(alignment: .leading, spacing: 8) {
                        Divider()
                            .opacity(0.6)
                        
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.sectionTitle)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                if !step.title.isEmpty {
                                    Text(step.title)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                }
                            }
                            
                            Spacer()
                            
                            if !project.guideSteps.isEmpty {
                                Text("Scheda \(step.orderIndex + 1)/\(project.guideSteps.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if !project.guideSteps.isEmpty {
                            ProgressView(value: progressPercentage)
                                .tint(.accentColor)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct ProjectRowView: View {
    let project: KnittingProject
    
    private var progressPercentage: Double {
        let total = project.guideSteps.count
        guard total > 0 else { return 0 }
        let completed = project.guideSteps.filter { $0.isCompleted }.count
        return Double(completed) / Double(total)
    }
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(project.completedAt != nil ? Color.green.opacity(0.12) : Color.accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                
                Image(systemName: project.completedAt != nil ? "checkmark.circle.fill" : "circle.grid.cross.fill")
                    .font(.title3)
                    .foregroundColor(project.completedAt != nil ? .green : .accentColor)
            }
            
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(project.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if project.completedAt != nil {
                        Text("Completato")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    } else if !project.guideSteps.isEmpty {
                        Text(String(format: "%.0f%%", progressPercentage * 100))
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundColor(.accentColor)
                    }
                }
                
                HStack(spacing: 6) {
                    if !project.designer.isEmpty {
                        Text(project.designer)
                            .foregroundColor(.secondary)
                    }
                    
                    if !project.selectedSize.isEmpty {
                        Text("• Taglia \(project.selectedSize)")
                            .foregroundColor(.accentColor)
                            .bold()
                    }
                }
                .font(.subheadline)
                
                if !project.guideSteps.isEmpty && project.completedAt == nil {
                    ProgressView(value: progressPercentage)
                        .tint(.accentColor)
                        .padding(.vertical, 2)
                }
                
                HStack(spacing: 12) {
                    Label("\(project.guideSteps.count) schede", systemImage: "rectangle.stack")
                    Label("\(project.counters.count) contatori", systemImage: "number.circle")
                    if project.totalSecondsWorked > 0 {
                        Label(TimerManager.shared.formatTime(project.totalSecondsWorked), systemImage: "clock")
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
