import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var isKeySaved: Bool = false
    @State private var autoPauseMinutes: Double = 15.0
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Chiave API di Gemini (inizia con AIzaSy...)", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    
                    if !apiKey.isEmpty && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).starts(with: "AIzaSy") {
                        Label("La chiave deve iniziare con 'AIzaSy'. Verificala su Google AI Studio.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    Button {
                        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        if KeychainHelper.shared.saveGeminiApiKey(cleanKey) {
                            isKeySaved = true
                        }
                    } label: {
                        HStack {
                            Text(isKeySaved ? "Chiave Salvata nel Keychain" : "Salva Chiave")
                            if isKeySaved {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
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
                    Text("La chiave API viene salvata esclusivamente nel Keychain crittografato del tuo iPhone e usata solo per analizzare i pattern che carichi.")
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
                }
                autoPauseMinutes = TimerManager.shared.autoPauseMinutes
            }
            .onChange(of: autoPauseMinutes) { _, newValue in
                TimerManager.shared.autoPauseMinutes = newValue
            }
        }
    }
}
