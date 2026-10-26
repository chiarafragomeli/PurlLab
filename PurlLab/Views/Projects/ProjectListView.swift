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
    @AppStorage("didAutoLoadSampleV3") private var didAutoLoadSampleV3 = false
    
    var body: some View {
        NavigationStack {
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
                        ForEach(projects) { project in
                            NavigationLink(destination: ProjectDetailView(project: project)) {
                                ProjectRowView(project: project)
                            }
                        }
                        .onDelete(perform: deleteProjects)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("I Miei Progetti")
            .onAppear {
                if projects.isEmpty && !didAutoLoadSampleV3 {
                    didAutoLoadSampleV3 = true
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
                    let defaultCounter = RowCounter(title: "Ferri Principali")
                    defaultCounter.project = project
                    project.counters.append(defaultCounter)
                    
                    modelContext.insert(project)
                    newProjectTitle = ""
                    newProjectDesigner = ""
                }
            }
        }
    }
    
    private func deleteProjects(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(projects[index])
        }
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
        
        let c1 = RowCounter(title: "Ferri Principali")
        c1.project = project
        project.counters.append(c1)
        
        let c2 = RowCounter(title: "Aumenti Raglan (58 giri)", targetCount: 58)
        c2.project = project
        project.counters.append(c2)
        
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
            
            let counter = RowCounter(title: "Ferro")
            counter.project = project
            project.counters.append(counter)
            
            modelContext.insert(project)
        } catch {
            print("Errore importazione PDF: \(error.localizedDescription)")
        }
    }
}

struct ProjectRowView: View {
    let project: KnittingProject
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "circle.grid.cross.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.headline)
                    .lineLimit(1)
                
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
                    
                    if project.completedAt != nil {
                        Text("Completato")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                }
                .font(.subheadline)
                
                HStack(spacing: 12) {
                    Label("\(project.guideSteps.count) schede", systemImage: "rectangle.stack")
                    Label("\(project.counters.count) contatori", systemImage: "number.circle")
                    if project.totalSecondsWorked > 0 {
                        Label(TimerManager.shared.formatTime(project.totalSecondsWorked), systemImage: "clock")
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}
