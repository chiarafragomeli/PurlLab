import SwiftUI
import SwiftData

enum GuideDisplayMode: String, CaseIterable {
    case card = "Card Singola"
    case list = "Elenco Sezioni"
}

struct GuideView: View {
    @Bindable var project: KnittingProject
    @Environment(\.modelContext) private var modelContext
    var onSelectPdfPage: (Int) -> Void
    var onExitProject: () -> Void = {}
    
    @State private var displayMode: GuideDisplayMode = .card
    @State private var currentStepIndex: Int = 0
    @State private var showingGenerateSheet = false
    @State private var showingAddStepSheet = false
    @State private var sectionToDelete: String? = nil
    @State private var showingDeleteSectionAlert = false
    @State private var errorMessage: String?
    @State private var showingCompletion = false
    
    /// Etichetta del tab della guida: nome del pattern + taglia
    private var patternTabLabel: String {
        let size = project.selectedSize.trimmingCharacters(in: .whitespaces)
        return size.isEmpty ? project.title : "\(project.title) · \(size)"
    }
    
    private var sortedSteps: [GuideStep] {
        project.guideSteps.sorted(by: { $0.orderIndex < $1.orderIndex })
    }
    
    struct SectionGroup: Identifiable {
        let id: String
        let title: String
        let steps: [GuideStep]
    }
    
