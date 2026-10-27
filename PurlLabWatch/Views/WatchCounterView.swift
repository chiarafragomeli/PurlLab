import SwiftUI
import WatchKit

struct WatchCounterView: View {
    @Bindable var watchManager = WatchConnectivityManager.shared
    @State private var crownValue: Double = 0
    @State private var showingProjectList = false
    
    private var project: WatchProjectSummary? {
        watchManager.activeProject
    }
    
    var body: some View {
        NavigationStack {
            if let project = project {
                ScrollView {
                    VStack(spacing: 8) {
                        // Header: Titolo Progetto e Taglia
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(project.title)
                                    .font(.headline.bold())
                                    .foregroundColor(Color(red: 0.850, green: 0.350, blue: 0.550))
                                    .lineLimit(1)
                                
                                Text(project.displaySubtitle)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            
                            // Tasto cambio progetto
                            Button {
                                showingProjectList = true
                            } label: {
                                Image(systemName: "folder")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(6)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 4)
                        
                        // Badge Scheda e Sezione Attuale
                        if !project.currentSectionTitle.isEmpty {
                            VStack(spacing: 2) {
                                Text(project.currentSectionTitle.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                
                                if !project.currentStepTitle.isEmpty {
                                    Text(project.currentStepTitle)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(8)
                        }
                        
                        // CONTATORE FERRI PRINCIPALE
                        VStack(spacing: 4) {
                            Text(project.counterLabel.isEmpty ? "Ferri" : project.counterLabel)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(project.currentCount)")
                                    .font(.system(size: 48, weight: .bold, design: .rounded))
                                    .foregroundColor(project.isTargetReached ? .green : .white)
                                    .contentTransition(.numericText())
                                
                                if let target = project.targetCount, target > 0 {
                                    Text("/ \(target)")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                        .focusable()
                        .digitalCrownRotation(
                            $crownValue,
                            from: 0,
                            through: Double(max(project.targetCount ?? 999, 999)),
                            by: 1.0,
                            sensitivity: .medium,
                            isContinuous: false,
                            isHapticFeedbackEnabled: true
                        )
                        .onChange(of: crownValue) { _, newValue in
                            let intVal = Int(newValue)
                            if intVal != project.currentCount {
                                watchManager.setMainCounter(to: intVal)
                            }
                        }
                        
                        // PULSANTI CONTATORE (+ e -)
                        HStack(spacing: 12) {
                            // Tasto Meno (-)
                            Button {
                                watchManager.decrementMainCounter()
                                crownValue = Double(project.currentCount - 1)
                            } label: {
                                Image(systemName: "minus")
                                    .font(.title3.bold())
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(Color.white.opacity(0.18))
                                    .foregroundColor(.white)
                                    .cornerRadius(22)
                            }
                            .buttonStyle(.plain)
                            .disabled(project.currentCount <= 0)
                            
                            // Tasto Più (+) GRANDE E COMODO
                            Button {
                                watchManager.incrementMainCounter()
                                crownValue = Double(project.currentCount + 1)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.title2.bold())
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(project.isTargetReached ? Color.green : Color(red: 0.850, green: 0.350, blue: 0.550))
                                    .foregroundColor(.white)
                                    .cornerRadius(24)
                                    .shadow(color: (project.isTargetReached ? Color.green : Color(red: 0.850, green: 0.350, blue: 0.550)).opacity(0.4), radius: 6)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 4)
                        
                        // BARRA SESSIONE E TIMER (SINCRONIZZATA CON IPHONE)
                        Button {
                            watchManager.toggleTimer()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: project.isTimerRunning ? "pause.fill" : "play.fill")
                                    .font(.caption.bold())
                                    .foregroundColor(project.isTimerRunning ? .orange : .green)
                                
                                Text(project.isTimerRunning ? "Sessione attiva" : "Avvia Sessione")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                if project.totalSecondsWorked > 0 {
                                    Text(formatWatchTime(project.totalSecondsWorked))
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 2)
                }
                .sheet(isPresented: $showingProjectList) {
                    WatchProjectListView()
                }
                .onAppear {
                    crownValue = Double(project.currentCount)
                }
                .onChange(of: project.currentCount) { _, newCount in
                    crownValue = Double(newCount)
                }
            } else {
                // Nessun progetto attivo
                VStack(spacing: 8) {
                    Image(systemName: "applewatch.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundColor(Color(red: 0.850, green: 0.350, blue: 0.550))
                    
                    Text("PurlLab")
                        .font(.headline.bold())
                    
                    Text("Apri l'app su iPhone per avviare o sincronizzare un pattern.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                    
                    Button("Aggiorna") {
                        watchManager.requestSyncFromPhone()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.850, green: 0.350, blue: 0.550))
                    .font(.caption2.bold())
                    .padding(.top, 4)
                }
                .padding()
            }
        }
    }
    
    private func formatWatchTime(_ totalSeconds: TimeInterval) -> String {
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else {
            return String(format: "%02dm", minutes)
        }
    }
}
