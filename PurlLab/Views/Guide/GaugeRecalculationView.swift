import SwiftUI
import SwiftData

struct GaugeRecalculationView: View {
    @Bindable var project: KnittingProject
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // Campione Pattern (default 21 m x 28 f su 10 cm se non presente)
    @State private var patternStitches: Double = 21.0
    @State private var patternRows: Double = 28.0
    
    // Campione Utente (effettivo)
    @State private var userStitches: Double = 19.0
    @State private var userRows: Double = 26.0
    
    // Stati UI
    @State private var isCalculating: Bool = false
    @State private var recalculationResult: GeneratedGuideResponse?
    @State private var errorMessage: String?
    @State private var showingErrorAlert: Bool = false
    @State private var appliedSuccessfully: Bool = false
    
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private let successHaptic = UINotificationFeedbackGenerator()
    
    /// Verifica se il campione dell'utente è identico a quello del pattern
    private var isGaugeIdentical: Bool {
        abs(userStitches - patternStitches) < 0.05 && abs(userRows - patternRows) < 0.05
    }
    
    /// Rapporto maglie e ferri
    private var stitchRatio: Double { userStitches / max(1.0, patternStitches) }
    private var rowRatio: Double { userRows / max(1.0, patternRows) }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header con icona e spiegazione
                    headerCard
                    
                    // Card Campione Pattern vs Campione Utente
                    gaugeInputSection
                    
                    // Diagnosi & Valutazione in tempo reale
                    diagnosisCard
                    
                    // Risultato del ricalcolo / Anteprima
                    if let result = recalculationResult {
                        recalculationResultCard(result: result)
                    }
                    