    private var orderedSections: [SectionGroup] {
        var orderedTitles: [String] = []
        for step in sortedSteps {
            if !orderedTitles.contains(step.sectionTitle) {
                orderedTitles.append(step.sectionTitle)
            }
        }
        
        return orderedTitles.map { title in
            SectionGroup(
                id: title,
                title: title,
                steps: sortedSteps.filter { $0.sectionTitle == title }
            )
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if project.guideSteps.isEmpty {
                    ContentUnavailableView {
                        Label("Nessuna Guida", systemImage: "sparkles")
                    } description: {
                        Text("Carica la guida operativa del No Frills Sweater, generane una nuova da PDF con Gemini o aggiungi manualmente sezioni e passaggi.")
                    } actions: {
                        VStack(spacing: 12) {
                            Button {
                                loadPreloadedGuide()
                            } label: {
                                Label("Carica Guida No Frills (Taglia M)", systemImage: "sparkles")
                                    .bold()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button {
                                showingAddStepSheet = true
                            } label: {
                                Label("Aggiungi Sezione Manualmente", systemImage: "plus.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            
                            Button {
                                showingGenerateSheet = true
                            } label: {
                                Label("Genera con Gemini AI", systemImage: "brain")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                            .disabled(project.pdfData == nil)
                        }
                        .padding(.horizontal, 24)
                    }
                } else {
                    VStack(spacing: 0) {
                        if project.completedAt != nil {
                            Button {
                                showingCompletion = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.seal.fill")
                                    Text("Progetto completato · Vedi riepilogo")
                                        .font(.subheadline.bold())
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                            .padding(.top, 8)
                        }
                        
                        // Selettore Pattern (Card Singola) / Elenco Sezioni
                        Picker("Modalità", selection: $displayMode) {
                            Text(patternTabLabel).tag(GuideDisplayMode.card)
                            Text(GuideDisplayMode.list.rawValue).tag(GuideDisplayMode.list)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                        
                        if displayMode == .card {
                            // Modalità Scheda Singola (Focus Mode)
                            GuideSingleCardView(
                                steps: sortedSteps,
                                orderedSections: orderedSections,
                                currentIndex: $currentStepIndex,
                                onNavigateToPage: onSelectPdfPage,
                                onDeleteStep: { step in
                                    deleteStep(step)
                                },
                                onFinishGuide: {
                                    finishGuide()
                                }
                            )
                        } else {
                            // Modalità Elenco Completo con gestione Sezioni
                            List {
                                ForEach(orderedSections) { group in
                                    Section {
                                        ForEach(group.steps) { step in
                                            GuideStepRow(
                                                step: step,
                                                onNavigateToPage: onSelectPdfPage,
                                                onJumpToCard: {
                                                    if let idx = sortedSteps.firstIndex(where: { $0.id == step.id }) {
                                                        currentStepIndex = idx
                                                        displayMode = .card
                                                    }
                                                },
                                                onDelete: {
                                                    deleteStep(step)
                                                }
                                            )
                                        }
                                        .onDelete { indexSet in
                                            deleteStepsFromGroup(indexSet, in: group)
                                        }
                                    } header: {
                                        HStack {
                                            Text(group.title)
                                                .font(.headline)
                                            Spacer()
                                            Menu {
                                                Button(role: .destructive) {
                                                    sectionToDelete = group.title
                                                    showingDeleteSectionAlert = true
                                                } label: {
                                                    Label("Elimina Sezione '\(group.title)'", systemImage: "trash")
                                                }
                                            } label: {
                                                Image(systemName: "ellipsis")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .padding(6)
                                            }
                                        }
                                    }
                                }
                            }
                            .listStyle(.insetGrouped)
                        }
                    }
                }
            }
            .navigationTitle(displayMode == .card && !project.guideSteps.isEmpty ? patternTabLabel : "Elenco Sezioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showingAddStepSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.body.bold())
                        }
                        
                        if !project.guideSteps.isEmpty {
                            Menu {
                                Button {
                                    showingAddStepSheet = true
                                } label: {
                                    Label("Aggiungi Sezione / Passaggio", systemImage: "plus.rectangle.on.rectangle")
                                }
                                
                                Divider()
                                
                                Button {
                                    loadPreloadedGuide()
                                } label: {
                                    Label("Ricarica Guida No Frills (M)", systemImage: "arrow.counterclockwise")
                                }
                                Button {
                                    showingGenerateSheet = true
                                } label: {
                                    Label("Rigenera con Gemini AI", systemImage: "sparkles")
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    clearAllSteps()
                                } label: {
                                    Label("Svuota Tutta la Guida", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
            }
            .onAppear {
                if let firstIncomplete = sortedSteps.firstIndex(where: { !$0.isCompleted }) {
                    currentStepIndex = firstIncomplete
                }
            }
            .sheet(isPresented: $showingAddStepSheet) {
                AddGuideStepSheet(project: project)
            }
            .sheet(isPresented: $showingGenerateSheet) {
                GenerateGuideSheet(project: project)
            }
            .fullScreenCover(isPresented: $showingCompletion) {
                GuideCompletionView(
                    project: project,
                    onReviewGuide: {
                        showingCompletion = false
                    },
                    onExit: {
                        showingCompletion = false
                        onExitProject()
                    }
                )
            }
            .alert("Elimina Sezione", isPresented: $showingDeleteSectionAlert) {
                Button("Annulla", role: .cancel) { sectionToDelete = nil }
                Button("Elimina", role: .destructive) {
                    if let sec = sectionToDelete {
                        deleteEntireSection(sec)
                    }
                    sectionToDelete = nil
                }
            } message: {
                Text("Sei sicuro di voler eliminare l'intera sezione '\(sectionToDelete ?? "")' e tutti i suoi passaggi?")
            }
            .alert("Errore", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
    
    // MARK: - Fine Guida
    private func finishGuide() {
        // Salva la sessione di lavoro in corso nel tempo totale del progetto
        if TimerManager.shared.isRunning && TimerManager.shared.activeProjectId == project.id {
            let duration = TimerManager.shared.pause()
            project.totalSecondsWorked += duration
        }
        project.completedAt = Date()
        project.updatedAt = Date()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showingCompletion = true
    }
    
    // MARK: - Funzioni di Cancellazione e Gestione
    private func deleteStep(_ step: GuideStep) {
        if let idx = project.guideSteps.firstIndex(where: { $0.id == step.id }) {
            project.guideSteps.remove(at: idx)
            modelContext.delete(step)
            if currentStepIndex >= project.guideSteps.count {
                currentStepIndex = max(0, project.guideSteps.count - 1)
            }
        }
    }
    
    private func deleteStepsFromGroup(_ indexSet: IndexSet, in group: SectionGroup) {
        for index in indexSet {
            let step = group.steps[index]
            deleteStep(step)
        }
    }
    
    private func deleteEntireSection(_ sectionTitle: String) {
        let stepsToDelete = project.guideSteps.filter { $0.sectionTitle == sectionTitle }
        for step in stepsToDelete {
            deleteStep(step)
        }
    }
    
    private func clearAllSteps() {
        for step in project.guideSteps {
            modelContext.delete(step)
        }
        project.guideSteps.removeAll()
        currentStepIndex = 0
        project.completedAt = nil
    }
    
    private func loadPreloadedGuide() {
        guard let guideUrl = Bundle.main.url(forResource: "NoFrillsGuide_M", withExtension: "json"),
              let guideData = try? Data(contentsOf: guideUrl),
              let guide = try? JSONDecoder().decode(GeneratedGuideResponse.self, from: guideData) else {
            errorMessage = "Guida di test non trovata nel bundle."
            return
        }
        
        project.selectedSize = "M"
        project.completedAt = nil
        for step in project.guideSteps {
            modelContext.delete(step)
        }
        project.guideSteps.removeAll()
        
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
                    hasCounter: stepData.hasCounter ?? false,
                    counterLabel: stepData.counterLabel,
                    currentStepCount: 0,
                    targetStepCount: stepData.targetStepCount
                )
                step.project = project
                project.guideSteps.append(step)
                stepOrder += 1
            }
        }
        currentStepIndex = 0
    }
}

// MARK: - Vista Card Singola (Focus Mode)
struct GuideSingleCardView: View {
    let steps: [GuideStep]
    let orderedSections: [GuideView.SectionGroup]
    @Binding var currentIndex: Int
    var onNavigateToPage: (Int) -> Void
    var onDeleteStep: (GuideStep) -> Void
    var onFinishGuide: () -> Void = {}
    
    @State private var showingEditSheet = false
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private let successHaptic = UINotificationFeedbackGenerator()
    
    var currentStep: GuideStep? {
        guard !steps.isEmpty, currentIndex >= 0, currentIndex < steps.count else { return nil }
        return steps[currentIndex]
    }
    
    // Calcola quale subStep è attivo se siamo in un pattern ripetuto
    private func isSubStepActive(index: Int, for step: GuideStep) -> Bool {
        guard let rowsPerRep = step.rowsPerRepeat, rowsPerRep > 1, !step.subSteps.isEmpty else {
            return false
        }
        if let target = step.targetStepCount, step.currentStepCount >= target {
            return false
        }
        let currentRowInCycle = (step.currentStepCount % rowsPerRep) + 1 // 1..rowsPerRep
        if step.subSteps.count == rowsPerRep {
            return index == (currentRowInCycle - 1)
        } else if rowsPerRep == 6 && step.subSteps.count == 2 {
            // Caso tipico maniche: Giri 1-5 (index 0) e Giro 6 di diminuzione (index 1)
            return currentRowInCycle < 6 ? (index == 0) : (index == 1)
        }
        return false
    }
    
    // Calcola quale repeatVariation è attiva
    private func isVariationActive(index: Int, for step: GuideStep) -> Bool {
        guard let rowsPerRep = step.rowsPerRepeat, rowsPerRep > 0, !step.repeatVariations.isEmpty else {
            return false
        }
        if let target = step.targetStepCount, step.currentStepCount >= target {
            return false
        }
        let currentRepeatZeroBased = step.currentStepCount / rowsPerRep
        return index == currentRepeatZeroBased
    }
    
    var body: some View {
        if let step = currentStep {
            VStack(spacing: 12) {
                // Selettore rapido Sezione + Progresso
                VStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(orderedSections) { group in
                                let isCurrentSection = group.title == step.sectionTitle
                                Button {
                                    if let firstStep = group.steps.first,
                                       let idx = steps.firstIndex(where: { $0.id == firstStep.id }) {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            currentIndex = idx
                                        }
                                    }
                                } label: {
                                    Text(group.title)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(isCurrentSection ? Color.accentColor : Color(.systemGray5))
                                        .foregroundColor(isCurrentSection ? .white : .secondary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    HStack {
                        Text(step.sectionTitle.uppercased())
                            .font(.caption2.bold())
                            .foregroundColor(.accentColor)
                        
                        Spacer()
                        
                        Text("Scheda \(currentIndex + 1) di \(steps.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    
                    ProgressView(value: Double(currentIndex + 1), total: Double(steps.count))
                        .tint(.accentColor)
                        .padding(.horizontal, 20)
                }
                
                // La Card Principale
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Top Bar della Card: Tipo Step, Pagina PDF, Modifica
                        HStack(spacing: 8) {
                            stepTypeBadge(for: step)
                            
                            if let page = step.sourcePage {
                                Button {
                                    onNavigateToPage(page)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.text")
                                        Text("Pag. \(page)")
                                    }
                                    .font(.caption.bold())
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundColor(.orange)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Spacer()
                            
                            if step.isCompleted {
                                Menu {
                                    Button {
                                        step.isCompleted = false
                                        step.completedAt = nil
                                    } label: {
                                        Label("Segna come da fare", systemImage: "arrow.uturn.backward")
                                    }
                                } label: {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(.green)
                                }
                            }
                            
                            Button {
                                showingEditSheet = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "pencil")
                                    Text("Modifica")
                                }
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(.systemGray5))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Titolo della Scheda
                        if !step.title.isEmpty {
                            Text(step.title)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        
                        // Badge Maglie Prima -> Dopo e Misura
                        HStack(spacing: 10) {
                            if let before = step.stitchCountBefore, let after = step.stitchCountAfter, before != after {
                                let diff = after - before
                                let diffStr = diff > 0 ? "+\(diff)" : "\(diff)"
                                Label("\(before) → \(after) maglie (\(diffStr))", systemImage: "arrow.right.circle.fill")
                                    .font(.caption.bold())
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else if let sts = step.stitchCountAfter, sts > 0 {
                                Label("\(sts) maglie sui ferri", systemImage: "number")
                                    .font(.caption.bold())
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            
                            if let measure = step.targetMeasureCm {
                                Label("Misura: \(String(format: "%.0f", measure)) cm", systemImage: "ruler")
                                    .font(.caption.bold())
                                    .foregroundColor(.purple)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.purple.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        
                        // CONTATORE INTEGRATO (in primo piano per guidare i passaggi)
                        if step.hasCounter {
                            CardCounterBoxView(step: step)
                        }
                        
                        // Testo Principale dell'Istruzione
                        Text(step.instructionText)
                            .font(.system(size: 17, weight: .regular, design: .rounded))
                            .lineSpacing(4)
                            .foregroundColor(.primary)
                        
                        // SUB-STEPS (Ferri o Giri del Ciclo Ripetuto, con evidenziazione del ferro attivo)
                        if !step.subSteps.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: step.rowsPerRepeat != nil ? "repeat" : "list.number")
                                        .foregroundColor(.accentColor)
                                    Text(step.rowsPerRepeat != nil ? "Passaggi del Ciclo (Evidenziato il ferro attuale):" : "Dettaglio Passaggi:")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.secondary)
                                }
                                
                                ForEach(Array(step.subSteps.enumerated()), id: \.offset) { idx, subText in
                                    let isActive = isSubStepActive(index: idx, for: step)
                                    VStack(alignment: .leading, spacing: 4) {
                                        if isActive {
                                            HStack(spacing: 4) {
                                                Image(systemName: "hand.point.right.fill")
                                                Text("DA LAVORARE ORA")
                                            }
                                            .font(.caption2.bold())
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.accentColor)
                                            .clipShape(Capsule())
                                        }
                                        
                                        Text(subText)
                                            .font(.system(size: 15, weight: isActive ? .semibold : .regular, design: .rounded))
                                            .foregroundColor(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(isActive ? Color.accentColor.opacity(0.14) : Color(.tertiarySystemGroupedBackground))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                                }
                            }
                        }
                        
                        // REPEAT VARIATIONS (es. avanzamento ferri accorciati per ciascuna ripetizione)
                        if !step.repeatVariations.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(.indigo)
                                    Text("Dove girare in ogni Ripetizione:")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.secondary)
                                }
                                
                                ForEach(Array(step.repeatVariations.enumerated()), id: \.offset) { idx, varText in
                                    let isCurrentVar = isVariationActive(index: idx, for: step)
                                    let isPastVar = (step.rowsPerRepeat != nil) && (step.currentStepCount / step.rowsPerRepeat!) > idx
                                    
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: isPastVar ? "checkmark.circle.fill" : (isCurrentVar ? "arrow.right.circle.fill" : "circle"))
                                            .foregroundColor(isPastVar ? .green : (isCurrentVar ? .indigo : .secondary))
                                            .font(.subheadline)
                                            .padding(.top, 2)
                                        
                                        VStack(alignment: .leading, spacing: 3) {
                                            if isCurrentVar {
                                                Text("RIPETIZIONE IN CORSO")
                                                    .font(.caption2.bold())
                                                    .foregroundColor(.indigo)
                                            }
                                            Text(varText)
                                                .font(.system(size: 14, weight: isCurrentVar ? .semibold : .regular, design: .rounded))
                                                .foregroundColor(isPastVar ? .secondary : .primary)
                                                .strikethrough(isPastVar, color: .secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(isCurrentVar ? Color.indigo.opacity(0.12) : Color(.tertiarySystemGroupedBackground))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(isCurrentVar ? Color.indigo : Color.clear, lineWidth: 1.5)
                                    )
                                }
                            }
                        }
                    }
                    .padding(20)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(24)
                    .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
                    .padding(.horizontal, 16)
                }
                
                // Barra di Navigazione Inferiore
                // Le frecce servono solo a sfogliare (NON segnano la scheda come completata).
                // Il pulsante centrale segna la scheda come completata e passa alla successiva.
                HStack(spacing: 10) {
                    Button {
                        if currentIndex > 0 {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                currentIndex -= 1
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.bold())
                            .frame(width: 52, height: 50)
                            .background(Color(.systemGray6))
                            .foregroundColor(currentIndex > 0 ? .primary : .secondary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(currentIndex == 0)
                    
                    let isLast = currentIndex >= steps.count - 1
                    Button {
                        haptic.impactOccurred()
                        TimerManager.shared.registerInteraction()
                        if step.isCompleted && !isLast {
                            // Scheda già completata: si limita ad avanzare
                            withAnimation(.easeInOut(duration: 0.25)) { currentIndex += 1 }
                            return
                        }
                        step.isCompleted = true
                        step.completedAt = Date()
                        if !isLast {
                            withAnimation(.easeInOut(duration: 0.25)) { currentIndex += 1 }
                        } else {
                            successHaptic.notificationOccurred(.success)
                            onFinishGuide()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isLast {
                                Text("Termina Guida")
                                Image(systemName: "flag.checkered")
                            } else if step.isCompleted {
                                Text("Già completata · Avanti")
                                Image(systemName: "chevron.right")
                            } else {
                                Image(systemName: "checkmark")
                                Text("Completa scheda")
                            }
                        }
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(step.isCompleted && !isLast ? Color.green : Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 6, x: 0, y: 3)
                    }
                    
                    Button {
                        if !isLast {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                currentIndex += 1
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.headline.bold())
                            .frame(width: 52, height: 50)
                            .background(Color(.systemGray6))
                            .foregroundColor(!isLast ? .primary : .secondary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(isLast)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            .sheet(isPresented: $showingEditSheet) {
                EditGuideStepSheet(step: step, onDelete: {
                    onDeleteStep(step)
                })
            }
        }
    }
    
    @ViewBuilder
    private func stepTypeBadge(for step: GuideStep) -> some View {
        if let rows = step.rowsPerRepeat, let reps = step.totalRepeats, rows > 0, reps > 0 {
            HStack(spacing: 4) {
                Image(systemName: "repeat")
                Text("PATTERN RIPETUTO: \(reps) × \(rows) = \(reps * rows)")
            }
            .font(.caption2.bold())
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.indigo.opacity(0.15))
            .foregroundColor(.indigo)
            .clipShape(Capsule())
        } else if step.stepType == "work_to_measure" {
            HStack(spacing: 4) {
                Image(systemName: "ruler")
                Text("A MISURA / GIRI")
            }
            .font(.caption2.bold())
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.purple.opacity(0.15))
            .foregroundColor(.purple)
            .clipShape(Capsule())
        } else if step.stepType == "info" || !step.hasCounter {
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                Text("ISTRUZIONE / SETUP")
            }
            .font(.caption2.bold())
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.15))
            .foregroundColor(.secondary)
            .clipShape(Capsule())
        } else {
            HStack(spacing: 4) {
                Image(systemName: "plus.forwardslash.minus")
                Text("AZIONE CON CONTATORE")
            }
            .font(.caption2.bold())
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.green.opacity(0.15))
            .foregroundColor(.green)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Box Contatore Integrato (un solo contatore globale + contatori manuali)
struct CardCounterBoxView: View {
    @Bindable var step: GuideStep
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private let successHaptic = UINotificationFeedbackGenerator()
    
    @State private var showingAddExtraCounter = false
    @State private var newExtraCounterName = ""
    
    var effectiveTarget: Int? {
        if let rows = step.rowsPerRepeat, let reps = step.totalRepeats, rows > 0, reps > 0 {
            return rows * reps
        }
        return step.targetStepCount
    }
    
    var isTargetReached: Bool {
        if let target = effectiveTarget, target > 0 {
            return step.currentStepCount >= target
        }
        return false
    }
    
    /// Riga informativa (non è un contatore) sulla posizione nel ciclo ripetuto
    var repeatPositionText: String? {
        guard let rows = step.rowsPerRepeat, let reps = step.totalRepeats, rows > 1, reps > 1 else { return nil }
        if isTargetReached { return "Tutte le \(reps) ripetizioni completate" }
        let rep = min(step.currentStepCount / rows + 1, reps)
        let row = step.currentStepCount % rows + 1
        return "Ripetizione \(rep) di \(reps) · ferro \(row) di \(rows)"
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Intestazione contatore globale
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.counterLabel ?? "Contatore")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    if let info = repeatPositionText {
                        Text(info)
                            .font(.caption.bold())
                            .foregroundColor(isTargetReached ? .green : .indigo)
                    } else if let target = effectiveTarget {
                        Text("Obiettivo: \(target)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if step.currentStepCount > 0 {
                    Button("Azzera") { step.currentStepCount = 0 }
                        .font(.caption.bold())
                        .foregroundColor(.red)
                }
            }
            
            if let target = effectiveTarget, target > 0 {
                ProgressView(value: min(Double(step.currentStepCount) / Double(target), 1.0))
                    .tint(isTargetReached ? .green : .accentColor)
            }
            
            // Contatore globale: - valore +
            HStack(spacing: 20) {
                Button {
                    TimerManager.shared.registerInteraction()
                    haptic.impactOccurred()
                    if step.currentStepCount > 0 { step.currentStepCount -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .font(.title3.bold())
                        .foregroundColor(.primary)
                        .frame(width: 48, height: 48)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
                .disabled(step.currentStepCount == 0)
                
                Spacer()
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(step.currentStepCount)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(isTargetReached ? .green : .primary)
                    if let target = effectiveTarget {
                        Text("/ \(target)")
                            .font(.title3.bold())
                            .foregroundColor(.secondary)
                    }
                }
                .contentTransition(.numericText())
                
                Spacer()
                
                Button {
                    TimerManager.shared.registerInteraction()
                    haptic.impactOccurred()
                    step.currentStepCount += 1
                    if isTargetReached { successHaptic.notificationOccurred(.success) }
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .frame(width: 58, height: 58)
                        .background(isTargetReached ? Color.green : Color.accentColor)
                        .clipShape(Circle())
                        .shadow(color: (isTargetReached ? Color.green : Color.accentColor).opacity(0.35), radius: 6, x: 0, y: 3)
                }
            }
            
            // Contatori aggiuntivi creati manualmente dall'utente
            if !step.extraCounterLabels.isEmpty {
                Divider()
                ForEach(Array(step.extraCounterLabels.enumerated()), id: \.offset) { idx, label in
                    ExtraCounterRow(
                        label: label,
                        value: idx < step.extraCounterValues.count ? step.extraCounterValues[idx] : 0,
                        onMinus: { changeExtra(at: idx, by: -1) },
                        onPlus: { changeExtra(at: idx, by: 1) },
                        onReset: { setExtra(at: idx, to: 0) },
                        onDelete: { removeExtra(at: idx) }
                    )
                }
            }
            
            Button {
                newExtraCounterName = ""
                showingAddExtraCounter = true
            } label: {
                Label("Aggiungi contatore", systemImage: "plus.circle")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
        .padding(16)
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(18)
        .alert("Nuovo contatore", isPresented: $showingAddExtraCounter) {
            TextField("Nome (es. Aumenti, Motivo, Trecce)", text: $newExtraCounterName)
            Button("Annulla", role: .cancel) {}
            Button("Aggiungi") {
                let name = newExtraCounterName.trimmingCharacters(in: .whitespaces)
                step.extraCounterLabels.append(name.isEmpty ? "Contatore \(step.extraCounterLabels.count + 1)" : name)
                step.extraCounterValues.append(0)
            }
        }
    }
    
    private func normalizedValues() -> [Int] {
        var values = step.extraCounterValues
        while values.count < step.extraCounterLabels.count { values.append(0) }
        return values
    }
    
    private func changeExtra(at idx: Int, by delta: Int) {
        TimerManager.shared.registerInteraction()
        haptic.impactOccurred()
        var values = normalizedValues()
        guard idx < values.count else { return }
        values[idx] = max(0, values[idx] + delta)
        step.extraCounterValues = values
    }
    
    private func setExtra(at idx: Int, to value: Int) {
        var values = normalizedValues()
        guard idx < values.count else { return }
        values[idx] = value
        step.extraCounterValues = values
    }
    
    private func removeExtra(at idx: Int) {
        var labels = step.extraCounterLabels
        var values = normalizedValues()
        guard idx < labels.count else { return }
        labels.remove(at: idx)
        values.remove(at: idx)
        step.extraCounterLabels = labels
        step.extraCounterValues = values
    }
}

struct ExtraCounterRow: View {
    let label: String
    let value: Int
    var onMinus: () -> Void
    var onPlus: () -> Void
    var onReset: () -> Void
    var onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Menu {
                Button("Azzera", systemImage: "arrow.counterclockwise", action: onReset)
                Button("Elimina contatore", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                HStack(spacing: 4) {
                    Text(label)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Image(systemName: "ellipsis")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: onMinus) {
                Image(systemName: "minus")
                    .font(.caption.bold())
                    .frame(width: 32, height: 32)
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(value == 0)
            
            Text("\(value)")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .frame(minWidth: 36)
                .contentTransition(.numericText())
            
            Button(action: onPlus) {
                Image(systemName: "plus")
                    .font(.caption.bold())
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.18))
                    .foregroundColor(.accentColor)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
}


// MARK: - Foglio per Aggiungere Manualmente una Sezione o Passaggio
struct AddGuideStepSheet: View {
    @Environment(\.dismiss) private var dismiss
    var project: KnittingProject
    
    @State private var sectionTitle: String = ""
    @State private var title: String = ""
    @State private var stepType: String = "single_action"
    @State private var instructionText: String = ""
    @State private var hasCounter: Bool = true
    @State private var counterLabel: String = "Ferri / Maglie"
    @State private var rowsPerRepeatString: String = "4"
    @State private var totalRepeatsString: String = "5"
    @State private var targetCountString: String = ""
    @State private var subStepsText: String = ""
    @State private var targetMeasureString: String = ""
    @State private var sourcePageString: String = ""
    @State private var stitchCountAfterString: String = ""
    
    var existingSections: [String] {
        var titles: [String] = []
        for step in project.guideSteps.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            if !titles.contains(step.sectionTitle) {
                titles.append(step.sectionTitle)
            }
        }
        return titles
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Sezione e Titolo") {
                    TextField("Nome Sezione (es. Sprone, Corpo, Maniche)", text: $sectionTitle)
                    
                    if !existingSections.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(existingSections, id: \.self) { sec in
                                    Button {
                                        sectionTitle = sec
                                    } label: {
                                        Text(sec)
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(sectionTitle == sec ? Color.accentColor : Color(.systemGray5))
                                            .foregroundColor(sectionTitle == sec ? .white : .primary)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    TextField("Titolo Scheda (es. Ferri Accorciati 5 × 4)", text: $title)
                }
                
                Section("Tipo di Passaggio") {
                    Picker("Tipo", selection: $stepType) {
                        Text("Azione Singola").tag("single_action")
                        Text("Pattern Ripetuto (N × M ferri)").tag("repeat_pattern")
                        Text("Lavora a Misura (cm)").tag("work_to_measure")
                        Text("Solo Informazione").tag("info")
                    }
                    .onChange(of: stepType) { _, newValue in
                        if newValue == "info" {
                            hasCounter = false
                        } else {
                            hasCounter = true
                        }
                    }
                }
                
                Section("Istruzione") {
                    TextEditor(text: $instructionText)
                        .frame(minHeight: 90)
                }
                
                if stepType == "repeat_pattern" {
                    Section("Calcolo Pattern Ripetuto") {
                        HStack {
                            Text("Ferri per ogni ripetizione:")
                            Spacer()
                            TextField("Es. 4", text: $rowsPerRepeatString)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        HStack {
                            Text("Numero di ripetizioni:")
                            Spacer()
                            TextField("Es. 5", text: $totalRepeatsString)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        if let r = Int(rowsPerRepeatString), let t = Int(totalRepeatsString) {
                            Text("Totale Contatore: \(r * t) ferri/giri")
                                .font(.subheadline.bold())
                                .foregroundColor(.indigo)
                        }
                    }
                } else {
                    Section("Contatore Integrato") {
                        Toggle("Abilita contatore su questa card", isOn: $hasCounter)
                        
                        if hasCounter {
                            TextField("Nome contatore (es. Maglie Avviate, Giri)", text: $counterLabel)
                            TextField("Obiettivo numerico (es. 114)", text: $targetCountString)
                                .keyboardType(.numberPad)
                        }
                    }
                }
                
                Section("Sotto-passaggi (1 per riga, opzionale)") {
                    TextEditor(text: $subStepsText)
                        .frame(minHeight: 80)
                }
                
                Section("Dettagli Aggiuntivi (Opzionali)") {
                    TextField("Maglie totali al termine (es. 154)", text: $stitchCountAfterString)
                        .keyboardType(.numberPad)
                    
                    TextField("Misura in cm (es. 4.0)", text: $targetMeasureString)
                        .keyboardType(.decimalPad)
                    
                    TextField("Numero pagina PDF (es. 3)", text: $sourcePageString)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Aggiungi Scheda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aggiungi") {
                        saveNewStep()
                        dismiss()
                    }
                    .bold()
                    .disabled(sectionTitle.trimmingCharacters(in: .whitespaces).isEmpty || instructionText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
    
    private func saveNewStep() {
        let rowsPerRep = stepType == "repeat_pattern" ? Int(rowsPerRepeatString) : nil
        let totalReps = stepType == "repeat_pattern" ? Int(totalRepeatsString) : nil
        let computedTarget: Int? = {
            if let r = rowsPerRep, let t = totalReps {
                return r * t
            }
            return hasCounter ? Int(targetCountString) : nil
        }()
        
        let parsedSubSteps = subStepsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        let step = GuideStep(
            sectionTitle: sectionTitle.trimmingCharacters(in: .whitespaces),
            title: title.trimmingCharacters(in: .whitespaces),
            stepType: stepType,
            instructionText: instructionText.trimmingCharacters(in: .whitespaces),
            subSteps: parsedSubSteps,
            rowsPerRepeat: rowsPerRep,
            totalRepeats: totalReps,
            stitchCountAfter: Int(stitchCountAfterString),
            targetMeasureCm: Double(targetMeasureString.replacingOccurrences(of: ",", with: ".")),
            sourcePage: Int(sourcePageString),
            orderIndex: project.guideSteps.count,
            hasCounter: stepType == "repeat_pattern" ? true : hasCounter,
            counterLabel: hasCounter ? counterLabel : nil,
            currentStepCount: 0,
            targetStepCount: computedTarget
        )
        step.project = project
        project.guideSteps.append(step)
    }
}

// MARK: - Foglio Modifica Passaggio e Sezione
struct EditGuideStepSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var step: GuideStep
    var onDelete: () -> Void
    
    @State private var sectionTitle: String = ""
    @State private var title: String = ""
    @State private var stepType: String = "single_action"
    @State private var editedText: String = ""
    @State private var hasCounter: Bool = false
    @State private var counterLabel: String = ""
    @State private var rowsPerRepeatString: String = ""
    @State private var totalRepeatsString: String = ""
    @State private var targetCountString: String = ""
    @State private var subStepsText: String = ""
    @State private var variationsText: String = ""
    @State private var targetMeasureString: String = ""
    @State private var stitchBeforeString: String = ""
    @State private var stitchCountString: String = ""
    @State private var sourcePageString: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Sezione e Titolo") {
                    TextField("Nome Sezione", text: $sectionTitle)
                    TextField("Titolo Scheda", text: $title)
                }
                
                Section("Tipo di Scheda") {
                    Picker("Tipo", selection: $stepType) {
                        Text("Azione Singola").tag("single_action")
                        Text("Pattern Ripetuto (N × M ferri)").tag("repeat_pattern")
                        Text("Lavora a Misura (cm)").tag("work_to_measure")
                        Text("Solo Informazione").tag("info")
                    }
                }
                
                Section("Testo Istruzione") {
                    TextEditor(text: $editedText)
                        .frame(minHeight: 100)
                }
                
                Section("Contatore e Ripetizioni") {
                    Toggle("Mostra contatore sulla scheda", isOn: $hasCounter)
                    
                    if hasCounter {
                        TextField("Etichetta contatore", text: $counterLabel)
                        
                        if stepType == "repeat_pattern" {
                            HStack {
                                Text("Ferri per ripetizione:")
                                Spacer()
                                TextField("Es. 4", text: $rowsPerRepeatString)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                            }
                            HStack {
                                Text("Ripetizioni totali:")
                                Spacer()
                                TextField("Es. 5", text: $totalRepeatsString)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                            }
                        }
                        
                        HStack {
                            Text("Obiettivo totale contatore:")
                            Spacer()
                            TextField("Es. 20", text: $targetCountString)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                    }
                }
                
                Section("Ferri / Sotto-passaggi (1 per riga)") {
                    TextEditor(text: $subStepsText)
                        .frame(minHeight: 90)
                }
                
                Section("Variazioni per Ripetizione (1 per riga)") {
                    TextEditor(text: $variationsText)
                        .frame(minHeight: 80)
                }
                
                Section("Maglie e Misure") {
                    HStack {
                        Text("Maglie iniziali:")
                        Spacer()
                        TextField("Es. 114", text: $stitchBeforeString)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Maglie finali:")
                        Spacer()
                        TextField("Es. 154", text: $stitchCountString)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Misura obiettivo (cm):")
                        Spacer()
                        TextField("Es. 4.0", text: $targetMeasureString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Pagina PDF:")
                        Spacer()
                        TextField("Es. 3", text: $sourcePageString)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Elimina questa Scheda", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Modifica Scheda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        saveChanges()
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear {
                sectionTitle = step.sectionTitle
                title = step.title
                stepType = step.stepType
                editedText = step.instructionText
                hasCounter = step.hasCounter
                counterLabel = step.counterLabel ?? ""
                if let r = step.rowsPerRepeat { rowsPerRepeatString = "\(r)" }
                if let t = step.totalRepeats { totalRepeatsString = "\(t)" }
                if let target = step.targetStepCount { targetCountString = "\(target)" }
                subStepsText = step.subSteps.joined(separator: "\n")
                variationsText = step.repeatVariations.joined(separator: "\n")
                if let before = step.stitchCountBefore { stitchBeforeString = "\(before)" }
                if let sts = step.stitchCountAfter { stitchCountString = "\(sts)" }
                if let measure = step.targetMeasureCm { targetMeasureString = "\(measure)" }
                if let page = step.sourcePage { sourcePageString = "\(page)" }
            }
        }
    }
    
    private func saveChanges() {
        step.sectionTitle = sectionTitle.trimmingCharacters(in: .whitespaces)
        step.title = title.trimmingCharacters(in: .whitespaces)
        step.stepType = stepType
        step.instructionText = editedText
        step.hasCounter = hasCounter
        step.counterLabel = counterLabel.isEmpty ? nil : counterLabel
        step.rowsPerRepeat = Int(rowsPerRepeatString)
        step.totalRepeats = Int(totalRepeatsString)
        if let r = step.rowsPerRepeat, let t = step.totalRepeats, r > 0, t > 0 {
            step.targetStepCount = r * t
        } else {
            step.targetStepCount = Int(targetCountString)
        }
        step.subSteps = subStepsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        step.repeatVariations = variationsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        step.stitchCountBefore = Int(stitchBeforeString)
        step.stitchCountAfter = Int(stitchCountString)
        step.targetMeasureCm = Double(targetMeasureString.replacingOccurrences(of: ",", with: "."))
        step.sourcePage = Int(sourcePageString)
    }
}

// MARK: - Riga Elenco Completo
struct GuideStepRow: View {
    @Bindable var step: GuideStep
    var onNavigateToPage: (Int) -> Void
    var onJumpToCard: () -> Void
    var onDelete: () -> Void
    @State private var showingEditSheet = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                step.isCompleted.toggle()
                step.completedAt = step.isCompleted ? Date() : nil
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(step.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            
            Button {
                onJumpToCard()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    if !step.title.isEmpty {
                        Text(step.title)
                            .font(.subheadline.bold())
                            .foregroundColor(step.isCompleted ? .secondary : .primary)
                            .strikethrough(step.isCompleted, color: .secondary)
                    }
                    
                    Text(step.instructionText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    HStack(spacing: 6) {
                        if let rows = step.rowsPerRepeat, let reps = step.totalRepeats {
                            Text("\(reps)×\(rows) = \(reps * rows) ferri")
                                .font(.caption2.bold())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.indigo.opacity(0.14))
                                .foregroundColor(.indigo)
                                .clipShape(Capsule())
                        } else if step.hasCounter, let target = step.targetStepCount {
                            Text("\(step.currentStepCount)/\(target)")
                                .font(.caption2.bold())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.14))
                                .foregroundColor(.green)
                                .clipShape(Capsule())
                        }
                        
                        if let sts = step.stitchCountAfter, sts > 0 {
                            Text("\(sts) m")
                                .font(.caption2.bold())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.12))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                        }
                        
                        if let measure = step.targetMeasureCm {
                            Text("\(String(format: "%.0f", measure)) cm")
                                .font(.caption2.bold())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.purple.opacity(0.12))
                                .foregroundColor(.purple)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Button {
                showingEditSheet = true
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingEditSheet) {
            EditGuideStepSheet(step: step, onDelete: onDelete)
        }
    }
}

// MARK: - Sheet Generazione AI
struct GenerateGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var project: KnittingProject
    
    @State private var targetSize: String = "M"
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Taglia Desiderata") {
                    TextField("Es. XS, S, M, L, XL...", text: $targetSize)
                    Text("Gemini (con ragionamento profondo) analizzerà il pattern calcolando ferri ripetuti, maglie e contatori per la taglia scelta.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if isProcessing {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Gemini sta analizzando i cicli di ripetizione e calcolando i ferri...")
                                .font(.subheadline)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Crea Guida con AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                        .disabled(isProcessing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Genera") {
                        generateGuide()
                    }
                    .bold()
                    .disabled(targetSize.trimmingCharacters(in: .whitespaces).isEmpty || isProcessing)
                }
            }
            .alert("Errore", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
    
    private func generateGuide() {
        guard let pdfData = project.pdfData else {
            errorMessage = "Nessun PDF associato a questo progetto."
            return
        }
        
        isProcessing = true
        
        Task {
            do {
                let response = try await GeminiService.shared.generateGuide(from: pdfData, targetSize: targetSize)
                
                await MainActor.run {
                    project.selectedSize = targetSize
                    if project.title.isEmpty || project.title == "Nuovo Progetto" {
                        project.title = response.patternTitle
                    }
                    if let designer = response.designer, !designer.isEmpty {
                        project.designer = designer
                    }
                    
                    for step in project.guideSteps {
                        modelContext.delete(step)
                    }
                    project.guideSteps.removeAll()
                    
                    var stepOrder = 0
                    for section in response.sections {
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
                                hasCounter: stepData.hasCounter ?? false,
                                counterLabel: stepData.counterLabel,
                                currentStepCount: 0,
                                targetStepCount: stepData.targetStepCount
                            )
                            step.project = project
                            project.guideSteps.append(step)
                            stepOrder += 1
                        }
                    }
                    
                    isProcessing = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
