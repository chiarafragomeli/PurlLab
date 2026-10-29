import SwiftUI
import SwiftData

enum DetailTab: String, CaseIterable {
    case guide = "Guida"
    case counters = "Contatori"
    case pdf = "PDF"
    
    var iconName: String {
        switch self {
        case .guide: return "book.pages"
        case .counters: return "number.circle"
        case .pdf: return "doc.text"
        }
    }
}

struct UnifiedProjectBottomBar: View {
    @Bindable var project: KnittingProject
    @Binding var selectedTab: DetailTab
    @State private var timerManager = TimerManager.shared
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        HStack(spacing: 8) {
            // Pillola Timer di Sessione
            Button {
                haptic.impactOccurred()
                if isProjectTimerActive {
                    let duration = timerManager.pause()
                    project.totalSecondsWorked += duration
                } else {
                    timerManager.start(for: project.id)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isProjectTimerActive ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(isProjectTimerActive ? .orange : .accentColor)
                    
                    Text(displayTimeString)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                    
                    if isProjectTimerActive {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .shadow(color: Color.green.opacity(0.8), radius: 3)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
            Spacer(minLength: 4)
            
            // Selettore Tab Guida / Contatori / PDF
            HStack(spacing: 2) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    let isSelected = (selectedTab == tab)
                    Button {
                        haptic.impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                            
                            if isSelected {
                                Text(tab.rawValue)
                                    .font(.system(size: 12, weight: .bold))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .padding(.horizontal, isSelected ? 12 : 9)
                        .padding(.vertical, 7)
                        .background(
                            isSelected ? Color.accentColor : Color.clear
                        )
                        .foregroundColor(isSelected ? .white : .secondary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color(.tertiarySystemFill))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
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
    var onDeleteProject: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: DetailTab = .guide
    @State private var targetPdfPage: Int = 1
    @State private var currentGuideStepIndex: Int = 0
    
    @State private var showingEditProject = false
    @State private var showingGaugeSheet = false
    @State private var showingAddStepSheet = false
    @State private var showingDeleteAlert = false
    @State private var stepToEdit: GuideStep? = nil
    @State private var editedTitle = ""
    @State private var editedDesigner = ""
    @State private var editedSize = ""
    
    private var activeGuideStep: GuideStep? {
        let sorted = project.guideSteps.sorted(by: { $0.orderIndex < $1.orderIndex })
        guard currentGuideStepIndex >= 0 && currentGuideStepIndex < sorted.count else { return nil }
        return sorted[currentGuideStepIndex]
    }
    
    var body: some View {
        Group {
            if project.isDeleted || project.modelContext == nil {
                Color.clear
            } else {
                VStack(spacing: 0) {
            // Tab Content
            TabView(selection: $selectedTab) {
                GuideView(
                    project: project,
                    currentStepIndex: $currentGuideStepIndex,
                    onSelectPdfPage: { page in
                        targetPdfPage = page
                        selectedTab = .pdf
                    },
                    onExitProject: {
                        dismiss()
                    }
                )
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
            
            // Barra di Controllo Unificata Inferiore (Timer + Selettore Schede)
            UnifiedProjectBottomBar(project: project, selectedTab: $selectedTab)
        }
        .navigationTitle(project.selectedSize.isEmpty ? project.title : "\(project.title) · \(project.selectedSize)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                        Text("Progetti")
                            .font(.body)
                    }
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showingGaugeSheet = true
                    } label: {
                        Image(systemName: project.isGaugeRecalculated ? "gauge.with.needle.fill" : "gauge.with.needle")
                            .font(.body)
                            .foregroundColor(project.isGaugeRecalculated ? .indigo : .accentColor)
                    }
                    
                    Menu {
                        if selectedTab == .guide, let active = activeGuideStep {
                            Button {
                                stepToEdit = active
                            } label: {
                                Label("Modifica Scheda Attuale", systemImage: "pencil")
                            }
                        }
                        
                        Button {
                            editedTitle = project.title
                            editedDesigner = project.designer
                            editedSize = project.selectedSize
                            showingEditProject = true
                        } label: {
                            Label("Modifica Info Progetto", systemImage: "info.circle")
                        }
                        
                        Button {
                            showingAddStepSheet = true
                        } label: {
                            Label("Aggiungi Scheda Guida", systemImage: "plus.rectangle.on.rectangle")
                        }
                        
                        Button {
                            showingGaugeSheet = true
                        } label: {
                            Label("Adatta al Campione (AI)...", systemImage: "gauge.with.needle")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Label("Elimina Progetto", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.body)
                    }
                }
            }
        }
        .sheet(item: $stepToEdit) { step in
            EditGuideStepSheet(step: step, onDelete: {
                if let idx = project.guideSteps.firstIndex(where: { $0.id == step.id }) {
                    project.guideSteps.remove(at: idx)
                    modelContext.delete(step)
                    try? modelContext.save()
                    WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
                }
            })
        }
        .sheet(isPresented: $showingAddStepSheet) {
            AddGuideStepSheet(project: project)
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
                    
                    Section {
                        Button(role: .destructive) {
                            showingEditProject = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                showingDeleteAlert = true
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Label("Elimina Progetto", systemImage: "trash")
                                Spacer()
                            }
                        }
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
            .presentationDetents([.medium, .large])
        }
        .alert("Elimina Progetto", isPresented: $showingDeleteAlert) {
            Button("Annulla", role: .cancel) { }
            Button("Elimina", role: .destructive) {
                if let onDelete = onDeleteProject {
                    onDelete()
                } else {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        modelContext.delete(project)
                        try? modelContext.save()
                        WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
                    }
                }
            }
        } message: {
            Text("Sei sicuro di voler eliminare \"\(project.title)\"? L'azione è irreversibile e cancellerà tutte le schede e i contatori associati.")
        }
        .onAppear {
            guard !project.isDeleted, project.modelContext != nil else { return }
            let sorted = project.guideSteps.sorted(by: { $0.orderIndex < $1.orderIndex })
            let savedIdx = UserDefaults.standard.object(forKey: "purl_lab_last_guide_step_\(project.id)") as? Int
            if let saved = savedIdx, saved >= 0 && saved < sorted.count {
                currentGuideStepIndex = saved
            } else if let active = project.activeWorkingStep(),
                      let idx = sorted.firstIndex(where: { $0.id == active.id }) {
                currentGuideStepIndex = idx
            }
            WatchConnectivityIOSManager.shared.setActiveProject(project)
        }
        .onDisappear {
            // Salva la sessione attiva se si esce dal progetto
            guard !project.isDeleted, project.modelContext != nil else { return }
            if TimerManager.shared.isRunning && TimerManager.shared.activeProjectId == project.id {
                let duration = TimerManager.shared.pause()
                project.totalSecondsWorked += duration
                try? modelContext.save()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard !project.isDeleted, project.modelContext != nil else { return }
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
    }
}
