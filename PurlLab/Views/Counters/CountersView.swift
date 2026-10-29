import SwiftUI
import SwiftData

struct CountersView: View {
    @Bindable var project: KnittingProject
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddCounterSheet = false
    
    // Scheda operativa attiva (sincronizzata con Apple Watch e Guida)
    private var activeStep: GuideStep? {
        project.activeWorkingStep(preferredStepId: WatchConnectivityIOSManager.shared.activeStepId)
    }
    
    var body: some View {
        Group {
            if project.isDeleted || project.modelContext == nil {
                Color.clear
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // MARK: - 1. HERO: STATISTICHE GLOBALI DI PROGETTO
                        GlobalProjectStatsCard(project: project)
                        
                        // MARK: - 2. SEZIONE ATTUALMENTE IN LAVORAZIONE
                        if let step = activeStep {
                            ActiveSectionCounterCard(project: project, step: step)
                        } else if let mainCounter = project.counters.first(where: { $0.title.localizedCaseInsensitiveContains("globale") }) ?? project.counters.first {
                            CounterCardView(counter: mainCounter) {
                                deleteCounter(mainCounter)
                            }
                        }
                        
                        // MARK: - 3. PANORAMICA SEZIONI DELLA GUIDA
                        if !project.guideSteps.isEmpty {
                            GuideSectionsProgressCard(project: project)
                        }
                        
                        // MARK: - 4. CONTATORI ACCESSORI PERSONALIZZATI
                        CustomCountersSection(
                            project: project,
                            onAddCounter: { showingAddCounterSheet = true },
                            onDeleteCounter: { counter in deleteCounter(counter) }
                        )
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .sheet(isPresented: $showingAddCounterSheet) {
                    AddCounterSheet(project: project)
                }
                .onAppear {
                    WatchConnectivityIOSManager.shared.setActiveProject(project)
                }
            }
        }
    }
    
    private func deleteCounter(_ counter: RowCounter) {
        if let index = project.counters.firstIndex(where: { $0.id == counter.id }) {
            project.counters.remove(at: index)
            modelContext.delete(counter)
            WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
        }
    }
}

// MARK: - 1. Hero Card: Statistiche Globali (Maglie Lavorate, Ferri Totali, Progresso)
struct GlobalProjectStatsCard: View {
    let project: KnittingProject
    
    var body: some View {
        VStack(spacing: 16) {
            // Header Card
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.indigo)
                    Text("Avanzamento Globale del Lavoro")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                }
                Spacer()
                
                let progressPercent = Int(round(project.globalProgress * 100))
                Text("\(progressPercent)%")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundColor(progressPercent >= 100 ? .green : .indigo)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.indigo.opacity(0.12))
                    .clipShape(Capsule())
            }
            
            // Griglia: Totale Maglie Lavorate & Totale Ferri
            HStack(spacing: 12) {
                // Maglie Lavorate Totali
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.grid.cross.fill")
                            .font(.caption)
                            .foregroundColor(.indigo)
                        Text("Maglie Lavorate")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }
                    
                    Text("\(project.totalStitchesWorked)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundColor(.indigo)
                        .contentTransition(.numericText())
                    
                    if let targetSts = project.targetTotalStitches, targetSts > 0 {
                        Text("su ca. \(targetSts) stimate")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("totale cumulativo")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.indigo.opacity(0.08))
                .cornerRadius(16)
                
                // Contatore Globale
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "number.circle.fill")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.850, green: 0.350, blue: 0.550))
                        Text("Contatore Globale")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }
                    
                    Text("\(project.totalGuideRowsWorked)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundColor(Color(red: 0.850, green: 0.350, blue: 0.550))
                        .contentTransition(.numericText())
                    
                    if let targetRows = project.targetTotalRows, targetRows > 0 {
                        Text("su \(targetRows) ferri previsti")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("in tutte le sezioni")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(red: 0.850, green: 0.350, blue: 0.550).opacity(0.08))
                .cornerRadius(16)
            }
            
            // Barra di Progresso Globale
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: project.globalProgress)
                    .tint(.indigo)
                    .scaleEffect(y: 1.4, anchor: .center)
            }
            
            // Informazioni aggiuntive: Tempo e Velocità di Lavoro
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text("Tempo: \(formatHours(project.totalSecondsWorked))")
                        .font(.caption.monospacedDigit())
                }
                .foregroundColor(.secondary)
                
                Spacer()
                
                if project.totalSecondsWorked >= 60 && project.totalStitchesWorked > 0 {
                    let stitchesPerMinute = Double(project.totalStitchesWorked) / (project.totalSecondsWorked / 60.0)
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                            .font(.caption)
                        Text(String(format: "%.1f m/min", stitchesPerMinute))
                            .font(.caption.bold())
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    private func formatHours(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) min"
        }
    }
}

