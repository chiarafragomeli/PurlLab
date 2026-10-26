import Foundation

struct GeneratedGuideResponse: Codable {
    let patternTitle: String
    let designer: String?
    let targetSize: String
    let gauge: String?
    let needles: [String]?
    let sections: [GeneratedSection]
}

struct GeneratedSection: Codable {
    let name: String
    let steps: [GeneratedStep]
}

struct GeneratedStep: Codable {
    let title: String?
    let stepType: String? // "info", "single_action", "repeat_pattern", "work_to_measure"
    let instruction: String
    let subSteps: [String]?
    let repeatVariations: [String]?
    let rowsPerRepeat: Int?
    let totalRepeats: Int?
    let stitchCountBefore: Int?
    let stitchCountAfter: Int?
    let targetMeasureCm: Double?
    let hasCounter: Bool?
    let counterLabel: String?
    let targetStepCount: Int?
    let sourcePage: Int?
    let sourceQuote: String?
}

enum GeminiError: LocalizedError {
    case missingApiKey
    case invalidApiKeyFormat
    case invalidURL
    case networkError(String)
    case parsingError(String)
    
    var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "Chiave API di Gemini non trovata. Inseriscila nelle Impostazioni."
        case .invalidApiKeyFormat:
            return "La chiave API inserita sembra troppo corta o non valida. Inserisci una chiave valida da Google AI Studio."
        case .invalidURL:
            return "URL dell'endpoint non valido."
        case .networkError(let msg):
            return "Errore di rete: \(msg)"
        case .parsingError(let msg):
            return "Errore nell'interpretazione della risposta: \(msg)"
        }
    }
}

final class GeminiService: @unchecked Sendable {
    static let shared = GeminiService()
    private init() {}
    
    func generateGuide(from pdfData: Data, targetSize: String) async throws -> GeneratedGuideResponse {
        guard let rawKey = KeychainHelper.shared.getGeminiApiKey(), !rawKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiError.missingApiKey
        }
        
        let apiKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if apiKey.count < 20 {
            throw GeminiError.invalidApiKeyFormat
        }
        
        let base64Pdf = pdfData.base64EncodedString()
        
