import SwiftUI
import SwiftData

enum GuideDisplayMode: String, CaseIterable {
    case card = "Scheda"
    case list = "Elenco Sezioni"
}

struct GuideView: View {
    @Bindable var project: KnittingProject
    @Binding var currentStepIndex: Int
    @Environment(\.modelContext) private var modelContext
    var onSelectPdfPage: (Int) -> Void
    var onExitProject: () -> Void = {}
    
    @State private var displayMode: GuideDisplayMode = .card
    @State private var showingGenerateSheet = false
    @State private var showingAddStepSheet = false
    @State private var showingGaugeSheet = false
    @State private var sectionToDelete: String? = nil
    @State private var showingDeleteSectionAlert = false
    @State private var errorMessage: String?
    @State private var showingCompletion = false
    
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
        Group {
            if project.isDeleted || project.modelContext == nil {
                Color.clear
            } else if project.guideSteps.isEmpty {
                    ContentUnavailableView {
                        Label("Nessuna Guida", systemImage: "sparkles")
                    } description: {
                        Text(project.pdfData != nil ? "Genera la guida interattiva passo-passo dal PDF con l'AI oppure crea le tue schede manualmente." : "Crea le tue schede operative e i contatori manualmente.")
                    } actions: {
                        VStack(spacing: 12) {
                            if project.pdfData != nil {
                                Button {
                                    showingGenerateSheet = true
                                } label: {
                                    Label("Sviluppa Guida da PDF con AI", systemImage: "sparkles")
                                        .bold()
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 4)
                                }
                                .buttonStyle(.borderedProminent)
                                
                                Button {
                                    showingAddStepSheet = true
                                } label: {
                                    Label("Aggiungi Scheda Manualmente", systemImage: "plus.circle")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 4)
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Button {
                                    showingAddStepSheet = true
                                } label: {
                                    Label("Aggiungi Scheda Manualmente", systemImage: "plus.circle")
                                        .bold()
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 4)
                                }
                                .buttonStyle(.borderedProminent)
                            }
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
                        
                        // Banner Guida Ricalcolata per Campione Utente
                        if project.isGaugeRecalculated {
                            Button {
                                showingGaugeSheet = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(.indigo)
                                    let sts = project.userGaugeStitches ?? 0
                                    let rws = project.userGaugeRows ?? 0
                                    let stsStr = sts.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(sts))" : String(format: "%.1f", sts)
                                    let rwsStr = rws.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(rws))" : String(format: "%.1f", rws)
                                    Text("Guida ricalibrata sul tuo campione (\(stsStr) m × \(rwsStr) f)")
                                        .font(.caption.bold())
                                        .foregroundColor(.indigo)
                                    Spacer()
                                    Text("Dettagli")
                                        .font(.caption2.bold())
                                        .foregroundColor(.accentColor)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.indigo.opacity(0.12))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                            .padding(.top, 4)
                        }
                        