// MARK: - 2. Card: Sezione Attualmente in Lavorazione (In Sync con Watch)
struct ActiveSectionCounterCard: View {
    let project: KnittingProject
    @Bindable var step: GuideStep
    
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private let successHaptic = UINotificationFeedbackGenerator()
    
    private var isTargetReached: Bool {
        if let target = step.targetStepCount, target > 0 {
            return step.currentStepCount >= target
        }
        return false
    }
    
    var body: some View {
        if step.isDetachedOrDeleted {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                headerRow
                stitchesBadge
                progressSection
                counterButtonsRow
            }
            .padding(18)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        }
    }
    
    @ViewBuilder
    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: "applewatch")
                        .font(.caption2)
                    Text("In sincronizzazione")
                        .font(.caption2.weight(.medium))
                }
                .foregroundColor(.secondary)
                
                Text(step.sectionTitle)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if !step.title.isEmpty {
                    Text(step.title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if step.currentStepCount > 0 {
                Button("Azzera") {
                    step.currentStepCount = 0
                    syncChanges()
                }
                .font(.caption.bold())
                .foregroundColor(.red)
            }
        }
    }
    
    @ViewBuilder
    private var stitchesBadge: some View {
        if let before = step.stitchCountBefore, let after = step.stitchCountAfter, before != after {
            let diff = after - before
            let diffStr = diff > 0 ? "+\(diff)" : "\(diff)"
            HStack(spacing: 6) {
                Image(systemName: "circle.grid.cross.fill")
                    .font(.caption2)
                Text("\(before) → \(after) maglie (\(diffStr))")
                    .font(.caption.bold())
            }
            .foregroundColor(.indigo)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.indigo.opacity(0.1))
            .clipShape(Capsule())
        } else if let sts = step.stitchCountAfter ?? step.stitchCountBefore, sts > 0 {
            HStack(spacing: 6) {
                Image(systemName: "circle.grid.cross.fill")
                    .font(.caption2)
                Text("\(sts) maglie sul ferro")
                    .font(.caption.bold())
            }
            .foregroundColor(.indigo)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.indigo.opacity(0.1))
            .clipShape(Capsule())
        }
    }
    
    @ViewBuilder
    private var progressSection: some View {
        if let target = step.targetStepCount, target > 0 {
            let progress = min(Double(step.currentStepCount) / Double(target), 1.0)
            ProgressView(value: progress)
                .tint(isTargetReached ? .green : Color(red: 0.850, green: 0.350, blue: 0.550))
        }
    }
    
    @ViewBuilder
    private var counterButtonsRow: some View {
        HStack(spacing: 16) {
            Button {
                haptic.impactOccurred()
                if step.currentStepCount > 0 {
                    step.currentStepCount -= 1
                    syncChanges()
                }
            } label: {
                Image(systemName: "minus")
                    .font(.callout.bold())
                    .frame(width: 42, height: 42)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
                    .foregroundColor(.primary)
            }
            .disabled(step.currentStepCount == 0)
            
            Spacer()
            
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(step.currentStepCount)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(isTargetReached ? .green : .primary)
                        .contentTransition(.numericText())
                    
                    if let target = step.targetStepCount, target > 0 {
                        Text("/ \(target)")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(step.counterLabel?.isEmpty == false ? step.counterLabel! : "Ferri")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }
            
            Spacer()
            
            Button {
                haptic.impactOccurred()
                step.currentStepCount += 1
                syncChanges()
                if isTargetReached {
                    successHaptic.notificationOccurred(.success)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.headline.bold())
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(isTargetReached ? Color.green : Color(red: 0.850, green: 0.350, blue: 0.550))
                    .clipShape(Circle())
                    .shadow(color: (isTargetReached ? Color.green : Color(red: 0.850, green: 0.350, blue: 0.550)).opacity(0.35), radius: 6, x: 0, y: 3)
            }
        }
    }
    
    private func syncChanges() {
        if let global = project.counters.first(where: {
            $0.title.localizedCaseInsensitiveContains("globale") ||
            $0.title.localizedCaseInsensitiveContains("totale")
        }) {
            global.currentCount = project.totalGuideRowsWorked
        }
        WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
    }
}