        let systemPrompt = """
        Sei una maestra di maglia (knitting) ed editor tecnica esperta.
        Il tuo compito è trasformare il pattern PDF in una GUIDA OPERATIVA INTERATTIVA a "Scheda Singola" (una card per ogni fase operativa reale) in LINGUA ITALIANA per la TAGLIA "\(targetSize)".
        
        RAGIONA SU COSA DEVE FARE FISICAMENTE CHI LAVORA A MAGLIA:
        
        1. VIETATO SPEZZETTARE LE FRASI INTRODUTTIVE IN CARD VUOTE:
           - NON creare MAI una card che dice solo "Lavorare i ferri accorciati come segue:" lasciando i passaggi in card separate.
           - Ogni card deve essere un'unità di lavoro autonoma e completa.
        
        2. RICONOSCIMENTO DEI PATTERN RIPETUTI (stepType = "repeat_pattern"):
           - Quando il pattern chiede di ripetere una sequenza di ferri o giri più volte, raggruppa l'INTERO ciclo ripetuto in UN'UNICA CARD di tipo "repeat_pattern"!
           - Esempio 1 (Ferri Accorciati): Se il pattern descrive i Passi/Ferri 1-4 e poi dice "Ripetere i Passi 1-4 per altre 4 volte" (5 volte in totale):
             * Crea UN'UNICA CARD intitolata es. "Ferri Accorciati sullo Sprone (5 ripetizioni = 20 ferri)".
             * rowsPerRepeat = 4 (i 4 ferri del ciclo)
             * totalRepeats = 5 (la prima volta + le altre 4 ripetizioni = 5 cicli totali)
             * targetStepCount = 20 (perché 5 ripetizioni × 4 ferri = 20 ferri totali lavorati!)
             * hasCounter = true, counterLabel = "Ferri Accorciati (5 cicli da 4 ferri)"
             * subSteps = array con la descrizione esatta di ciascuno dei 4 ferri: ["Ferro 1 (Dir): ...", "Ferro 2 (Rov): ...", "Ferro 3 (Rov): ...", "Ferro 4 (Dir): ..."]
             * repeatVariations = array con cosa cambia in ogni ripetizione (es. ["Ripetizione 1 (Ferri 1-4): ...", "Ripetizione 2 (Ferri 5-8): ...", ...])
           - Esempio 2 (Aumenti Raglan in tondo): Se il pattern dice "*Giro 1 con 8 aumenti raglan, Giro 2 tutto a diritto*, ripetere per un totale di 29 volte":
             * Crea UN'UNICA CARD con stepType = "repeat_pattern".
             * rowsPerRepeat = 2, totalRepeats = 29, targetStepCount = 58 (29 × 2 = 58 giri totali!).
             * subSteps = ["Giro 1 (Aumenti Raglan - +8 maglie): ...", "Giro 2 (Giro pari): Lavorare tutto a diritto senza aumenti."]
           - Esempio 3 (Diminuzioni Manica): Se il pattern dice "Diminuire ogni 6° giro per 18 volte":
             * Crea UN'UNICA CARD con stepType = "repeat_pattern".
             * rowsPerRepeat = 6, totalRepeats = 18, targetStepCount = 108 (18 × 6 = 108 giri totali!).
             * subSteps = ["Giri 1-5: Lavorare a diritto in tondo senza diminuzioni.", "Giro 6 (Giro di diminuzione - -2 maglie): ..."]
        
        3. DECIDERE QUANDO METTERE IL CONTATORE (hasCounter = true / false):
           - hasCounter = TRUE quando l'utente deve contare attivamente:
             * Avvio maglie (cast on): targetStepCount = numero maglie da avviare (es. 114), counterLabel = "Maglie Avviate".
             * Pattern ripetuti (repeat_pattern): targetStepCount = rowsPerRepeat * totalRepeats (es. 20 ferri, 58 giri, 108 giri).
             * Lavorazione a centimetri (work_to_measure, es. "Lavorare 4 cm a coste 1/1" o "7 cm a coste"): imposta hasCounter = true e calcola targetStepCount = numero stimato di giri in base al campione del pattern (es. 28 ferri = 10 cm -> 4 cm = 11 giri; 7 cm = 20 giri), così l'utente può contare i giri lavorati!
             * Giro singolo con serie di diminuzioni/aumenti (es. "*7 dir, 2 dir ins* per 25 volte + 1 volta"): hasCounter = true, targetStepCount = numero totale di diminuzioni (es. 26).
             * Intreccio maglie (bind off): hasCounter = true, targetStepCount = numero maglie da intrecciare.
           - hasCounter = FALSE SOLO per:
             * Informazioni generali (campione, materiali, filato) -> stepType = "info".
             * Posizionamento iniziale dei marcapunti o semplice cambio ferri senza lavorazione prolungata.
        
        4. FILTRO TAGLIA E GLOSSARIO ITALIANO:
           - Mostra SOLO i numeri per la taglia "\(targetSize)".
           - Usa i termini italiani: dir (diritto), rov (rovescio), 2 dir ins (k2tog), 2 dir ins ritorto / acc (ssk / k2tog tbl), AID (M1R), AIS (M1L), MP (marcapunti), ferri accorciati alla tedesca (German short rows).
        """
        
        let userPrompt = "Analizza il pattern PDF per la taglia \(targetSize) e genera la guida operativa JSON completa in italiano, calcolando con precisione ferri totali, ripetizioni e maglie."
        