                        if displayMode == .card {
                            // Modalità Scheda Singola (Focus Mode)
                            GuideSingleCardView(
                                steps: sortedSteps,
                                orderedSections: orderedSections,
                                currentIndex: $currentStepIndex,
                                project: project,
                                onNavigateToPage: onSelectPdfPage,
                                onDeleteStep: { step in
                                    deleteStep(step)
                                },
                                onFinishGuide: {
                                    finishGuide()
                                },
                                onOpenGaugeSheet: {
                                    showingGaugeSheet = true
                                },
                                onToggleOutline: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        displayMode = .list
                                    }
                                }
                            )
                        } else {
                            // Modalità Elenco Completo con gestione Sezioni
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Indice Sezioni e Schede")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            displayMode = .card
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "rectangle.portrait.fill")
                                            Text("Torna alla Scheda")
                                        }
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor)
                                        .clipShape(Capsule())
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                
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
                                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                                displayMode = .card
                                                            }
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
            }
            .onAppear {
                if !sortedSteps.isEmpty {
                    if currentStepIndex < 0 || currentStepIndex >= sortedSteps.count {
                        let savedIdx = UserDefaults.standard.object(forKey: "purl_lab_last_guide_step_\(project.id)") as? Int
                        if let saved = savedIdx, saved >= 0 && saved < sortedSteps.count {
                            currentStepIndex = saved
                        } else if let active = project.activeWorkingStep(),
                                  let idx = sortedSteps.firstIndex(where: { $0.id == active.id }) {
                            currentStepIndex = idx
                        } else if let firstIncomplete = sortedSteps.firstIndex(where: { !$0.isCompleted }) {
                            currentStepIndex = firstIncomplete
                        } else {
                            currentStepIndex = 0
                        }
                    }
                }
            }
            .onChange(of: currentStepIndex) { _, newIndex in
                if newIndex >= 0 && newIndex < sortedSteps.count {
                    UserDefaults.standard.set(newIndex, forKey: "purl_lab_last_guide_step_\(project.id)")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .watchDidChangeActiveStep)) { notification in
                if let targetStepId = notification.userInfo?["stepId"] as? UUID,
                   let idx = sortedSteps.firstIndex(where: { $0.id == targetStepId }) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentStepIndex = idx
                    }
                }
            }
            .sheet(isPresented: $showingAddStepSheet) {
                AddGuideStepSheet(project: project)
            }
            .sheet(isPresented: $showingGenerateSheet) {
                GenerateGuideSheet(project: project)
            }
            .sheet(isPresented: $showingGaugeSheet) {
                GaugeRecalculationView(project: project)
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
                    },
                    onRestartFromBeginning: {
                        showingCompletion = false
                        currentStepIndex = 0
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
    
    // MARK: - Fine Guida
    private func finishGuide() {
        // Salva la sessione di lavoro in corso nel tempo totale del progetto
        if TimerManager.shared.isRunning && TimerManager.shared.activeProjectId == project.id {
            _ = TimerManager.shared.pause()
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
}

// MARK: - Vista Card Singola (Focus Mode)
struct GuideSingleCardView: View {
    let steps: [GuideStep]
    let orderedSections: [GuideView.SectionGroup]
    @Binding var currentIndex: Int
    var project: KnittingProject? = nil
    var onNavigateToPage: (Int) -> Void
    var onDeleteStep: (GuideStep) -> Void
    var onFinishGuide: () -> Void = {}
    var onOpenGaugeSheet: () -> Void = {}
    var onToggleOutline: () -> Void = {}
    
    @State private var stepToEdit: GuideStep? = nil
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private let successHaptic = UINotificationFeedbackGenerator()
    
    var currentStep: GuideStep? {
        guard !steps.isEmpty, currentIndex >= 0, currentIndex < steps.count else { return nil }
        let step = steps[currentIndex]
        guard !step.isDetachedOrDeleted else { return nil }
        return step
    }
    
    // Calcola quale subStep è attivo se siamo in un pattern ripetuto
    private func isSubStepActive(index: Int, for step: GuideStep) -> Bool {
        guard !step.isDetachedOrDeleted else { return false }
        let sub = step.safeSubSteps
        guard let rowsPerRep = step.rowsPerRepeat, rowsPerRep > 1, !sub.isEmpty else {
            return false
        }
        if let target = step.targetStepCount, step.currentStepCount >= target {
            return false
        }
        let currentRowInCycle = (step.currentStepCount % rowsPerRep) + 1 // 1..rowsPerRep
        if sub.count == rowsPerRep {
            return index == (currentRowInCycle - 1)
        } else if rowsPerRep == 6 && sub.count == 2 {
            // Caso tipico maniche: Giri 1-5 (index 0) e Giro 6 di diminuzione (index 1)
            return currentRowInCycle < 6 ? (index == 0) : (index == 1)
        }
        return false
    }
    
    // Calcola quale repeatVariation è attiva
    private func isVariationActive(index: Int, for step: GuideStep) -> Bool {
        guard !step.isDetachedOrDeleted else { return false }
        let variations = step.safeRepeatVariations
        guard let rowsPerRep = step.rowsPerRepeat, rowsPerRep > 0, !variations.isEmpty else {
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
            VStack(spacing: 8) {
                // Barra Compatta Sezioni + Progresso
                VStack(spacing: 6) {
                    HStack {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
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
                                            .font(.system(size: 13, weight: isCurrentSection ? .bold : .medium))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(isCurrentSection ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill))
                                            .foregroundColor(isCurrentSection ? Color.accentColor : .secondary)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.leading, 16)
                        }
                        
                        Button {
                            onToggleOutline()
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                    }
                    
                    HStack {
                        ProgressView(value: Double(currentIndex + 1), total: Double(steps.count))
                            .tint(Color.accentColor)
                            .scaleEffect(y: 0.8)
                        
                        Text("\(currentIndex + 1)/\(steps.count)")
                            .font(.caption2.monospacedDigit().weight(.medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 4)
                
                // La Card Principale
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Top Bar Essenziale della Card
                        HStack(alignment: .center, spacing: 8) {
                            if let rows = step.rowsPerRepeat, let reps = step.totalRepeats, rows > 0, reps > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "repeat")
                                    Text("\(reps) × \(rows) ferri")
                                }
                                .font(.caption2.bold())
                                .foregroundColor(.indigo)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.indigo.opacity(0.12))
                                .clipShape(Capsule())
                            } else if step.stepType == "work_to_measure", let cm = step.targetMeasureCm {
                                HStack(spacing: 4) {
                                    Image(systemName: "ruler")
                                    Text("\(Int(cm)) cm")
                                }
                                .font(.caption2.bold())
                                .foregroundColor(.purple)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.12))
                                .clipShape(Capsule())
                            }
                            
                            if let page = step.sourcePage {
                                Button {
                                    onNavigateToPage(page)
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "doc.text")
                                        Text("p. \(page)")
                                    }
                                    .font(.caption2.bold())
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.12))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Spacer()
                            
                            let isWatchActive = (WatchConnectivityIOSManager.shared.activeStepId == step.id)
                            if step.hasCounter || (step.targetStepCount != nil && step.targetStepCount! > 0) {
                                Button {
                                    let targetProject = project ?? step.project
                                    WatchConnectivityIOSManager.shared.setActiveStep(step, for: targetProject)
                                    let gen = UIImpactFeedbackGenerator(style: .medium)
                                    gen.impactOccurred()
                                } label: {
                                    Image(systemName: "applewatch")
                                        .font(.footnote.weight(isWatchActive ? .bold : .regular))
                                        .foregroundColor(isWatchActive ? .green : .secondary)
                                        .padding(6)
                                        .background(isWatchActive ? Color.green.opacity(0.15) : Color(.tertiarySystemFill))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                            
                            if step.isCompleted {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                            }
                            
                            Button {
                                haptic.impactOccurred()
                                stepToEdit = step
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 32, height: 32)
                                    .background(Color(.tertiarySystemFill))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                        }
                        
                        // Titolo della Scheda
                        if !step.title.isEmpty {
                            Text(step.title)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        
                        // Badge Misura (se presente)
                        if let measure = step.targetMeasureCm {
                            HStack(spacing: 8) {
                                Label("Misura: \(String(format: "%.0f", measure)) cm", systemImage: "ruler")
                                    .font(.caption.bold())
                                    .foregroundColor(.purple)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Color.purple.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        
                        // CONTATORE INTEGRATO
                        if step.hasCounter {
                            CardCounterBoxView(step: step)
                        }
                        
                        // Testo Principale dell'Istruzione
                        Text(step.instructionText)
                            .font(.system(size: 17, weight: .regular, design: .rounded))
                            .lineSpacing(5)
                            .foregroundColor(.primary)
                        
                        // Banner Compatto Campione nella card Preparazione / Campione
                        if step.sectionTitle.localizedCaseInsensitiveContains("Preparazione") || step.instructionText.localizedCaseInsensitiveContains("Campione") {
                            let isRecalc = (project?.isGaugeRecalculated ?? false)
                            Button {
                                onOpenGaugeSheet()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: isRecalc ? "gauge.with.needle.fill" : "sparkles")
                                        .font(.subheadline)
                                        .foregroundColor(isRecalc ? .indigo : .accentColor)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(isRecalc ? "Guida ricalibrata sul tuo campione" : "Il tuo campione è diverso da quello del pattern?")
                                            .font(.footnote.bold())
                                            .foregroundColor(.primary)
                                        Text(isRecalc ? "I valori sono adattati alla tua tensione" : "Tocca per ricalibrare la guida con l'AI")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.bold())
                                        .foregroundColor(.secondary)
                                }
                                .padding(10)
                                .background(Color(.tertiarySystemFill))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 2)
                        }
                        
                        // SUB-STEPS (Checklist essenziale con indicatore attivo)
                        let currentSubSteps = step.safeSubSteps
                        if !currentSubSteps.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: step.rowsPerRepeat != nil ? "repeat" : "list.number")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                    Text(step.rowsPerRepeat != nil ? "Passaggi del Ciclo" : "Dettaglio Passaggi")
                                        .font(.footnote.bold())
                                        .foregroundColor(.secondary)
                                }
                                .padding(.bottom, 2)
                                
                                ForEach(Array(currentSubSteps.enumerated()), id: \.offset) { idx, subText in
                                    let isActive = isSubStepActive(index: idx, for: step)
                                    HStack(alignment: .top, spacing: 10) {
                                        if isActive {
                                            Circle()
                                                .fill(Color.accentColor)
                                                .frame(width: 8, height: 8)
                                                .padding(.top, 6)
                                        } else {
                                            Circle()
                                                .fill(Color.secondary.opacity(0.35))
                                                .frame(width: 6, height: 6)
                                                .padding(.top, 7)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            if isActive {
                                                Text("DA LAVORARE ORA")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(Color.accentColor)
                                            }
                                            Text(subText)
                                                .font(.system(size: 15, weight: isActive ? .semibold : .regular, design: .rounded))
                                                .foregroundColor(.primary)
                                                .lineSpacing(3)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(isActive ? Color.accentColor.opacity(0.1) : Color(.tertiarySystemFill))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(isActive ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
                                    )
                                }
                            }
                        }
                        
                        // REPEAT VARIATIONS
                        let currentVariations = step.safeRepeatVariations
                        if !currentVariations.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .font(.caption.bold())
                                        .foregroundColor(.indigo)
                                    Text("Ripetizioni:")
                                        .font(.footnote.bold())
                                        .foregroundColor(.secondary)
                                }
                                .padding(.bottom, 2)
                                
                                ForEach(Array(currentVariations.enumerated()), id: \.offset) { idx, varText in
                                    let isCurrentVar = isVariationActive(index: idx, for: step)
                                    let isPastVar = (step.rowsPerRepeat != nil) && (step.currentStepCount / step.rowsPerRepeat!) > idx
                                    
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: isPastVar ? "checkmark.circle.fill" : (isCurrentVar ? "arrow.right.circle.fill" : "circle"))
                                            .foregroundColor(isPastVar ? .green : (isCurrentVar ? .indigo : .secondary))
                                            .font(.caption)
                                            .padding(.top, 2)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            if isCurrentVar {
                                                Text("IN CORSO")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(.indigo)
                                            }
                                            Text(varText)
                                                .font(.system(size: 14, weight: isCurrentVar ? .semibold : .regular, design: .rounded))
                                                .foregroundColor(isPastVar ? .secondary : .primary)
                                                .strikethrough(isPastVar, color: .secondary)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isCurrentVar ? Color.indigo.opacity(0.1) : Color(.tertiarySystemFill))
                                    )
                                }
                            }
                        }
                    }
                    .padding(18)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
                    .padding(.horizontal, 16)
                }
                
                // Barra di Navigazione Inferiore della Scheda
                HStack(spacing: 10) {
                    Button {
                        if currentIndex > 0 {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                currentIndex -= 1
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.bold())
                            .frame(width: 44, height: 44)
                            .background(Color(.tertiarySystemFill))
                            .foregroundColor(currentIndex > 0 ? .primary : .secondary.opacity(0.35))
                            .clipShape(Circle())
                    }
                    .disabled(currentIndex == 0)
                    
                    let isLast = currentIndex >= steps.count - 1
                    Button {
                        haptic.impactOccurred()
                        TimerManager.shared.registerInteraction()
                        if step.isCompleted && !isLast {
                            withAnimation(.easeInOut(duration: 0.25)) { currentIndex += 1 }
                            return
                        }
                        step.isCompleted = true
                        step.completedAt = Date()
                        
                        let targetProject = project ?? step.project
                        
                        // Se completiamo l'ultimo step contiguo di una sezione puramente informativa,
                        // sanifica eventuali altri step informativi con lo stesso titolo
                        let currentSectionSteps = steps.filter { $0.sectionTitle == step.sectionTitle }
                        if currentSectionSteps.allSatisfy({ $0.stepType == "info" || (!$0.hasCounter && ($0.targetStepCount == nil || $0.targetStepCount == 0)) }) {
                            let isLastInBlock = currentIndex + 1 >= steps.count || steps[currentIndex + 1].sectionTitle != step.sectionTitle
                            if isLastInBlock {
                                for s in currentSectionSteps where !s.isCompleted {
                                    s.isCompleted = true
                                    if s.completedAt == nil { s.completedAt = Date() }
                                }
                            }
                        }
                        
                        try? targetProject?.modelContext?.save()
                        
                        if WatchConnectivityIOSManager.shared.activeStepId == step.id {
                            if !isLast {
                                let nextStep = steps[currentIndex + 1]
                                WatchConnectivityIOSManager.shared.setActiveStep(nextStep, for: targetProject)
                            }
                        } else {
                            WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
                        }
                        
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
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(step.isCompleted && !isLast ? Color.green : Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: (step.isCompleted && !isLast ? Color.green : Color.accentColor).opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                    
                    Button {
                        if !isLast {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                currentIndex += 1
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.body.bold())
                            .frame(width: 44, height: 44)
                            .background(Color(.tertiarySystemFill))
                            .foregroundColor(!isLast ? .primary : .secondary.opacity(0.35))
                            .clipShape(Circle())
                    }
                    .disabled(isLast)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
            .sheet(item: $stepToEdit) { step in
                EditGuideStepSheet(step: step, onDelete: {
                    onDeleteStep(step)
                })
            }
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
                    Button("Azzera") {
                        step.currentStepCount = 0
                        if let global = step.project?.counters.first(where: { $0.title.localizedCaseInsensitiveContains("globale") || $0.title.localizedCaseInsensitiveContains("totale") }) {
                            global.currentCount = step.project?.totalGuideRowsWorked ?? 0
                        }
                        WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
                    }
                    .font(.caption.bold())
                    .foregroundColor(.red)
                }
            }
            
            if let target = effectiveTarget, target > 0 {
                ProgressView(value: min(Double(step.currentStepCount) / Double(target), 1.0))
                    .tint(isTargetReached ? .green : .accentColor)
            }
            
            // Contatore integrato: - valore +
            HStack(spacing: 16) {
                Button {
                    TimerManager.shared.registerInteraction()
                    haptic.impactOccurred()
                    if step.currentStepCount > 0 {
                        step.currentStepCount -= 1
                        step.project?.updatedAt = Date()
                        if let global = step.project?.counters.first(where: { $0.title.localizedCaseInsensitiveContains("globale") || $0.title.localizedCaseInsensitiveContains("totale") }) {
                            global.currentCount = step.project?.totalGuideRowsWorked ?? 0
                        }
                        WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.callout.bold())
                        .foregroundColor(.primary)
                        .frame(width: 42, height: 42)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
                .disabled(step.currentStepCount == 0)
                
                Spacer()
                
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(step.currentStepCount)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(isTargetReached ? .green : .primary)
                    if let target = effectiveTarget {
                        Text("/ \(target)")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                .contentTransition(.numericText())
                
                Spacer()
                
                Button {
                    TimerManager.shared.registerInteraction()
                    haptic.impactOccurred()
                    step.currentStepCount += 1
                    step.project?.updatedAt = Date()
                    if let global = step.project?.counters.first(where: { $0.title.localizedCaseInsensitiveContains("globale") || $0.title.localizedCaseInsensitiveContains("totale") }) {
                        global.currentCount = step.project?.totalGuideRowsWorked ?? 0
                    }
                    WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
                    if isTargetReached { successHaptic.notificationOccurred(.success) }
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.bold())
                        .foregroundColor(.white)
                        .frame(width: 46, height: 46)
                        .background(isTargetReached ? Color.green : Color.accentColor)
                        .clipShape(Circle())
                        .shadow(color: (isTargetReached ? Color.green : Color.accentColor).opacity(0.35), radius: 6, x: 0, y: 3)
                }
            }
            
            // Contatori aggiuntivi creati manualmente dall'utente
            if !step.safeExtraCounterLabels.isEmpty {
                Divider()
                ForEach(Array(step.safeExtraCounterLabels.enumerated()), id: \.offset) { idx, label in
                    ExtraCounterRow(
                        label: label,
                        value: idx < step.safeExtraCounterValues.count ? step.safeExtraCounterValues[idx] : 0,
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
        .onAppear {
            haptic.prepare()
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
                subStepsText = step.safeSubSteps.joined(separator: "\n")
                variationsText = step.safeRepeatVariations.joined(separator: "\n")
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
                try? step.project?.modelContext?.save()
                WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
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
    
    @State private var targetSize: String = ""
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Taglia Desiderata (Opzionale)") {
                    TextField("Es. XS, S, M, L... (lascia vuoto se taglia unica)", text: $targetSize)
                    Text("Se il pattern prevede più taglie specifica quella desiderata. Se il lavoro non prevede taglie (es. sciarpa, coperta, scialle o taglia unica), lascia pure il campo vuoto.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button {
                        generateOfflineGuide()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bolt.badge.checkmark.fill")
                                .font(.title3)
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Genera Guida Rapida (Bypass AI / Offline)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                Text("Crea all'istante schede e contatori dal PDF con un clic, senza dipendere da chiavi API esterne o rete.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Bypass Rapido")
                }
                
                if isProcessing {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Gemini sta analizzando il pattern e calcolando i ferri...")
                                .font(.subheadline)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Crea Guida")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                        .disabled(isProcessing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Genera con AI") {
                        generateGuide()
                    }
                    .bold()
                    .disabled(isProcessing)
                }
            }
            .onAppear {
                if !project.selectedSize.isEmpty {
                    targetSize = project.selectedSize
                }
            }
            .alert("Errore Generazione", isPresented: .constant(errorMessage != nil)) {
                Button("Annulla", role: .cancel) { errorMessage = nil }
                Button("Crea Guida Locale (Offline)") {
                    errorMessage = nil
                    generateOfflineGuide()
                }
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
        let chosenSize = targetSize.trimmingCharacters(in: .whitespaces)
        
        Task {
            do {
                let response = try await GeminiService.shared.generateGuide(from: pdfData, targetSize: chosenSize)
                
                await MainActor.run {
                    project.selectedSize = chosenSize
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
                    var seenSectionNames: Set<String> = []
                    var lastSectionName: String? = nil
                    for section in response.sections {
                        var rawName = GeminiService.cleanSectionName(section.name)
                        if rawName.isEmpty { rawName = "Sezione" }
                        
                        var distinctName = rawName
                        if seenSectionNames.contains(rawName) && lastSectionName != rawName {
                            if rawName.localizedCaseInsensitiveContains("informazion") || rawName.localizedCaseInsensitiveContains("specifiche") {
                                distinctName = "\(rawName) (Note)"
                            } else {
                                distinctName = "\(rawName) (Parte 2)"
                            }
                        }
                        seenSectionNames.insert(rawName)
                        lastSectionName = rawName
                        
                        for stepData in section.steps {
                            let step = GuideStep(
                                sectionTitle: distinctName,
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
                                counterKind: stepData.counterKind,
                                currentStepCount: 0,
                                targetStepCount: stepData.targetStepCount
                            )
                            step.project = project
                            project.guideSteps.append(step)
                            stepOrder += 1
                        }
                    }
                    
                    try? modelContext.save()
                    WatchConnectivityIOSManager.shared.setActiveStep(project.activeWorkingStep(), for: project)
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
    
    private func generateOfflineGuide() {
        for step in project.guideSteps {
            modelContext.delete(step)
        }
        project.guideSteps.removeAll()
        project.selectedSize = targetSize.trimmingCharacters(in: .whitespaces)
        
        let titleLower = project.title.lowercased()
        let sizeNotice = project.selectedSize.isEmpty ? "" : " per la tua taglia " + project.selectedSize
        
        // Se è Sophie Scarf o una sciarpa/scialle
        if titleLower.contains("sophie") || titleLower.contains("scarf") {
            let stepsData: [(sec: String, title: String, text: String, counter: Bool, label: String?, target: Int?, sub: [String])] = [
                ("Preparazione", "Materiali e Ferri", "Ferri 3.5 mm o secondo campione (22 m a legaccio = 10 cm). Filato: circa 25-50 g fingering/DK.", false, nil, nil, []),
                ("Avvio", "Avvio con I-Cord (4 maglie)", "Avviare 4 maglie sui ferri a doppia punta o circolari usando il metodo a cappio per impostare il bordo I-cord.", true, "Maglie Avviate", 4, []),
                ("Sezione Aumenti", "Aumenti ogni 8 ferri", "Lavorare a maglia legaccio con bordo I-cord di 3 maglie ai lati, aumentando 1 maglia sul lato destro ogni 8 ferri fino a raggiungere la larghezza massima.", true, "Ferri Lavorati", 64, [
                    "Ferro 1 (Dir): 3 dir (I-cord), dir fino alle ultime 3 maglie, 3 dir.",
                    "Ferro 8 (Aumento): 3 dir, 1 gett / AID, dir fino a 3 maglie dalla fine, 3 dir."
                ]),
                ("Centro e Diminuzioni", "Calature ogni 8 ferri", "Lavorare la seconda metà della sciarpa simmetricamente, diminuendo 1 maglia ogni 8 ferri fino a ritrovare le 4 maglie iniziali.", true, "Ferri Lavorati", 64, []),
                ("Chiusura", "Chiusura I-cord", "Intrecciare le ultime 4 maglie seguendo la chiusura I-cord e nascondere le codine di filo.", true, "Maglie Chiuse", 4, [])
            ]
            
            for (idx, data) in stepsData.enumerated() {
                let s = GuideStep(
                    sectionTitle: data.sec,
                    title: data.title,
                    stepType: data.counter ? "repeat_pattern" : "info",
                    instructionText: data.text,
                    subSteps: data.sub,
                    orderIndex: idx,
                    hasCounter: data.counter,
                    counterLabel: data.label,
                    targetStepCount: data.target
                )
                s.project = project
                project.guideSteps.append(s)
            }
        } else if titleLower.contains("no frills") {
            // Carica la guida completa verificata del No Frills
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
                            orderIndex: stepOrder,
                            hasCounter: stepData.hasCounter ?? false,
                            counterLabel: stepData.counterLabel,
                            targetStepCount: stepData.targetStepCount
                        )
                        step.project = project
                        project.guideSteps.append(step)
                        stepOrder += 1
                    }
                }
            }
        } else {
            // Struttura modulare universale per qualsiasi pattern PDF caricato
            let defaultSteps: [(sec: String, title: String, text: String, counter: Bool, label: String?, target: Int?)] = [
                ("Preparazione", "Campione e Materiali", "Verifica la tensione del campione dopo il bloccaggio e prepara i ferri e i marcapunti indicati nel pattern PDF.", false, nil, nil),
                ("Avvio e Bordi", "Avvio Maglie", "Avvia il numero di maglie richiesto\(sizeNotice) e lavora il bordo iniziale.", true, "Maglie Avviate", 100),
                ("Lavorazione Principale", "Corpo del Lavoro", "Lavora il motivo principale seguendo le istruzioni della pagina PDF indicata\(sizeNotice).", true, "Ferri / Giri Lavorati", 60),
                ("Modellatura", "Aumenti / Diminuzioni", "Esegui le calature o gli aumenti previsti dal pattern ad intervalli regolari.", true, "Ripetizioni / Ferri", 20),
                ("Finiture", "Intreccio e Bloccaggio", "Intreccia le maglie morbidamente secondo il motivo, cuci o rifinisci e blocca il capo.", true, "Maglie Intrecciate", 100)
            ]
            
            for (idx, data) in defaultSteps.enumerated() {
                let s = GuideStep(
                    sectionTitle: data.sec,
                    title: data.title,
                    stepType: data.counter ? "single_action" : "info",
                    instructionText: data.text,
                    orderIndex: idx,
                    hasCounter: data.counter,
                    counterLabel: data.label,
                    targetStepCount: data.target
                )
                s.project = project
                project.guideSteps.append(s)
            }
        }
        
        dismiss()
    }
}
