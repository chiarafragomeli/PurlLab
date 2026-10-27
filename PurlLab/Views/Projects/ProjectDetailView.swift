import SwiftUI
import SwiftData

struct ProjectTimerBar: View {
    @Bindable var project: KnittingProject
    @State private var timerManager = TimerManager.shared
    
    var body: some View {
        HStack(spacing: 16) {
            // Play/Pause button
            Button {
                if timerManager.isRunning && timerManager.activeProjectId == project.id {
                    let duration = timerManager.pause()
                    project.totalSecondsWorked += duration
                } else {
                    timerManager.start(for: project.id)
                }
            } label: {
                Image(systemName: isProjectTimerActive ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 38))
                    .foregroundColor(isProjectTimerActive ? .orange : .accentColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(isProjectTimerActive ? "Sessione in corso" : "Tempo Totale")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Text(displayTimeString)
                    .font(.system(.title3, design: .monospaced, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            if isProjectTimerActive {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .shadow(color: Color.green.opacity(0.8), radius: 3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        .padding(.horizontal)
    }
    
    private var isProjectTimerActive: Bool {
        timerManager.isRunning && timerManager.activeProjectId == project.id
    }
    
    private var displayTimeString: String {
        let total = project.totalSecondsWorked + (isProjectTimerActive ? timerManager.elapsedSecondsInCurrentSession : 0)
        return timerManager.formatTime(total)
    }
}

struct ProjectDetailView: View {
    @Bindable var project: KnittingProject
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: DetailTab = .guide
    @State private var targetPdfPage: Int = 1
    
    @State private var showingEditProject = false
    @State private var showingGaugeSheet = false
    @State private var editedTitle = ""
    @State private var editedDesigner = ""
    @State private var editedSize = ""
    
    enum DetailTab: String, CaseIterable {
        case guide = "Guida"
        case counters = "Contatori"
        case pdf = "PDF"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Content
            TabView(selection: $selectedTab) {
                GuideView(project: project, onSelectPdfPage: { page in
                    targetPdfPage = page
                    selectedTab = .pdf
                }, onExitProject: {
                    dismiss()
                })
                .tag(DetailTab.guide)
                
                CountersView(project: project)
                    .tag(DetailTab.counters)
                
                if let pdfData = project.pdfData {
                    PatternPDFView(pdfData: pdfData)
                        .tag(DetailTab.pdf)
                } else {
                    ContentUnavailableView(
                        "Nessun PDF",
                        systemImage: "doc.text",
                        description: Text("Nessun file PDF caricato per questo progetto.")
                    )
                    .tag(DetailTab.pdf)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
            // Bottom Timer Bar
            ProjectTimerBar(project: project)
                .padding(.bottom, 8)
            
            // Custom Segmented Picker
            Picker("Sezione", selection: $selectedTab) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
        .navigationTitle(project.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showingGaugeSheet = true
                    } label: {
                        Image(systemName: project.isGaugeRecalculated ? "gauge.with.needle.fill" : "gauge.with.needle")
                            .font(.body)
                            .foregroundColor(project.isGaugeRecalculated ? .indigo : .accentColor)
                    }
                    
                    Button {
                        editedTitle = project.title
                        editedDesigner = project.designer
                        editedSize = project.selectedSize
                        showingEditProject = true
                    } label: {
                        Image(systemName: "pencil.circle")
                            .font(.body)
                    }
                }
            }
        }
        .sheet(isPresented: $showingGaugeSheet) {
            GaugeRecalculationView(project: project)
        }
        .sheet(isPresented: $showingEditProject) {
            NavigationStack {
                Form {
                    Section("Nome e Dettagli") {
                        TextField("Nome del Progetto", text: $editedTitle)
                        TextField("Designer (opzionale)", text: $editedDesigner)
                        TextField("Taglia (es. M, S, L...)", text: $editedSize)
                    }
                }
                .navigationTitle("Modifica Progetto")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annulla") { showingEditProject = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Salva") {
                            let clean = editedTitle.trimmingCharacters(in: .whitespaces)
                            if !clean.isEmpty {
                                project.title = clean
                            }
                            project.designer = editedDesigner.trimmingCharacters(in: .whitespaces)
                            project.selectedSize = editedSize.trimmingCharacters(in: .whitespaces)
                            project.updatedAt = Date()
                            showingEditProject = false
                        }
                        .bold()
                        .disabled(editedTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onDisappear {
            // Salva la sessione attiva se si esce dal progetto
            if TimerManager.shared.isRunning && TimerManager.shared.activeProjectId == project.id {
                let duration = TimerManager.shared.pause()
                project.totalSecondsWorked += duration
                try? modelContext.save()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Se l'app va in background o lo schermo viene bloccato, memorizza subito
            // i secondi lavorati per prevenire perdite dati in caso di sospensione o chiusura da iOS
            if newPhase == .background || newPhase == .inactive {
                if TimerManager.shared.isRunning && TimerManager.shared.activeProjectId == project.id {
                    let chunk = TimerManager.shared.flushElapsedToTotal()
                    if chunk > 0 {
                        project.totalSecondsWorked += chunk
                        project.updatedAt = Date()
                        try? modelContext.save()
                    }
                }
            }
        }
    }
}