        let jsonSchema: [String: Any] = [
            "type": "OBJECT",
            "properties": [
                "patternTitle": ["type": "STRING"],
                "designer": ["type": "STRING"],
                "targetSize": ["type": "STRING"],
                "gauge": ["type": "STRING"],
                "needles": [
                    "type": "ARRAY",
                    "items": ["type": "STRING"]
                ],
                "sections": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "name": ["type": "STRING"],
                            "steps": [
                                "type": "ARRAY",
                                "items": [
                                    "type": "OBJECT",
                                    "properties": [
                                        "title": ["type": "STRING"],
                                        "stepType": [
                                            "type": "STRING",
                                            "enum": ["info", "single_action", "repeat_pattern", "work_to_measure"]
                                        ],
                                        "instruction": ["type": "STRING"],
                                        "subSteps": [
                                            "type": "ARRAY",
                                            "items": ["type": "STRING"]
                                        ],
                                        "repeatVariations": [
                                            "type": "ARRAY",
                                            "items": ["type": "STRING"]
                                        ],
                                        "rowsPerRepeat": ["type": "INTEGER"],
                                        "totalRepeats": ["type": "INTEGER"],
                                        "stitchCountBefore": ["type": "INTEGER"],
                                        "stitchCountAfter": ["type": "INTEGER"],
                                        "targetMeasureCm": ["type": "NUMBER"],
                                        "hasCounter": ["type": "BOOLEAN"],
                                        "counterLabel": ["type": "STRING"],
                                        "targetStepCount": ["type": "INTEGER"],
                                        "sourcePage": ["type": "INTEGER"],
                                        "sourceQuote": ["type": "STRING"]
                                    ],
                                    "required": ["title", "stepType", "instruction", "hasCounter"]
                                ]
                            ]
                        ],
                        "required": ["name", "steps"]
                    ]
                ]
            ],
            "required": ["patternTitle", "targetSize", "sections"]
        ]
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        [
                            "inline_data": [
                                "mime_type": "application/pdf",
                                "data": base64Pdf
                            ]
                        ],
                        [
                            "text": userPrompt
                        ]
                    ]
                ]
            ],
            "system_instruction": [
                "parts": [
                    ["text": systemPrompt]
                ]
            ],
            "generationConfig": [
                "response_mime_type": "application/json",
                "response_schema": jsonSchema,
                "temperature": 0.1,
                "thinkingConfig": [
                    "thinkingBudget": 4096
                ]
            ]
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        let candidateModels = ["gemini-3-flash-preview", "gemini-2.5-flash"]
        var lastError: Error?
        
        for model in candidateModels {
            let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
            guard let url = URL(string: urlString) else { continue }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 150
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            request.httpBody = bodyData
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    continue
                }
                
                if httpResponse.statusCode == 200 {
                    struct GeminiAPIResponse: Decodable {
                        struct Candidate: Decodable {
                            struct Content: Decodable {
                                struct Part: Decodable {
                                    let text: String?
                                    let thought: Bool?
                                }
                                let parts: [Part]?
                            }
                            let content: Content?
                        }
                        let candidates: [Candidate]?
                    }
                    
                    let apiResponse = try JSONDecoder().decode(GeminiAPIResponse.self, from: data)
                    let parts = apiResponse.candidates?.first?.content?.parts ?? []
                    let textPart = parts.last(where: { $0.thought != true && $0.text != nil }) ?? parts.last
                    
                    guard let jsonString = textPart?.text,
                          let jsonData = jsonString.data(using: .utf8) else {
                        throw GeminiError.parsingError("Nessun testo JSON generato da Gemini")
                    }
                    
                    return try JSONDecoder().decode(GeneratedGuideResponse.self, from: jsonData)
                } else {
                    let errorText = String(data: data, encoding: .utf8) ?? "Status code: \(httpResponse.statusCode)"
                    lastError = GeminiError.networkError("HTTP \(httpResponse.statusCode): \(errorText)")
                    // Prova il modello successivo se 503 o 429
                    continue
                }
            } catch {
                lastError = error
                continue
            }
        }
        
        throw lastError ?? GeminiError.networkError("Impossibile contattare i modelli Gemini.")
    }
}
