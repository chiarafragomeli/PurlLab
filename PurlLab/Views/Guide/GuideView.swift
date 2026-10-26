import SwiftUI
import SwiftData

enum GuideDisplayMode: String, CaseIterable {
    case card = "Card Singola"
    case list = "Elenco"
}

struct GuideView: View {
    @Bindable var project: KnittingProject
    @Environment(\.modelContext) private var modelContext
    var onSelectPdfPage: (Int) -> Void
    
    @State private var displayMode: GuideDisplayMode = .card
    @State private var currentStepIndex: Int = 0
    @State private var showingGenerateSheet = false
    @State private var errorMessage: String?
    
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
                        Text("Carica la guida del No Frills Sweater o generane una nuova da PDF con Gemini.")
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
                                showingGenerateSheet = true
                            } label: {
                                Label("Genera con Gemini AI", systemImage: "brain")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(project.pdfData == nil)
                        }
                        .padding(.horizontal, 24)
                    }
                } else {
                    VStack(spacing: 0) {
                        // Picker visualizzazione Card / Elenco
                        Picker("Modalità", selection: $displayMode) {
                            ForEach(GuideDisplayMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        
                        if displayMode == .card {
                            // Modalità Scheda Singola (Focus Mode alla LooseLoop)
                            GuideSingleCardView(
                                steps: sortedSteps,
                                currentIndex: $currentStepIndex,
                                onNavigateToPage: onSelectPdfPage
                            )
                        } else {
                            // Modalità Elenco Completo
                            List {
                                ForEach(orderedSections) { group in
                                    Section(header: Text(group.title).font(.headline)) {
                                        ForEach(group.steps) { step in
                                            GuideStepRow(step: step) { page in
                                                onSelectPdfPage(page)
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
            .navigationTitle(displayMode == .card && !project.guideSteps.isEmpty ? "Guida Attiva" : "Guida Passo-Passo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !project.guideSteps.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
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
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .onAppear {
                // Posizionati automaticamente sulla prima card non completata
                if let firstIncomplete = sortedSteps.firstIndex(where: { !$0.isCompleted }) {
                    currentStepIndex = firstIncomplete
                }
            }
            .sheet(isPresented: $showingGenerateSheet) {
                GenerateGuideSheet(project: project)
            }
            .alert("Errore", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
    
    private func loadPreloadedGuide() {
        guard let guideUrl = Bundle.main.url(forResource: "NoFrillsGuide_M", withExtension: "json"),
              let guideData = try? Data(contentsOf: guideUrl),
              let guide = try? JSONDecoder().decode(GeneratedGuideResponse.self, from: guideData) else {
            errorMessage = "Guida di test non trovata nel bundle."
            return
        }
        
        project.selectedSize = "M"
        for step in project.guideSteps {
            modelContext.delete(step)
        }
        project.guideSteps.removeAll()
        
        var stepOrder = 0
        for section in guide.sections {
            for stepData in section.steps {
                let step = GuideStep(
                    sectionTitle: section.name,
                    instructionText: stepData.instruction,
                    stitchCountAfter: stepData.stitchCountAfter,
                    targetMeasureCm: stepData.targetMeasureCm,
                    sourcePage: stepData.sourcePage,
                    sourceQuote: stepData.sourceQuote,
                    orderIndex: stepOrder,
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

// MARK: - Vista Card Singola con Contatore Integrato (Focus Mode)
struct GuideSingleCardView: View {
    let steps: [GuideStep]
    @Binding var currentIndex: Int
    var onNavigateToPage: (Int) -> Void
    
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private let successHaptic = UINotificationFeedbackGenerator()
    
    var currentStep: GuideStep? {
        guard !steps.isEmpty, currentIndex >= 0, currentIndex < steps.count else { return nil }
        return steps[currentIndex]
    }
    
    var body: some View {
        if let step = currentStep {
            VStack(spacing: 16) {
                // Indicatore di progresso in alto
                VStack(spacing: 6) {
                    HStack {
                        Text(step.sectionTitle.uppercased())
                            .font(.caption.bold())
                            .foregroundColor(.accentColor)
                        
                        Spacer()
                        
                        Text("Passo \(currentIndex + 1) di \(steps.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    
                    ProgressView(value: Double(currentIndex + 1), total: Double(steps.count))
                        .tint(.accentColor)
                }
                .padding(.horizontal, 20)
                
                // La Card Principale
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Badge superiore
                        HStack {
                            if let page = step.sourcePage {
                                Button {
                                    onNavigateToPage(page)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.text")
                                        Text("PDF Pagina \(page)")
                                    }
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundColor(.orange)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Spacer()
                            
                            if step.isCompleted {
                                Label("Completato", systemImage: "checkmark.circle.fill")
                                    .font(.caption.bold())
                                    .foregroundColor(.green)
                            }
                        }
                        
                        // Testo Istruzione
                        Text(step.instructionText)
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .lineSpacing(6)
                            .foregroundColor(.primary)
                        
                        // Metriche di riferimento
                        HStack(spacing: 12) {
                            if let sts = step.stitchCountAfter {
                                Label("\(sts) maglie totali", systemImage: "number")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            
                            if let measure = step.targetMeasureCm {
                                Label("Misura: \(String(format: "%.1f", measure)) cm", systemImage: "ruler")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.purple)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.purple.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        // SEZIONE CONTATORE INTEGRATO NELLA CARD
                        CardCounterBoxView(step: step)
                    }
                    .padding(22)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(24)
                    .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
                    .padding(.horizontal, 16)
                }
                
                // Barra di Navigazione Inferiore
                HStack(spacing: 14) {
                    // Pulsante Precedente
                    Button {
                        if currentIndex > 0 {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                currentIndex -= 1
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Indietro")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6))
                        .foregroundColor(currentIndex > 0 ? .primary : .secondary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(currentIndex == 0)
                    
                    // Pulsante Completa / Prossimo
                    Button {
                        haptic.impactOccurred()
                        step.isCompleted = true
                        if currentIndex < steps.count - 1 {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                currentIndex += 1
                            }
                        } else {
                            successHaptic.notificationOccurred(.success)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(currentIndex < steps.count - 1 ? "Completato e Avanti" : "Finito!")
                            Image(systemName: currentIndex < steps.count - 1 ? "chevron.right" : "sparkles")
                        }
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 6, x: 0, y: 3)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }
}

// MARK: - Box Contatore Speciale della Card
struct CardCounterBoxView: View {
    @Bindable var step: GuideStep
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private let successHaptic = UINotificationFeedbackGenerator()
    
    var effectiveTarget: Int? {
        if let target = step.targetStepCount, target > 0 {
            return target
        }
        if step.instructionText.lowercased().contains("avviare") || step.instructionText.lowercased().contains("avvia"),
           let sts = step.stitchCountAfter {
            return sts
        }
        return nil
    }
    
    var isTargetReached: Bool {
        if let target = effectiveTarget {
            return step.currentStepCount >= target
        }
        return false
    }
    
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(counterTitle)
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                    
                    if let target = effectiveTarget {
                        Text("Obiettivo: \(target)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if step.currentStepCount > 0 {
                    Button("Azzera") {
                        step.currentStepCount = 0
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            
            // Barra di avanzamento contatore
            if let target = effectiveTarget {
                let progress = min(Double(step.currentStepCount) / Double(target), 1.0)
                ProgressView(value: progress)
                    .tint(isTargetReached ? .green : .accentColor)
            }
            
            // Display Contatore e Tasti - e +
            HStack(spacing: 24) {
                // Tasto Meno
                Button {
                    TimerManager.shared.registerInteraction()
                    haptic.impactOccurred()
                    if step.currentStepCount > 0 {
                        step.currentStepCount -= 1
                    }
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
                
                // Numero
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(step.currentStepCount)")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundColor(isTargetReached ? .green : .primary)
                    
                    if let target = effectiveTarget {
                        Text("/ \(target)")
                            .font(.title2.bold())
                            .foregroundColor(.secondary)
                    }
                }
                .contentTransition(.numericText())
                
                Spacer()
                
                // Tasto Più Gigante
                Button {
                    TimerManager.shared.registerInteraction()
                    haptic.impactOccurred()
                    step.currentStepCount += 1
                    if isTargetReached {
                        successHaptic.notificationOccurred(.success)
                    }
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
        }
        .padding(16)
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(18)
    }
    
    private var counterTitle: String {
        let txt = step.instructionText.lowercased()
        if txt.contains("avviare") || txt.contains("avvia") {
            return "Contatore Maglie Avviate"
        } else if txt.contains("aumenti") || txt.contains("ripetere") {
            return "Contatore Ripetizioni"
        } else if txt.contains("diminuzion") || txt.contains("calatur") {
            return "Contatore Calature"
        } else {
            return "Contatore Ferri della Card"
        }
    }
}

// MARK: - Step Row per Elenco Completo
struct GuideStepRow: View {
    @Bindable var step: GuideStep
    var onNavigateToPage: (Int) -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                step.isCompleted.toggle()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(step.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(step.instructionText)
                    .font(.body)
                    .foregroundColor(step.isCompleted ? .secondary : .primary)
                    .strikethrough(step.isCompleted, color: .secondary)
                
                HStack(spacing: 8) {
                    if let sts = step.stitchCountAfter {
                        HStack(spacing: 4) {
                            Image(systemName: "number")
                            Text("\(sts) m")
                        }
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.12))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                    }
                    
                    if let measure = step.targetMeasureCm {
                        HStack(spacing: 4) {
                            Image(systemName: "ruler")
                            Text("\(String(format: "%.1f", measure)) cm")
                        }
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.12))
                        .foregroundColor(.purple)
                        .clipShape(Capsule())
                    }
                    
                    if let page = step.sourcePage {
                        Button {
                            onNavigateToPage(page)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                Text("Pag. \(page)")
                            }
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 4)
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
                    TextField("Es. S, M, L, XL, 38, 42...", text: $targetSize)
                    Text("L'AI filtrerà il pattern isolando solo le istruzioni e il conteggio maglie per questa taglia.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if isProcessing {
                    Section {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Gemini sta analizzando il pattern e creando la guida in italiano...")
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
                                sectionTitle: section.name,
                                instructionText: stepData.instruction,
                                stitchCountAfter: stepData.stitchCountAfter,
                                targetMeasureCm: stepData.targetMeasureCm,
                                sourcePage: stepData.sourcePage,
                                sourceQuote: stepData.sourceQuote,
                                orderIndex: stepOrder,
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
