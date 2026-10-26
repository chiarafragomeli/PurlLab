import SwiftUI
import SwiftData

struct CountersView: View {
    @Bindable var project: KnittingProject
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddCounterSheet = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if project.counters.isEmpty {
                        ContentUnavailableView(
                            "Nessun Contatore",
                            systemImage: "number.circle",
                            description: Text("Aggiungi un contatore per ferri, aumenti o ripetizioni.")
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(project.counters.sorted(by: { $0.orderIndex < $1.orderIndex })) { counter in
                            CounterCardView(counter: counter) {
                                deleteCounter(counter)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Contatori")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddCounterSheet = true
                    } label: {
                        Label("Aggiungi", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddCounterSheet) {
                AddCounterSheet(project: project)
            }
        }
    }
    
    private func deleteCounter(_ counter: RowCounter) {
        if let index = project.counters.firstIndex(where: { $0.id == counter.id }) {
            project.counters.remove(at: index)
            modelContext.delete(counter)
        }
    }
}

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
            HStack(spacing: 20) {
                // Decrement Button
                Button {
                    TimerManager.shared.registerInteraction()
                    haptic.impactOccurred()
                    counter.decrement()
                } label: {
                    Image(systemName: "minus")
                        .font(.title2.bold())
                        .frame(width: 52, height: 52)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
                .disabled(counter.currentCount == 0)
                
                Spacer()
                
                // Count Display
                Text("\(counter.currentCount)")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundColor(isAtTarget ? .green : .primary)
                    .contentTransition(.numericText())
                
                Spacer()
                
                // Big Increment Button
                Button {
                    TimerManager.shared.registerInteraction()
                    haptic.impactOccurred()
                    counter.increment()
                    if isAtTarget {
                        successHaptic.notificationOccurred(.success)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.title.bold())
                        .foregroundColor(.white)
                        .frame(width: 64, height: 64)
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
    }
    
    private var isAtTarget: Bool {
        if let target = counter.targetCount, target > 0 {
            return counter.currentCount >= target
        }
        return false
    }
}

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
                        dismiss()
                    }
                }
            }
        }
    }
}