// MARK: - 3. Card: Panoramica Avanzamento di Tutte le Sezioni
struct GuideSectionsProgressCard: View {
    let project: KnittingProject
    
    private var sortedSteps: [GuideStep] {
        project.guideSteps.sorted(by: { $0.orderIndex < $1.orderIndex })
    }
    
    private var sectionsSummary: [(title: String, worked: Int, target: Int?, isComplete: Bool, stitches: Int?)] {
        var orderedTitles: [String] = []
        for step in sortedSteps {
            if !orderedTitles.contains(step.sectionTitle) {
                orderedTitles.append(step.sectionTitle)
            }
        }
        
        return orderedTitles.map { title in
            let steps = sortedSteps.filter { $0.sectionTitle == title }
            let worked = steps.reduce(0) { $0 + $1.currentStepCount }
            let target = steps.compactMap { $0.targetStepCount }.reduce(0, +)
            let isComplete = steps.allSatisfy { $0.isCompleted }
            let lastStitch = steps.compactMap { $0.stitchCountAfter ?? $0.stitchCountBefore }.last
            return (title, worked, target > 0 ? target : nil, isComplete, lastStitch)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Avanzamento Sezioni")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Text("\(sectionsSummary.filter { $0.isComplete }.count) di \(sectionsSummary.count) completate")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 10) {
                ForEach(sectionsSummary, id: \.title) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(item.isComplete ? .green : .secondary)
                            .font(.subheadline)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            if let sts = item.stitches {
                                Text("\(sts) maglie sul ferro")
                                    .font(.caption2)
                                    .foregroundColor(.indigo)
                            }
                        }
                        
                        Spacer()
                        
                        if let target = item.target {
                            Text("\(item.worked)/\(target) f")
                                .font(.caption.monospacedDigit().bold())
                                .foregroundColor(item.worked >= target ? .green : .secondary)
                        } else if item.worked > 0 {
                            Text("\(item.worked) f")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    if item.title != sectionsSummary.last?.title {
                        Divider()
                    }
                }
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

// MARK: - 4. Sezione: Contatori Personalizzati Aggiuntivi
struct CustomCountersSection: View {
    let project: KnittingProject
    var onAddCounter: () -> Void
    var onDeleteCounter: (RowCounter) -> Void
    
    // Escludiamo il contatore globale di sistema se già visualizzato nella hero
    private var customCounters: [RowCounter] {
        project.counters.filter { counter in
            !counter.title.localizedCaseInsensitiveContains("globale") &&
            !counter.title.localizedCaseInsensitiveContains("ferri principali") &&
            counter.title.localizedCaseInsensitiveCompare("ferro") != .orderedSame &&
            counter.title.localizedCaseInsensitiveCompare("ferri") != .orderedSame
        }.sorted(by: { $0.orderIndex < $1.orderIndex })
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Contatori Personalizzati")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Button {
                    onAddCounter()
                } label: {
                    Label("Aggiungi", systemImage: "plus")
                        .font(.caption.bold())
                }
            }
            
            if customCounters.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Nessun contatore personalizzato")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Puoi creare contatori manuali per seguire ripetizioni di trecce, coste o aumenti.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(16)
            } else {
                ForEach(customCounters) { counter in
                    CounterCardView(counter: counter) {
                        onDeleteCounter(counter)
                    }
                }
            }
        }
    }
}

