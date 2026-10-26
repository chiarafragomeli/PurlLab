import Foundation

struct GeneratedGuideResponse: Codable {
    let patternTitle: String
    let designer: String?
    let targetSize: String
    let gauge: String?
    let needles: [String]?
    var recalculationSummary: String?
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
    
    /// Rimuove eventuali traduzioni inglesi tra parentesi dai nomi delle sezioni (es. "Corpo (Body)" -> "Corpo").
    static func cleanSectionName(_ name: String) -> String {
        let pattern = #"\s*\((?i:body|yoke|sleeves?|neck(?:band|line)?|collar|hem|finishing|cuffs?|front|back|ribbing|set[- ]?up|gauge|materials|short rows|raglan increases|divide|edging|pocket|hood)\)"#
        let cleaned = name.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
    
    /// Verifica se la chiave API configurata risponde correttamente
    func testConnection(with key: String? = nil) async throws -> Bool {
        let rawKey = key ?? KeychainHelper.shared.getGeminiApiKey() ?? ""
        let cleanKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanKey.count >= 20 else { throw GeminiError.invalidApiKeyFormat }
        
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(cleanKey)"
        guard let url = URL(string: urlString) else { throw GeminiError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let testBody: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": "ping"]]]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: testBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.networkError("Nessuna risposta dal server")
        }
        
        if http.statusCode == 200 {
            return true
        } else {
            let errorText = String(data: data, encoding: .utf8) ?? "Status code: \(http.statusCode)"
            throw GeminiError.networkError("HTTP \(http.statusCode): \(errorText)")
        }
    }
    
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
           - I nomi delle sezioni ("name") e i titoli delle schede devono essere SOLO in italiano, SENZA la traduzione inglese tra parentesi (es. "Corpo" e NON "Corpo (Body)", "Sprone" e NON "Sprone (Yoke)", "Maniche" e NON "Maniche (Sleeves)").
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
    
    // MARK: - Ricalcolo Pattern per Campione Personalizzato (AI & Locale)
    
    /// Ricalcola l'intera guida operativa con Gemini AI in base al campione personalizzato dell'utente
    func recalculateGuideForGauge(
        patternTitle: String,
        targetSize: String,
        pdfData: Data?,
        currentStepsDescription: String,
        patternStitches: Double,
        patternRows: Double,
        userStitches: Double,
        userRows: Double
    ) async throws -> GeneratedGuideResponse {
        guard let rawKey = KeychainHelper.shared.getGeminiApiKey(), !rawKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiError.missingApiKey
        }
        
        let apiKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if apiKey.count < 20 {
            throw GeminiError.invalidApiKeyFormat
        }
        
        let effectiveSize = targetSize.isEmpty ? "M" : targetSize
        let stitchRatio = userStitches / patternStitches
        let rowRatio = userRows / patternRows
        let stitchDiffPct = String(format: "%+.1f%%", (stitchRatio - 1.0) * 100)
        let rowDiffPct = String(format: "%+.1f%%", (rowRatio - 1.0) * 100)
        
        let systemPrompt = """
        Sei una knitwear designer esperta, tecnica tessile e maestra di maglia.
        Il tuo compito è RICALCOLARE MATEMATICAMENTE l'INTERA guida operativa a scheda singola per la taglia "\(effectiveSize)" in LINGUA ITALIANA, adattandola al CAMPIONE REALE ottenuto dall'utente con il proprio filato.
        
        DATI DEL CAMPIONE (misurato su 10 × 10 cm a maglia rasata):
        - Campione originale del pattern: \(patternStitches) maglie × \(patternRows) ferri
        - Campione reale dell'utente: \(userStitches) maglie × \(userRows) ferri
        - Variazione larghezza (maglie): \(stitchDiffPct) (fattore di scala: \(String(format: "%.4f", stitchRatio)))
        - Variazione altezza (ferri): \(rowDiffPct) (fattore di scala: \(String(format: "%.4f", rowRatio)))
        
        REGOLE FONDAMENTALI DI RICALCOLO:
        1. LE DIMENSIONI IN CENTIMETRI DEL CAPO NON DEVONO CAMBIARE:
           - Tutte le misure finite in cm (circonferenza torace, lunghezza corpo, lunghezza maniche, profondità sprone) devono rimanere IDENTICHE a quelle originali previste dal cartamodello per la taglia "\(effectiveSize)".
        2. RICALCOLO DELLE MAGLIE:
           - Ogni conteggio di maglie (avvio del collo, maglie davanti/dietro/maniche, maglie sottomanica, maglie ai polsini) deve essere ricalcolato moltiplicando per il fattore \(String(format: "%.4f", stitchRatio)) e arrotondato opportunamente.
           - Mantieni la parità/modularità richiesta dal motivo (es. coste 1/1 = numero pari; coste 2/2 = multiplo di 4).
           - Mantieni la perfetta simmetria tra davanti e dietro e tra manica destra e sinistra.
        3. RICALCOLO DEI FERRI E DELLE RIPETIZIONI (repeat_pattern e work_to_measure):
           - Per le sezioni lavorate a centimetri (stepType = "work_to_measure"), il conteggio stimato dei giri (targetStepCount) deve corrispondere a: (userRows / 10.0 * targetMeasureCm).
           - Per gli aumenti raglan e le diminuzioni sagomate delle maniche, adatta il numero totale di ripetizioni (totalRepeats) e ferri (rowsPerRepeat * totalRepeats) in modo che alla fine dello sprone si ottengano sia i centimetri che il nuovo totale di maglie corretto per il corpo e le maniche.
        4. AGGIORNAMENTO TESTI E CONTATORI:
           - Ogni singola istruzione (`instruction`, `subSteps`, `repeatVariations`, `title`, `counterLabel`) DEVE RIPORTARE I NUOVI NUMERI RICALCOLATI.
           - I nomi delle sezioni devono essere solo in italiano (es. "Preparazione", "Collo e Impostazione Sprone", "Sprone", "Corpo", "Manica Destra", "Manica Sinistra").
        5. RIEPILOGO DELLE MODIFICHE:
           - Inserisci nel campo "recalculationSummary" un riassunto chiaro e dettagliato in italiano di tutte le modifiche chiave apportate (es. "Avvio collo: 114 m → 104 m (-8.8%) | Sprone: 26 ripetizioni raglan anziché 29 | Maniche: 68 m → 62 m | Dimensioni finali in cm preservate").
        """
        
        var userContentParts: [[String: Any]] = []
        
        if let pdfData = pdfData {
            let base64Pdf = pdfData.base64EncodedString()
            userContentParts.append([
                "inline_data": [
                    "mime_type": "application/pdf",
                    "data": base64Pdf
                ]
            ])
            userContentParts.append([
                "text": "Ricalcola l'intero cartamodello per la taglia \(effectiveSize) adattandolo al campione dell'utente (\(userStitches) m × \(userRows) f rispetto all'originale \(patternStitches) m × \(patternRows) f). Restituisci la guida operativa completa ricalcolata in formato JSON."
            ])
        } else {
            userContentParts.append([
                "text": """
                Ecco la guida attuale del pattern "\(patternTitle)" per la taglia "\(effectiveSize)":
                \(currentStepsDescription)
                
                Ricalcola ciascuna sezione e passaggio adattando ogni numero al campione utente (\(userStitches) m × \(userRows) f vs originale \(patternStitches) m × \(patternRows) f). Restituisci la guida operativa completa ricalcolata in formato JSON.
                """
            ])
        }
        
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
                "recalculationSummary": [
                    "type": "STRING",
                    "description": "Riepilogo in italiano delle modifiche numeriche apportate (maglie avviate, ripetizioni raglan, ferri totali)"
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
                    "parts": userContentParts
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
                guard let httpResponse = response as? HTTPURLResponse else { continue }
                
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
                    continue
                }
            } catch {
                lastError = error
                continue
            }
        }
        
        throw lastError ?? GeminiError.networkError("Impossibile contattare i modelli Gemini per il ricalcolo.")
    }
    
    /// Ricalcolo matematico locale istantaneo di fallback (funziona anche offline e senza API key)
    static func recalculateGuideLocally(
        project: KnittingProject,
        patternStitches: Double,
        patternRows: Double,
        userStitches: Double,
        userRows: Double
    ) -> GeneratedGuideResponse {
        let stitchRatio = userStitches / patternStitches
        let rowRatio = userRows / patternRows
        
        let sortedSteps = project.guideSteps.sorted(by: { $0.orderIndex < $1.orderIndex })
        
        // Raggruppa per sezione preservando l'ordine
        var sectionMap: [String: [GuideStep]] = [:]
        var sectionOrder: [String] = []
        for step in sortedSteps {
            if sectionMap[step.sectionTitle] == nil {
                sectionMap[step.sectionTitle] = []
                sectionOrder.append(step.sectionTitle)
            }
            sectionMap[step.sectionTitle]?.append(step)
        }
        
        var generatedSections: [GeneratedSection] = []
        
        for secTitle in sectionOrder {
            let steps = sectionMap[secTitle] ?? []
            var genSteps: [GeneratedStep] = []
            
            for step in steps {
                var newBefore = step.stitchCountBefore
                var newAfter = step.stitchCountAfter
                var newTotalRepeats = step.totalRepeats
                var newTargetStepCount = step.targetStepCount
                var newInstruction = step.instructionText
                var newTitle = step.title
                var newCounterLabel = step.counterLabel
                
                // Ricalcola maglie
                if let b = step.stitchCountBefore, b > 0 {
                    newBefore = max(1, Int(round(Double(b) * stitchRatio)))
                }
                if let a = step.stitchCountAfter, a > 0 {
                    var recalculatedA = max(1, Int(round(Double(a) * stitchRatio)))
                    // Se avvio coste 1/1 assicurati sia pari
                    if step.sectionTitle.localizedCaseInsensitiveContains("Collo") || step.title.localizedCaseInsensitiveContains("Avvio") {
                        if recalculatedA % 2 != 0 { recalculatedA += 1 }
                    }
                    newAfter = recalculatedA
                }
                
                // Ricalcola ferri / ripetizioni
                if step.stepType == "repeat_pattern" {
                    if let repeats = step.totalRepeats, repeats > 0 {
                        // Se sono aumenti raglan (+8 maglie), scala le ripetizioni per il ratio maglie
                        if step.sectionTitle.localizedCaseInsensitiveContains("Sprone") || step.title.localizedCaseInsensitiveContains("Raglan") {
                            newTotalRepeats = max(1, Int(round(Double(repeats) * stitchRatio)))
                        } else {
                            newTotalRepeats = max(1, Int(round(Double(repeats) * rowRatio)))
                        }
                        if let rpr = step.rowsPerRepeat {
                            newTargetStepCount = (newTotalRepeats ?? repeats) * rpr
                        }
                    }
                } else if step.stepType == "work_to_measure" {
                    if let cm = step.targetMeasureCm, cm > 0 {
                        newTargetStepCount = max(1, Int(round((userRows / 10.0) * cm)))
                    } else if let origTarget = step.targetStepCount, origTarget > 0 {
                        newTargetStepCount = max(1, Int(round(Double(origTarget) * rowRatio)))
                    }
                } else if step.hasCounter {
                    if let origTarget = step.targetStepCount, origTarget > 0 {
                        if step.counterLabel?.localizedCaseInsensitiveContains("Maglie") == true || (step.stitchCountAfter != nil && step.stitchCountAfter == origTarget) {
                            newTargetStepCount = newAfter ?? max(1, Int(round(Double(origTarget) * stitchRatio)))
                        } else {
                            newTargetStepCount = max(1, Int(round(Double(origTarget) * rowRatio)))
                        }
                    }
                }
                
                // Aggiorna testi numerici
                if let oldA = step.stitchCountAfter, let recA = newAfter, oldA != recA {
                    newTitle = newTitle.replacingOccurrences(of: "\(oldA)", with: "\(recA)")
                    newInstruction = newInstruction.replacingOccurrences(of: "\(oldA) maglie", with: "\(recA) maglie")
                    newInstruction = newInstruction.replacingOccurrences(of: "\(oldA) m", with: "\(recA) m")
                }
                if let oldR = step.totalRepeats, let recR = newTotalRepeats, oldR != recR {
                    newTitle = newTitle.replacingOccurrences(of: "\(oldR) volte", with: "\(recR) volte")
                    newTitle = newTitle.replacingOccurrences(of: "\(oldR) ripetizioni", with: "\(recR) ripetizioni")
                    newInstruction = newInstruction.replacingOccurrences(of: "\(oldR) volte", with: "\(recR) volte")
                    if let lbl = newCounterLabel {
                        newCounterLabel = lbl.replacingOccurrences(of: "\(oldR)", with: "\(recR)")
                    }
                }
                if let oldT = step.targetStepCount, let recT = newTargetStepCount, oldT != recT {
                    newTitle = newTitle.replacingOccurrences(of: "\(oldT) ferri", with: "\(recT) ferri")
                    newTitle = newTitle.replacingOccurrences(of: "\(oldT) giri", with: "\(recT) giri")
                }
                
                let genStep = GeneratedStep(
                    title: newTitle,
                    stepType: step.stepType,
                    instruction: newInstruction,
                    subSteps: step.subSteps,
                    repeatVariations: step.repeatVariations,
                    rowsPerRepeat: step.rowsPerRepeat,
                    totalRepeats: newTotalRepeats,
                    stitchCountBefore: newBefore,
                    stitchCountAfter: newAfter,
                    targetMeasureCm: step.targetMeasureCm,
                    hasCounter: step.hasCounter,
                    counterLabel: newCounterLabel,
                    targetStepCount: newTargetStepCount,
                    sourcePage: step.sourcePage,
                    sourceQuote: step.sourceQuote
                )
                genSteps.append(genStep)
            }
            
            generatedSections.append(GeneratedSection(name: secTitle, steps: genSteps))
        }
        
        let stitchPct = String(format: "%+.1f%%", (stitchRatio - 1.0) * 100)
        let rowPct = String(format: "%+.1f%%", (rowRatio - 1.0) * 100)
        let summary = "Ricalcolo Matematico Locale: Campione adattato da \(Int(patternStitches)) m × \(Int(patternRows)) f a \(Int(userStitches)) m × \(Int(userRows)) f per 10 cm (Maglie: \(stitchPct), Ferri: \(rowPct)). Misure sartoriali in cm preservate."
        
        return GeneratedGuideResponse(
            patternTitle: project.title,
            designer: project.designer,
            targetSize: project.selectedSize,
            gauge: "\(Int(userStitches)) maglie × \(Int(userRows)) ferri = 10 × 10 cm (Campione Utente)",
            needles: nil,
            recalculationSummary: summary,
            sections: generatedSections
        )
    }
}