                    // Ripristino se già ricalcolato in precedenza
                    if project.isGaugeRecalculated && recalculationResult == nil {
                        previouslyRecalculatedCard
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Adattatore Campione AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .onAppear {
                initValuesFromProject()
            }
            .alert("Errore Ricalcolo", isPresented: $showingErrorAlert) {
                Button("OK", role: .cancel) {}
                Button("Usa Ricalcolo Locale") {
                    runLocalRecalculation()
                }
            } message: {
                Text(errorMessage ?? "Si è verificato un errore imprevisto.")
            }
        }
    }
    
    // MARK: - Inizializzazione Valori
    private func initValuesFromProject() {
        if let ps = project.patternGaugeStitches, ps > 0 {
            patternStitches = ps
        } else {
            patternStitches = 21.0
        }
        
        if let pr = project.patternGaugeRows, pr > 0 {
            patternRows = pr
        } else {
            patternRows = 28.0
        }
        
        if let us = project.userGaugeStitches, us > 0 {
            userStitches = us
        } else {
            userStitches = 19.0
        }
        
        if let ur = project.userGaugeRows, ur > 0 {
            userRows = ur
        } else {
            userRows = 26.0
        }
    }
    
    // MARK: - Header
    private var headerCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)
                .padding(.top, 4)
            
            Text("Calibrazione Tensione & Campione")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            
            Text("Inserisci il campione ottenuto con il tuo filato. Se non coincide con quello del pattern, l'AI ricalcola maglie di avvio, aumenti raglan, ferri e ripetizioni per mantenere perfetta la taglia **\(project.selectedSize.isEmpty ? "M" : project.selectedSize)**.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Input Sezione Campioni
    private var gaugeInputSection: some View {
        VStack(spacing: 16) {
            // 1. Campione Pattern
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Campione del Pattern (Originale)", systemImage: "doc.text")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Spacer()
                    Text("10 × 10 cm")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(6)
                }
                
                HStack(spacing: 16) {
                    GaugeField(label: "Maglie", value: $patternStitches, unit: "m", step: 0.5)
                    GaugeField(label: "Ferri / Giri", value: $patternRows, unit: "f", step: 0.5)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(16)
            
            // 2. Il Mio Campione
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Il Mio Campione (Tensione Reale)", systemImage: "hand.raised")
                        .font(.subheadline.bold())
                        .foregroundColor(.accentColor)
                    Spacer()
                    Text("10 × 10 cm")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .cornerRadius(6)
                }
                
                HStack(spacing: 16) {
                    GaugeField(label: "Maglie", value: $userStitches, unit: "m", step: 0.5)
                    GaugeField(label: "Ferri / Giri", value: $userRows, unit: "f", step: 0.5)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(16)
        }
    }
    
    // MARK: - Diagnosi in Tempo Reale
    private var diagnosisCard: some View {
        VStack(spacing: 14) {
            if isGaugeIdentical {
                // Campione Identico
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Campione Perfetto!")
                                .font(.headline)
                                .foregroundColor(.green)
                            Text("La tensione del tuo filato coincide al 100% con il pattern (\(formatNum(patternStitches)) m × \(formatNum(patternRows)) f).")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text("Non è necessario alcun ricalcolo. Puoi lavorare il cartamodello originale con le indicazioni previste dal designer.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green.opacity(0.12))
                .cornerRadius(14)
            } else {
                // Campione Differente
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Tensione Differente Rilevata")
                            .font(.headline)
                        Spacer()
                    }
                    
                    HStack(spacing: 12) {
                        DiffPill(
                            title: "Maglie",
                            original: patternStitches,
                            actual: userStitches,
                            diffPct: (stitchRatio - 1.0) * 100,
                            unit: "m"
                        )
                        
                        DiffPill(
                            title: "Ferri",
                            original: patternRows,
                            actual: userRows,
                            diffPct: (rowRatio - 1.0) * 100,
                            unit: "f"
                        )
                    }
                    
                    Text(diagnosticExplanation)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 2)
                    
                    // Azione di Ricalcolo AI
                    Button {
                        runGeminiRecalculation()
                    } label: {
                        HStack(spacing: 8) {
                            if isCalculating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Ricalcolo con Gemini AI in corso...")
                                    .bold()
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.headline)
                                Text("Ricalcola Tutto il Pattern con AI")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isCalculating)
                    
                    // Opzione Ricalcolo Locale Istantaneo
                    Button {
                        runLocalRecalculation()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.fill")
                            Text("Ricalcola con Motore Matematico Istantaneo (Locale)")
                        }
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                    }
                    .disabled(isCalculating)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(16)
            }
        }
    }
    
    private var diagnosticExplanation: String {
        var parts: [String] = []
        if userStitches < patternStitches {
            parts.append("Il tuo filato produce meno maglie per 10 cm: senza modifiche il capo risulterebbe più largo. L'AI ridurrà le maglie avviate e le ripetizioni per preservare le misure sartoriali in cm.")
        } else if userStitches > patternStitches {
            parts.append("Il tuo filato produce più maglie per 10 cm: senza modifiche il capo risulterebbe più stretto. L'AI aumenterà proporzionalmente le maglie per garantire la vestibilità desiderata.")
        }
        if abs(userRows - patternRows) >= 0.5 {
            parts.append("I ferri verranno riadattati nelle sezioni a misura fissa e nei giri di sagomatura.")
        }
        return parts.joined(separator: " ")
    }
    
    // MARK: - Scheda Risultato Ricalcolo
    @ViewBuilder
    private func recalculationResultCard(result: GeneratedGuideResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pattern Ricalcolato con Successo!")
                        .font(.headline)
                        .foregroundColor(.green)
                    Text("Taglia \(project.selectedSize.isEmpty ? "M" : project.selectedSize) ricalibrata sul tuo campione")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            if let summary = result.recalculationSummary, !summary.isEmpty {
                Text(summary)
                    .font(.footnote)
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
            
            // Dettagli sezioni generate
            VStack(alignment: .leading, spacing: 6) {
                Text("Sezioni ricalcolate:")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                ForEach(result.sections, id: \.name) { sec in
                    HStack {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundColor(.accentColor)
                        Text(GeminiService.cleanSectionName(sec.name))
                            .font(.footnote)
                        Spacer()
                        Text("\(sec.steps.count) schede")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Bottone Applica
            Button {
                applyRecalculatedGuide(result)
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Applica Guida Ricalcolata al Progetto")
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.green.opacity(0.4), lineWidth: 1.5)
        )
    }
    
    // MARK: - Scheda Già Ricalcolato
    private var previouslyRecalculatedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.indigo)
                Text("Progetto Attualmente Ricalibrato")
                    .font(.subheadline.bold())
                Spacer()
            }
            
            if let summary = project.gaugeRecalculationSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button(role: .destructive) {
                restoreOriginalGuide()
            } label: {
                HStack {
                    Image(systemName: "arrow.uturn.backward")
                    Text("Ripristina Pattern Originale (\(formatNum(patternStitches)) m × \(formatNum(patternRows)) f)")
                }
                .font(.footnote.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Logica Esecuzione Ricalcolo
    private func runGeminiRecalculation() {
        haptic.impactOccurred()
        isCalculating = true
        errorMessage = nil
        
        let pTitle = project.title
        let pSize = project.selectedSize
        let pdf = project.pdfData
        let stepsDesc = project.guideSteps.sorted(by: { $0.orderIndex < $1.orderIndex }).map { step in
            "[\(step.sectionTitle)] \(step.title) (Tipo: \(step.stepType), Maglie prima: \(step.stitchCountBefore ?? 0), Maglie dopo: \(step.stitchCountAfter ?? 0), Ferri/Target: \(step.targetStepCount ?? 0)): \(step.instructionText)"
        }.joined(separator: "\n")
        
        let pSts = patternStitches
        let pRws = patternRows
        let uSts = userStitches
        let uRws = userRows
        
        Task {
            do {
                let response = try await GeminiService.shared.recalculateGuideForGauge(
                    patternTitle: pTitle,
                    targetSize: pSize,
                    pdfData: pdf,
                    currentStepsDescription: stepsDesc,
                    patternStitches: pSts,
                    patternRows: pRws,
                    userStitches: uSts,
                    userRows: uRws
                )
                
                await MainActor.run {
                    self.recalculationResult = response
                    self.isCalculating = false
                    self.successHaptic.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    self.isCalculating = false
                    self.errorMessage = error.localizedDescription
                    self.showingErrorAlert = true
                }
            }
        }
    }
    
    private func runLocalRecalculation() {
        haptic.impactOccurred()
        let result = GeminiService.recalculateGuideLocally(
            project: project,
            patternStitches: patternStitches,
            patternRows: patternRows,
            userStitches: userStitches,
            userRows: userRows
        )
        self.recalculationResult = result
        self.successHaptic.notificationOccurred(.success)
    }
    
    // MARK: - Applicazione al Progetto
    private func applyRecalculatedGuide(_ result: GeneratedGuideResponse) {
        haptic.impactOccurred()
        
        // Salva i parametri del campione nel progetto
        project.patternGaugeStitches = patternStitches
        project.patternGaugeRows = patternRows
        project.userGaugeStitches = userStitches
        project.userGaugeRows = userRows
        project.isGaugeRecalculated = true
        project.gaugeRecalculationSummary = result.recalculationSummary
        project.updatedAt = Date()
        
        // Rimuove i vecchi step
        for oldStep in project.guideSteps {
            modelContext.delete(oldStep)
        }
        project.guideSteps.removeAll()
        
        // Aggiunge i nuovi step ricalcolati
        var orderIndex = 0
        for section in result.sections {
            let cleanSection = GeminiService.cleanSectionName(section.name)
            for stepData in section.steps {
                let step = GuideStep(
                    sectionTitle: cleanSection,
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
                    orderIndex: orderIndex,
                    hasCounter: stepData.hasCounter ?? false,
                    counterLabel: stepData.counterLabel,
                    currentStepCount: 0,
                    targetStepCount: stepData.targetStepCount
                )
                step.project = project
                project.guideSteps.append(step)
                orderIndex += 1
            }
        }
        
        try? modelContext.save()
        successHaptic.notificationOccurred(.success)
        dismiss()
    }
    
    private func restoreOriginalGuide() {
        haptic.impactOccurred()
        
        project.isGaugeRecalculated = false
        project.gaugeRecalculationSummary = nil
        project.userGaugeStitches = nil
        project.userGaugeRows = nil
        
        // Ricarica la guida standard bundle se No Frills
        if let guideUrl = Bundle.main.url(forResource: "NoFrillsGuide_M", withExtension: "json"),
           let guideData = try? Data(contentsOf: guideUrl),
           let guide = try? JSONDecoder().decode(GeneratedGuideResponse.self, from: guideData) {
            for oldStep in project.guideSteps {
                modelContext.delete(oldStep)
            }
            project.guideSteps.removeAll()
            
            var orderIndex = 0
            for section in guide.sections {
                let cleanSection = GeminiService.cleanSectionName(section.name)
                for stepData in section.steps {
                    let step = GuideStep(
                        sectionTitle: cleanSection,
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
                        orderIndex: orderIndex,
                        hasCounter: stepData.hasCounter ?? false,
                        counterLabel: stepData.counterLabel,
                        currentStepCount: 0,
                        targetStepCount: stepData.targetStepCount
                    )
                    step.project = project
                    project.guideSteps.append(step)
                    orderIndex += 1
                }
            }
        }
        
        try? modelContext.save()
        successHaptic.notificationOccurred(.success)
        dismiss()
    }
    
    private func formatNum(_ val: Double) -> String {
        val.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(val))" : String(format: "%.1f", val)
    }
}

// MARK: - Componenti Grafici Secondari
private struct GaugeField: View {
    let label: String
    @Binding var value: Double
    let unit: String
    let step: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Text("\(formatNum(value)) \(unit)")
                    .font(.title3.monospacedDigit().bold())
                Spacer()
                Stepper("", value: $value, in: 5...60, step: step)
                    .labelsHidden()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemGroupedBackground))
            .cornerRadius(10)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func formatNum(_ val: Double) -> String {
        val.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(val))" : String(format: "%.1f", val)
    }
}

private struct DiffPill: View {
    let title: String
    let original: Double
    let actual: Double
    let diffPct: Double
    let unit: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2.bold())
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            HStack(spacing: 4) {
                Text("\(formatNum(actual))")
                    .font(.headline.bold())
                Text("vs \(formatNum(original)) \(unit)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(String(format: "%+.1f%%", diffPct))
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(diffColor.opacity(0.15))
                .foregroundColor(diffColor)
                .cornerRadius(4)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(10)
    }
    
    private var diffColor: Color {
        abs(diffPct) < 0.1 ? .green : (diffPct > 0 ? .blue : .orange)
    }
    
    private func formatNum(_ val: Double) -> String {
        val.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(val))" : String(format: "%.1f", val)
    }
}