// MARK: - Card per singolo RowCounter manuale
struct CounterCardView: View {
    @Bindable var counter: RowCounter
    var onDelete: () -> Void
    
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private let successHaptic = UINotificationFeedbackGenerator()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(counter.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let target = counter.targetCount, target > 0 {
                        Text("Obiettivo: \(target) ferri")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Menu {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Elimina", systemImage: "trash")
                    }
                    Button {
                        counter.reset()
                        WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
                    } label: {
                        Label("Azzera", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
            
            // Progress Bar if target exists
            if let target = counter.targetCount, target > 0 {
                let progress = min(Double(counter.currentCount) / Double(target), 1.0)
                ProgressView(value: progress)
                    .tint(progress >= 1.0 ? .green : .accentColor)
            }
            
            // Number & Action Controls
            HStack(spacing: 16) {
                // Decrement Button
                Button {
                    TimerManager.shared.registerInteraction()
                    haptic.impactOccurred()
                    counter.decrement()
                    WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
                } label: {
                    Image(systemName: "minus")
                        .font(.callout.bold())
                        .frame(width: 42, height: 42)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
                .disabled(counter.currentCount == 0)
                
                Spacer()
                
                // Count Display
                Text("\(counter.currentCount)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(isAtTarget ? .green : .primary)
                    .contentTransition(.numericText())
                
                Spacer()
                
                // Big Increment Button
                Button {
                    TimerManager.shared.registerInteraction()
                    haptic.impactOccurred()
                    counter.increment()
                    WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
                    if isAtTarget {
                        successHaptic.notificationOccurred(.success)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.bold())
                        .foregroundColor(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 6, x: 0, y: 3)
                }
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        .onAppear {
            haptic.prepare()
        }
    }
    
    private var isAtTarget: Bool {
        if let target = counter.targetCount, target > 0 {
            return counter.currentCount >= target
        }
        return false
    }
}

// MARK: - Foglio Aggiungi Contatore
struct AddCounterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var project: KnittingProject
    
    @State private var title = "Ferri"
    @State private var hasTarget = false
    @State private var targetCount = 10
    @State private var stepIncrement = 1
    @State private var resetOnTarget = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Dettagli Contatore") {
                    TextField("Nome (es. Manica, Aumenti, Trecce)", text: $title)
                    Stepper("Incremento: +\(stepIncrement)", value: $stepIncrement, in: 1...10)
                }
                
                Section("Obiettivo") {
                    Toggle("Imposta un obiettivo", isOn: $hasTarget)
                    if hasTarget {
                        Stepper("Obiettivo: \(targetCount) ferri", value: $targetCount, in: 1...999)
                        Toggle("Azzera automaticamente all'obiettivo", isOn: $resetOnTarget)
                    }
                }
            }
            .navigationTitle("Nuovo Contatore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        let counter = RowCounter(
                            title: title.isEmpty ? "Ferri" : title,
                            targetCount: hasTarget ? targetCount : nil,
                            stepIncrement: stepIncrement,
                            resetOnTarget: resetOnTarget,
                            orderIndex: project.counters.count
                        )
                        counter.project = project
                        project.counters.append(counter)
                        WatchConnectivityIOSManager.shared.syncAllProjectsToWatch()
                        dismiss()
                    }
                }
            }
        }
    }
}
