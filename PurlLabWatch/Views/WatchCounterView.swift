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
                        headerView(project: project)
                        sectionBanner(project: project)
                        counterSection(project: project)
                        counterButtons(project: project)
                        
                        if project.isTargetReached || project.isStepCompleted {
                            completeStepButton(project: project)
                        }
                        
                        statsFooter(project: project)
                        timerButton(project: project)
                    }
                    .padding(.bottom, 12)
                }
                .navigationDestination(isPresented: $showingProjectList) {
                    WatchProjectListView()
                }
                .onAppear {
                    crownValue = Double(project.currentCount)
                    watchManager.requestSyncFromPhone()
                }
                .onChange(of: project.currentCount) { _, newCount in
                    crownValue = Double(newCount)
                }
            } else {
                emptyStateView
            }
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private func headerView(project: WatchProjectSummary) -> some View {
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
    }
    
    @ViewBuilder
    private func sectionBanner(project: WatchProjectSummary) -> some View {
        VStack(spacing: 4) {
            HStack {
                Button {
                    watchManager.previousStep()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(project.canGoPrevious ? .accentColor : .secondary.opacity(0.3))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!project.canGoPrevious)
                
                Spacer()
                
                VStack(spacing: 1) {
                    if !project.currentSectionTitle.isEmpty {
                        Text(project.currentSectionTitle.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(red: 0.850, green: 0.350, blue: 0.550))
                            .lineLimit(1)
                    }
                    
                    if project.totalStepsCount > 0 {
                        Text("Scheda \(project.currentStepIndex + 1) di \(project.totalStepsCount)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    watchManager.nextStep()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(project.canGoNext ? .accentColor : .secondary.opacity(0.3))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!project.canGoNext)
            }
            
            if !project.currentStepTitle.isEmpty {
                Text(project.currentStepTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 4)
            }
            
            if let stitchesText = project.stitchesDescription {
                HStack(spacing: 4) {
                    Image(systemName: "circle.grid.cross.fill")
                        .font(.system(size: 8))
                    Text(stitchesText)
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.indigo.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.indigo.opacity(0.18))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func counterSection(project: WatchProjectSummary) -> some View {
        VStack(spacing: 2) {
            Text(project.counterLabel.isEmpty ? "Ferri Sezione" : project.counterLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(project.currentCount)")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
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
    }
    
    @ViewBuilder
    private func counterButtons(project: WatchProjectSummary) -> some View {
        HStack(spacing: 12) {
            Button {
                watchManager.decrementMainCounter()
                crownValue = Double(max(0, project.currentCount - 1))
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
    }
    
    @ViewBuilder
    private func completeStepButton(project: WatchProjectSummary) -> some View {
        Button {
            watchManager.completeStep()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text(project.isStepCompleted ? "Già completata · Avanti" : "Completa Scheda")
            }
            .font(.system(size: 11, weight: .bold))
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(Color.green.opacity(0.25))
            .foregroundColor(.green)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
    
    @ViewBuilder
    private func statsFooter(project: WatchProjectSummary) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                Image(systemName: "number")
                    .font(.system(size: 9))
                Text("\(project.totalRowsWorked) f totali")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(.secondary)
            
            Text("•")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            
            HStack(spacing: 3) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                Text("\(project.totalStitchesWorked) m lavorate")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(.indigo.opacity(0.9))
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.06))
        .cornerRadius(6)
    }
    
    @ViewBuilder
    private func timerButton(project: WatchProjectSummary) -> some View {
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
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.12))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("In attesa di iPhone...")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Sincronizza") {
                watchManager.requestSyncFromPhone()
            }
            .font(.caption2)
            .buttonStyle(.bordered)
        }
        .padding()
    }
    
    private func formatWatchTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            let secs = total % 60
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}
