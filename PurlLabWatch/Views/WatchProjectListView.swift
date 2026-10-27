import SwiftUI

struct WatchProjectListView: View {
    @Bindable var watchManager = WatchConnectivityManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                if watchManager.projects.isEmpty {
                    VStack(spacing: 6) {
                        Text("Nessun Progetto")
                            .font(.headline)
                        Text("Aggiungi o importa un progetto su iPhone.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ForEach(watchManager.projects) { project in
                        let isSelected = (project.id == watchManager.activeProject?.id)
                        Button {
                            watchManager.selectProject(id: project.id)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.title)
                                        .font(.subheadline.bold())
                                        .foregroundColor(isSelected ? Color(red: 0.850, green: 0.350, blue: 0.550) : .white)
                                        .lineLimit(1)
                                    
                                    HStack(spacing: 4) {
                                        if !project.selectedSize.isEmpty {
                                            Text(project.selectedSize)
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.white.opacity(0.12))
                                                .cornerRadius(4)
                                        }
                                        
                                        Text("\(project.currentCount) \(project.counterLabel.isEmpty ? "m/f" : project.counterLabel)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color(red: 0.850, green: 0.350, blue: 0.550))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("I Tuoi Progetti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }
}
