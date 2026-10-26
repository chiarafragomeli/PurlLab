import SwiftUI
import SwiftData

struct GuideView: View {
    @Bindable var project: KnittingProject
    @Environment(\.modelContext) private var modelContext
    var onSelectPdfPage: (Int) -> Void
    
    @State private var showingGenerateSheet = false
    @State private var isGenerating = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Group {
                if project.guideSteps.isEmpty {
                    ContentUnavailableView {
                        Label("Nessuna Guida", systemImage: "sparkles")
                    } description: {
                        Text("Genera una guida interattiva passo-passo dal PDF del pattern con Gemini AI.")
                    } actions: {
                        Button {
                            showingGenerateSheet = true
                        } label: {
                            Text("Genera Guida con AI")
                                .bold()
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(project.pdfData == nil)
                    }
                } else {
                    List {
                        let grouped = Dictionary(grouping: project.guideSteps.sorted(by: { $0.orderIndex < $1.orderIndex })) { $0.sectionTitle }
                        
                        ForEach(grouped.keys.sorted(), id: \.self) { sectionTitle in
                            Section(header: Text(sectionTitle).font(.headline)) {
                                ForEach(grouped[sectionTitle] ?? []) { step in
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
            .navigationTitle("Guida Passo-Passo")
            .toolbar {
                if !project.guideSteps.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingGenerateSheet = true
                        } label: {
                            Label("Rigenera", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
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
}

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
                            Text("\(sts) maglie")
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
                    // Update project details
                    project.selectedSize = targetSize
                    if project.title.isEmpty || project.title == "Nuovo Progetto" {
                        project.title = response.patternTitle
                    }
                    if let designer = response.designer, !designer.isEmpty {
                        project.designer = designer
                    }
                    
                    // Replace existing guide steps
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
                                orderIndex: stepOrder
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
