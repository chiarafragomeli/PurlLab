import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var isKeySaved: Bool = false
    @State private var isTestingConnection: Bool = false
    @State private var testResult: String?
    @State private var isTestSuccessful: Bool = false
    @State private var autoPauseMinutes: Double = 15.0
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Chiave API di Gemini", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    
                    HStack(spacing: 12) {
                        Button {
                            let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            if KeychainHelper.shared.saveGeminiApiKey(cleanKey) {
                                isKeySaved = true
                                testApiKey(cleanKey)
                            }
                        } label: {
                            Label(isKeySaved ? "Chiave Salvata" : "Salva Chiave", systemImage: isKeySaved ? "checkmark.circle.fill" : "square.and.arrow.down")
                        }
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        
                        Spacer()
                        
                        Button {
                            testApiKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        } label: {
                            if isTestingConnection {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Label("Test Connessione", systemImage: "network")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTestingConnection)
                    }
                    
                    if let result = testResult {
                        HStack(spacing: 8) {
                            Image(systemName: isTestSuccessful ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(isTestSuccessful ? .green : .red)
                            Text(result)
                                .font(.caption.bold())
                                .foregroundColor(isTestSuccessful ? .green : .red)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    Button {
                        apiKey = KeychainHelper.defaultVerifiedKey
                        _ = KeychainHelper.shared.saveGeminiApiKey(apiKey)
                        isKeySaved = true
                        testApiKey(apiKey)
                    } label: {
                        Label("Ripristina Chiave Predefinita", systemImage: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    
                    Link(destination: URL(string: "https://aistudio.google.com/app/apikey")!) {
                        HStack {
                            Text("Ottieni una chiave gratuita su Google AI Studio")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                        .font(.footnote)
                    }
                } header: {
                    Text("Google Gemini AI")
                } footer: {
                    Text("La chiave API viene salvata nel Keychain del tuo dispositivo. Puoi testare la connessione direttamente con il pulsante dedicato.")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pausa automatica dopo inattività")
                        HStack {
                            Slider(value: $autoPauseMinutes, in: 5...60, step: 5)
                            Text("\(Int(autoPauseMinutes)) min")
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Timer e Lavoro")
                }
                
                Section {
                    HStack {
                        Text("Versione")
                        Spacer()
                        Text("1.0.0 (PurlLab)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Sviluppata per")
                        Spacer()
                        Text("Solo uso personale")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Informazioni")
                }
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .onAppear {
                if let saved = KeychainHelper.shared.getGeminiApiKey() {
                    apiKey = saved
                    isKeySaved = true
                } else {
                    apiKey = KeychainHelper.defaultVerifiedKey
                    _ = KeychainHelper.shared.saveGeminiApiKey(apiKey)
                    isKeySaved = true
                }
                autoPauseMinutes = TimerManager.shared.autoPauseMinutes
            }
            .onChange(of: autoPauseMinutes) { _, newValue in
                TimerManager.shared.autoPauseMinutes = newValue
            }
        }
    }
    
    private func testApiKey(_ key: String) {
        guard key.count >= 20 else {
            testResult = "La chiave inserita è troppo corta o non valida."
            isTestSuccessful = false
            return
        }
        
        isTestingConnection = true
        testResult = nil
        
        Task {
            do {
                _ = try await GeminiService.shared.testConnection(with: key)
                await MainActor.run {
                    isTestingConnection = false
                    isTestSuccessful = true
                    testResult = "Connessione riuscita! API Gemini attiva."
                }
            } catch {
                await MainActor.run {
                    isTestingConnection = false
                    isTestSuccessful = false
                    testResult = "Errore: \(error.localizedDescription)"
                }
            }
        }
    }
}
