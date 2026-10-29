import SwiftUI
import SwiftData

/// Pagina mostrata al termine della guida: riepilogo del lavoro svolto e del tempo impiegato.
struct GuideCompletionView: View {
    @Bindable var project: KnittingProject
    var onReviewGuide: () -> Void
    var onExit: () -> Void
    var onRestartFromBeginning: (() -> Void)? = nil
    
    @Environment(\.modelContext) private var modelContext
    @State private var showingRestartAlert = false
    
    private var sortedSteps: [GuideStep] {
        project.guideSteps.sorted { $0.orderIndex < $1.orderIndex }
    }
    
    private var completedCount: Int {
        sortedSteps.filter(\.isCompleted).count
    }
    
    /// Ferri/giri contati: schede con pattern ripetuto o lavorate a misura
    private func isRowCounter(_ step: GuideStep) -> Bool {
        step.rowsPerRepeat != nil || step.stepType == "work_to_measure" || step.stepType == "repeat_pattern"
    }
    
    private var rowsCounted: Int {
        sortedSteps.filter { $0.hasCounter && isRowCounter($0) }.reduce(0) { $0 + $1.currentStepCount }
    }
    
    private var stitchesCounted: Int {
        sortedSteps.filter { $0.hasCounter && !isRowCounter($0) }.reduce(0) { $0 + $1.currentStepCount }
    }
    
    private var startDate: Date {
        sortedSteps.compactMap(\.completedAt).min() ?? project.createdAt
    }
    
    private var endDate: Date {
        project.completedAt ?? Date()
    }
    
    private var daysSpan: Int {
        let cal = Calendar.current
        let d = cal.dateComponents([.day], from: cal.startOfDay(for: project.createdAt), to: cal.startOfDay(for: endDate)).day ?? 0
        return max(1, d + 1)
    }
    
    private struct SectionSummary: Identifiable {
        let id: String
        let title: String
        let total: Int
        let completed: Int
        let rows: Int
        let finalStitches: Int?
    }
    
    private var sectionSummaries: [SectionSummary] {
        var titles: [String] = []
        for s in sortedSteps where !titles.contains(s.sectionTitle) { titles.append(s.sectionTitle) }
        return titles.map { title in
            let steps = sortedSteps.filter { $0.sectionTitle == title }
            let rows = steps.filter { $0.hasCounter && isRowCounter($0) }.reduce(0) { $0 + $1.currentStepCount }
            let finalSts = steps.compactMap(\.stitchCountAfter).last(where: { $0 > 0 })
            return SectionSummary(
                id: title,
                title: title,
                total: steps.count,
                completed: steps.filter(\.isCompleted).count,
                rows: rows,
                finalStitches: finalSts
            )
        }
    }
    
    private var extraCountersSummary: [(String, Int)] {
        var result: [(String, Int)] = []
        for step in sortedSteps {
            let labels = step.safeExtraCounterLabels
            let values = step.safeExtraCounterValues
            for (i, label) in labels.enumerated() {
                let v = i < values.count ? values[i] : 0
                result.append((label, v))
            }
        }
        for counter in project.counters.sorted(by: { $0.orderIndex < $1.orderIndex }) where counter.currentCount > 0 {
            result.append((counter.title, counter.currentCount))
        }
        return result
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    // Intestazione celebrativa
                    VStack(spacing: 10) {
                        Image(systemName: "party.popper.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.orange, .pink)
                            .padding(.top, 20)
                        Text("Hai finito!")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("\(project.title)\(project.selectedSize.isEmpty ? "" : " · Taglia \(project.selectedSize)")")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.accentColor)
                        if !project.designer.isEmpty {
                            Text("di \(project.designer)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Statistiche principali
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatTile(icon: "clock.fill", color: .orange,
                                 value: TimerManager.shared.formatTime(project.totalSecondsWorked),
                                 label: "Tempo di lavoro")
                        StatTile(icon: "checkmark.circle.fill", color: .green,
                                 value: "\(completedCount)/\(sortedSteps.count)",
                                 label: "Schede completate")
                        StatTile(icon: "line.3.horizontal", color: .indigo,
                                 value: "\(rowsCounted)",
                                 label: "Ferri/giri contati")
                        StatTile(icon: "number", color: .blue,
                                 value: "\(stitchesCounted)",
                                 label: "Maglie contate")
                    }
                    .padding(.horizontal)
                    
                    // Date
                    HStack(spacing: 0) {
                        DateBlock(title: "Iniziato", date: project.createdAt)
                        Divider().frame(height: 36)
                        DateBlock(title: "Finito", date: endDate)
                        Divider().frame(height: 36)
                        VStack(spacing: 2) {
                            Text("\(daysSpan)")
                                .font(.headline.monospacedDigit())
                            Text(daysSpan == 1 ? "giorno" : "giorni")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    
                    // Riepilogo per sezione
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Cosa hai lavorato")
                            .font(.headline)
                        
                        ForEach(sectionSummaries) { sec in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: sec.completed == sec.total ? "checkmark.circle.fill" : "circle.dashed")
                                    .foregroundColor(sec.completed == sec.total ? .green : .secondary)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(sec.title)
                                        .font(.subheadline.bold())
                                    HStack(spacing: 10) {
                                        Text("\(sec.completed)/\(sec.total) schede")
                                        if sec.rows > 0 {
                                            Text("• \(sec.rows) ferri/giri")
                                        }
                                        if let sts = sec.finalStitches {
                                            Text("• \(sts) maglie")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal)
                    
                    if !extraCountersSummary.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Altri contatori")
                                .font(.headline)
                            ForEach(Array(extraCountersSummary.enumerated()), id: \.offset) { _, item in
                                HStack {
                                    Text(item.0)
                                    Spacer()
                                    Text("\(item.1)")
                                        .bold()
                                        .monospacedDigit()
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Azioni
                    VStack(spacing: 10) {
                        Button(action: onExit) {
                            Label("Torna ai progetti", systemImage: "house.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        Button(action: onReviewGuide) {
                            Text("Rivedi la guida")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .foregroundColor(.secondary)
                        
                        Button(role: .destructive) {
                            showingRestartAlert = true
                        } label: {
                            Label("Ricomincia da capo", systemImage: "arrow.counterclockwise")
                                .font(.subheadline.bold())
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onReviewGuide()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .alert("Ricomincia da capo", isPresented: $showingRestartAlert) {
                Button("Annulla", role: .cancel) { }
                Button("Ricomincia da capo", role: .destructive) {
                    project.resetAllProgress(modelContext: modelContext)
                    if let onRestart = onRestartFromBeginning {
                        onRestart()
                    } else {
                        onReviewGuide()
                    }
                }
            } message: {
                Text("Sei sicuro di voler ricominciare \"\(project.title)\" da capo? Tutti i progressi, i contatori e il tempo registrato verranno azzerati.")
            }
        }
    }
}

private struct StatTile: View {
    let icon: String
    let color: Color
    let value: String
    let label: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct DateBlock: View {
    let title: String
    let date: Date
    
    var body: some View {
        VStack(spacing: 2) {
            Text(date.formatted(.dateTime.day().month(.abbreviated).year()))
                .font(.subheadline.bold())
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
