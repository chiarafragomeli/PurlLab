import Foundation

struct GeneratedGuideResponse: Codable {
    let patternTitle: String
    let designer: String?
    let targetSize: String
    let gauge: String?
    let needles: [String]?
    var recalculationSummary: String?
    var changedStepTitles: [String]? = nil
    let sections: [GeneratedSection]
}

struct GaugeStepSnapshot: Codable, Sendable {
    var stepId: String? = nil
    let index: Int
    let sectionTitle: String
    let title: String
    let stepType: String
    let instruction: String
    let subSteps: [String]
    let repeatVariations: [String]
    let rowsPerRepeat: Int?
    let totalRepeats: Int?
    let stitchCountBefore: Int?
    let stitchCountAfter: Int?
    let targetMeasureCm: Double?
    let hasCounter: Bool
    let counterLabel: String?
    var counterKind: String? = nil
    let targetStepCount: Int?
    let sourcePage: Int?
    let sourceQuote: String?
}

struct GaugeTextReplacement: Codable, Sendable {
    let original: String
    let replacement: String
}

struct GaugeStepPatch: Codable, Sendable {
    let index: Int
    let stitchCountBefore: Int?
    let stitchCountAfter: Int?
    let rowsPerRepeat: Int?
    let totalRepeats: Int?
    let targetStepCount: Int?
    let replacements: [GaugeTextReplacement]?
}

struct GaugePatchResponse: Codable, Sendable {
    let recalculationSummary: String?
    let steps: [GaugeStepPatch]
}

struct GeneratedSection: Codable {
    let name: String
    let steps: [GeneratedStep]
}

struct GeneratedStep: Codable {
    var stepId: String? = nil
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
    var counterKind: String? = nil
    let targetStepCount: Int?
    let sourcePage: Int?
    let sourceQuote: String?
}

enum GeminiError: LocalizedError {
    case missingApiKey
    case invalidApiKeyFormat
    case invalidApiKey(String)
    case invalidURL
    case networkError(String)
    case parsingError(String)
    case invalidInput(String)
    
    var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "Chiave API di Gemini non trovata. Inseriscila nelle Impostazioni."
        case .invalidApiKeyFormat:
            return "La chiave API inserita sembra troppo corta o non valida. Inserisci una chiave valida da Google AI Studio."
        case .invalidApiKey(let msg):
            return "Autorizzazione Gemini non valida: \(msg)"
        case .invalidURL:
            return "URL dell'endpoint non valido."
        case .networkError(let msg):
            return "Errore di rete: \(msg)"
        case .parsingError(let msg):
            return "Errore nell'interpretazione della risposta: \(msg)"
        case .invalidInput(let msg):
            return "Input non valido: \(msg)"
        }
    }
}

final class GeminiService: @unchecked Sendable {
    static let shared = GeminiService()
    
    // MARK: - Modelli Gemini Centralizzati
    // gemini-2.5-flash è il modello primario ad alta velocità e stabilità di produzione
    // gemini-3-flash-preview funge da fallback avanzato
    static let primaryModel = "gemini-2.5-flash"
    static let fallbackModel = "gemini-3-flash-preview"
    static let candidateModels = [primaryModel, fallbackModel]
    
    // Sessione HTTP dedicata con timeout esteso a 180s per request
    // per consentire ingestion PDF pesanti (base64) e generazione JSON complessa
    // senza subire il timeout di default a 60s di URLSession.shared
    private static let apiSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 300
        config.networkServiceType = .responsiveData
        return URLSession(configuration: config)
    }()
    
    /// Costruisce una generationConfig ottimizzata per il modello:
    /// - Gemini 3.x adotta `thinkingLevel: "low"` per evitare l'overhead del default "high" ed errori di parametri deprecati.
    /// - Gemini 2.5 Flash adotta `thinkingBudget: 1024` per un ragionamento matematico rapido senza timeout.
    private static func buildGenerationConfig(for model: String, schema: [String: Any], temperature: Double = 0.1) -> [String: Any] {
        var config: [String: Any] = [
            "response_mime_type": "application/json",
            "response_schema": schema,
            "temperature": temperature
        ]
        if model.contains("gemini-3") {
            config["thinkingConfig"] = ["thinkingLevel": "low"]
        } else {
            config["thinkingConfig"] = ["thinkingBudget": 1024]
        }
        return config
    }
    
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
        
        // URL pulito: la chiave API è inviata cifrata solo nell'header TLS (x-goog-api-key)
        // per evitare che appaia in chiaro nei log proxy o cronologia URL
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(Self.primaryModel):generateContent"
        guard let url = URL(string: urlString) else { throw GeminiError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.networkServiceType = .responsiveData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(cleanKey, forHTTPHeaderField: "x-goog-api-key")
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
    
    func generateGuide(from pdfData: Data, targetSize: String? = nil) async throws -> GeneratedGuideResponse {
        guard let rawKey = KeychainHelper.shared.getGeminiApiKey(), !rawKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiError.missingApiKey
        }
        
        let apiKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if apiKey.count < 20 {
            throw GeminiError.invalidApiKeyFormat
        }
        
        let cleanSize = targetSize?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isSizeSpecified = !cleanSize.isEmpty
        let sizeFilterPrompt = isSizeSpecified
            ? "Mostra SOLO i numeri per la taglia \"\(cleanSize)\"."
            : "Questo pattern non specifica taglie separate o è a taglia unica (es. sciarpa, coperta, scialle). Estrai i numeri e i passaggi esatti come indicati nel pattern per la taglia unica."
        
        guard pdfData.count <= 15_000_000 else {
            throw GeminiError.invalidInput("Il file PDF supera la dimensione massima supportata (15 MB).")
        }
        
        let base64Pdf = pdfData.base64EncodedString()
        
        let systemPrompt = """
        Sei una maestra di maglia (knitting) ed editor tecnica esperta.
        Il tuo compito è trasformare il pattern PDF in una GUIDA OPERATIVA INTERATTIVA a "Scheda Singola" (una card per ogni fase operativa reale) in LINGUA ITALIANA\(isSizeSpecified ? " per la TAGLIA \"\(cleanSize)\"" : " (taglia unica o come da pattern)").
        
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
           - \(sizeFilterPrompt)
           - I nomi delle sezioni ("name") e i titoli delle schede devono essere SOLO in italiano, SENZA la traduzione inglese tra parentesi (es. "Corpo" e NON "Corpo (Body)", "Sprone" e NON "Sprone (Yoke)", "Maniche" e NON "Maniche (Sleeves)").
           - Usa i termini italiani: dir (diritto), rov (rovescio), 2 dir ins (k2tog), 2 dir ins ritorto / acc (ssk / k2tog tbl), AID (M1R), AIS (M1L), MP (marcapunti), ferri accorciati alla tedesca (German short rows).
        
        5. GESTIONE DEGLI SCHEMI (CHART A QUADRETTI):
           - Se il pattern usa schemi a quadretti: NON trascrivere i singoli quadretti e NON dedurre o inventare colori.
           - Per ogni tratto lavorato a schema crea UNA SOLA SCHEDA con:
             * Titolo: il nome dello schema e la parte del lavoro (es. "Schema A, corpo").
             * Istruzione: specifica da quale quadretto/colonna si parte, il senso di lettura (gli schemi partono in basso a destra e si leggono da destra a sinistra), e le eventuali ripetizioni del motivo orizzontale.
             * sourcePage: imposta il numero di pagina dello schema per la taglia selezionata (se il pattern ha schemi diversi per taglia, usa quello della taglia scelta).
             * Contatore: hasCounter = true, counterLabel = "Riga schema [Nome]" (es. "Riga schema A"), targetStepCount = numero di righe dello schema (o delle righe da lavorare).
             * Ripetizioni di righe: per le parti che si ripetono (es. "ripetere le righe 24-39") imposta stepType = "repeat_pattern" con rowsPerRepeat e totalRepeats se calcolabili, altrimenti stepType = "work_to_measure".
           - Se un numero non è leggibile con certezza: scrivi "verificare nel PDF" nell'istruzione e lascia vuoto/null il rispettivo campo numerico.
        """
        
        let userPrompt = isSizeSpecified
            ? "Analizza il pattern PDF per la taglia \(cleanSize) e genera la guida operativa JSON completa in italiano, calcolando con precisione ferri totali, ripetizioni e maglie."
            : "Analizza il pattern PDF (a taglia unica / standard) e genera la guida operativa JSON completa in italiano, calcolando con precisione ferri totali, ripetizioni e maglie."
        
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
        
        let candidateModels = Self.candidateModels
        var lastError: Error?
        
        for model in candidateModels {
            let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
            guard let url = URL(string: urlString) else { continue }
            
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
                "generationConfig": Self.buildGenerationConfig(for: model, schema: jsonSchema, temperature: 0.1)
            ]
            
            guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else { continue }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 180
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.networkServiceType = .responsiveData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            request.httpBody = bodyData
            
            do {
                let (data, response) = try await Self.apiSession.data(for: request)
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
                } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    let errorText = String(data: data, encoding: .utf8) ?? "Status code: \(httpResponse.statusCode)"
                    throw GeminiError.invalidApiKey("Chiave API o autorizzazione non valida (HTTP \(httpResponse.statusCode)): \(errorText)")
                } else if httpResponse.statusCode == 400 {
                    let errorText = String(data: data, encoding: .utf8) ?? "Status code: 400"
                    throw GeminiError.networkError("Richiesta non valida (HTTP 400): \(errorText)")
                } else {
                    let errorText = String(data: data, encoding: .utf8) ?? "Status code: \(httpResponse.statusCode)"
                    lastError = GeminiError.networkError("HTTP \(httpResponse.statusCode): \(errorText)")
                    // Prova il modello successivo solo per errori transitori (es. 503 o 429)
                    continue
                }
            } catch let geminiErr as GeminiError {
                throw geminiErr
            } catch {
                if let urlErr = error as? URLError, urlErr.code == .timedOut {
                    lastError = GeminiError.networkError("Tempo di attesa scaduto (timeout). Il pattern è molto complesso o la connessione è lenta. Riprova.")
                } else {
                    lastError = error
                }
                continue
            }
        }
        
        throw lastError ?? GeminiError.networkError("Impossibile contattare i modelli Gemini.")
    }
    
    // MARK: - Ricalcolo Pattern per Campione Personalizzato (AI & Locale)
    
    /// Chiede a Gemini SOLO quali numeri cambiare (maglie, ferri, ripetizioni) in base al campione dell'utente.
    /// L'AI non riscrive mai i testi: restituisce coppie "originale → sostituzione" e i nuovi conteggi numerici,
    /// che l'app applica ai testi originali scartando qualsiasi modifica che non sia puramente numerica.
    func recalculateGuideForGauge(
        patternTitle: String,
        designer: String,
        targetSize: String,
        snapshots: [GaugeStepSnapshot],
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
        
        guard patternStitches > 0, patternRows > 0, userStitches > 0, userRows > 0 else {
            throw GeminiError.invalidInput("I valori del campione del pattern e dell'utente devono essere maggiori di zero.")
        }
        
        let effectiveSize = targetSize.isEmpty ? "M" : targetSize
        let stitchRatio = userStitches / patternStitches
        let rowRatio = userRows / patternRows
        
        let systemPrompt = """
        Sei una tecnica di maglia che esegue SOLO calcoli numerici. NON sei un'autrice: non scrivi, non riformuli, non inventi alcuna parola.
        
        Ricevi i passaggi esatti di un pattern (taglia "\(effectiveSize)") in JSON. Devi indicare quali NUMERI cambiano per adattare il pattern al campione dell'utente.
        
        CAMPIONE (10 × 10 cm):
        - Pattern: \(patternStitches) maglie × \(patternRows) ferri
        - Utente: \(userStitches) maglie × \(userRows) ferri
        - Fattore maglie: \(String(format: "%.4f", stitchRatio)) — Fattore ferri: \(String(format: "%.4f", rowRatio))
        
        REGOLE ASSOLUTE (ZERO CREATIVITÀ):
        1. Le istruzioni restano IDENTICHE parola per parola. Cambiano SOLO i numeri di maglie, ferri/giri e ripetizioni.
        2. NON modificare MAI: misure in cm, misure dei ferri in mm, numeri di pagina, nomi di punti, ordine dei passaggi, nomi delle sezioni.
        3. NON aggiungere né togliere passaggi, frasi, consigli o note.
        4. Ricalcolo maglie: moltiplica per il fattore maglie e arrotonda rispettando la modularità del punto (coste 1/1 = pari, coste 2/2 = multiplo di 4) e la simmetria davanti/dietro e tra le maniche.
        5. Ricalcolo ferri: le lavorazioni "a misura" mantengono i cm; aggiorna solo il numero stimato di giri (fattore ferri). Per aumenti/diminuzioni ripetuti adatta il numero di ripetizioni in modo che i totali di maglie risultino coerenti con i nuovi conteggi.
        6. Coerenza: i conteggi devono tornare da un passaggio all'altro (stitchCountAfter di un passaggio = stitchCountBefore del successivo, quando collegati).
        
        FORMATO DELLE SOSTITUZIONI ("replacements"):
        - "original" è un frammento ESATTO copiato dal testo del passaggio (titolo, istruzione, sotto-passaggi, variazioni o etichetta contatore), contenente il numero e una parola di contesto (es. "114 maglie", "per 29 volte", "58 giri", "28 m").
        - "replacement" è lo STESSO frammento con SOLO le cifre cambiate (es. "104 maglie", "per 26 volte", "52 giri", "26 m").
        - Qualsiasi sostituzione che cambi parole, punteggiatura o aggiunga testo verrà scartata automaticamente dal codice.
        - Includi solo i passaggi in cui cambia almeno un numero. Usa il campo "index" del passaggio.
        
        "recalculationSummary": un elenco sintetico e puramente numerico dei cambi principali (es. "Avvio collo: 114 → 104 m | Aumenti raglan: 29 → 26 ripetizioni"). Nessun commento aggiuntivo.
        """
        
        let snapshotJSON = String(data: try JSONEncoder().encode(snapshots), encoding: .utf8) ?? "[]"
        let userPrompt = """
        Pattern: "\(patternTitle)" — taglia \(effectiveSize).
        Passaggi (JSON):
        \(snapshotJSON)
        
        Restituisci solo le modifiche numeriche secondo le regole.
        """
        
        let jsonSchema: [String: Any] = [
            "type": "OBJECT",
            "properties": [
                "recalculationSummary": ["type": "STRING"],
                "steps": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "index": ["type": "INTEGER"],
                            "stitchCountBefore": ["type": "INTEGER"],
                            "stitchCountAfter": ["type": "INTEGER"],
                            "rowsPerRepeat": ["type": "INTEGER"],
                            "totalRepeats": ["type": "INTEGER"],
                            "targetStepCount": ["type": "INTEGER"],
                            "replacements": [
                                "type": "ARRAY",
                                "items": [
                                    "type": "OBJECT",
                                    "properties": [
                                        "original": ["type": "STRING"],
                                        "replacement": ["type": "STRING"]
                                    ],
                                    "required": ["original", "replacement"]
                                ]
                            ]
                        ],
                        "required": ["index"]
                    ]
                ]
            ],
            "required": ["recalculationSummary", "steps"]
        ]
        
        let candidateModels = Self.candidateModels
        var lastError: Error?
        
        for model in candidateModels {
            let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
            guard let url = URL(string: urlString) else { continue }
            
            let requestBody: [String: Any] = [
                "contents": [
                    ["role": "user", "parts": [["text": userPrompt]]]
                ],
                "system_instruction": [
                    "parts": [["text": systemPrompt]]
                ],
                "generationConfig": Self.buildGenerationConfig(for: model, schema: jsonSchema, temperature: 0.0)
            ]
            
            guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else { continue }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 180
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.networkServiceType = .responsiveData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            request.httpBody = bodyData
            
            do {
                let (data, response) = try await Self.apiSession.data(for: request)
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
                    
                    let patch = try JSONDecoder().decode(GaugePatchResponse.self, from: jsonData)
                    return Self.applyGaugePatch(
                        snapshots: snapshots,
                        patch: patch,
                        patternTitle: patternTitle,
                        designer: designer,
                        targetSize: effectiveSize,
                        userStitches: userStitches,
                        userRows: userRows
                    )
                } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    let errorText = String(data: data, encoding: .utf8) ?? "Status code: \(httpResponse.statusCode)"
                    throw GeminiError.invalidApiKey("Chiave API o autorizzazione non valida (HTTP \(httpResponse.statusCode)): \(errorText)")
                } else if httpResponse.statusCode == 400 {
                    let errorText = String(data: data, encoding: .utf8) ?? "Status code: 400"
                    throw GeminiError.networkError("Richiesta non valida (HTTP 400): \(errorText)")
                } else {
                    let errorText = String(data: data, encoding: .utf8) ?? "Status code: \(httpResponse.statusCode)"
                    lastError = GeminiError.networkError("HTTP \(httpResponse.statusCode): \(errorText)")
                    continue
                }
            } catch let geminiErr as GeminiError {
                throw geminiErr
            } catch {
                lastError = error
                continue
            }
        }
        
        throw lastError ?? GeminiError.networkError("Impossibile contattare i modelli Gemini per il ricalcolo.")
    }
    
    /// Una sostituzione è accettata solo se cambia esclusivamente cifre (stesse parole, stessa punteggiatura)
    /// e non tocca misure in cm/mm o numeri di pagina.
    static func isNumericOnlyChange(original: String, replacement: String) -> Bool {
        guard !original.isEmpty, original != replacement else { return false }
        let strip: (String) -> String = { $0.filter { !$0.isNumber } }
        guard strip(original) == strip(replacement) else { return false }
        guard original.contains(where: { $0.isNumber }) else { return false }
        let lower = original.lowercased()
        let protected = ["cm", "mm", "pag", "pagina"]
        return !protected.contains(where: { lower.contains($0) })
    }
    
    /// Formatta i valori numerici del gauge preservando i decimali (es. 21.5 m)
    static func formatGaugeNumber(_ val: Double) -> String {
        val.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(val))" : String(format: "%.1f", val)
    }
    
    /// Esegue la sostituzione numerica in un'unica passata sull'intera stringa,
    /// garantendo assenza di collisioni a cascata, rispetto dei boundary numerici (es. '4' dentro '114')
    /// e distinzione esatta tra unità (es. 'm' vs 'mm').
    static func replaceNumbersInText(
        _ text: String,
        stitchMap: [Int: Int] = [:],
        repeatMap: [Int: Int] = [:],
        rowMap: [Int: Int] = [:]
    ) -> String {
        guard !text.isEmpty, (!stitchMap.isEmpty || !repeatMap.isEmpty || !rowMap.isEmpty) else {
            return text
        }
        
        let pattern = #"(?<![\d.,])(\d+)(?![\d.,])(\s*)(maglie\b|punti\b|ripetizioni\b|volte\b|cicli\b|ferri\b|giri\b|m\b|m\.)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        guard !matches.isEmpty else { return text }
        
        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            guard match.numberOfRanges >= 4 else { continue }
            let numRange = match.range(at: 1)
            let spacingRange = match.range(at: 2)
            let unitRange = match.range(at: 3)
            
            let numStr = nsString.substring(with: numRange)
            guard let oldVal = Int(numStr) else { continue }
            
            let spacing = nsString.substring(with: spacingRange)
            let unitStr = nsString.substring(with: unitRange)
            let unitLower = unitStr.lowercased()
            
            let targetNewVal: Int?
            if ["maglie", "punti", "m", "m."].contains(unitLower) {
                targetNewVal = stitchMap[oldVal] ?? rowMap[oldVal]
            } else if ["volte", "ripetizioni", "cicli"].contains(unitLower) {
                targetNewVal = repeatMap[oldVal]
            } else if ["ferri", "giri"].contains(unitLower) {
                targetNewVal = rowMap[oldVal]
            } else {
                targetNewVal = nil
            }
            
            if let newVal = targetNewVal, newVal != oldVal {
                let replacement = "\(newVal)\(spacing)\(unitStr)"
                mutable.replaceCharacters(in: match.range, with: replacement)
            }
        }
        
        return mutable as String
    }
    
    /// Applica la patch numerica ai testi ORIGINALI dei passaggi: i testi non vengono mai riscritti dall'AI,
    /// vengono solo sostituiti i frammenti numerici validati.
    static func applyGaugePatch(
        snapshots: [GaugeStepSnapshot],
        patch: GaugePatchResponse,
        patternTitle: String,
        designer: String,
        targetSize: String,
        userStitches: Double,
        userRows: Double
    ) -> GeneratedGuideResponse {
        let patchByIndex = Dictionary(patch.steps.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
        var changeLog: [String] = []
        var discarded = 0
        
        var sectionOrder: [String] = []
        var stepsBySection: [String: [GeneratedStep]] = [:]
        
        for snap in snapshots {
            var title = snap.title
            var instruction = snap.instruction
            var subSteps = snap.subSteps
            var variations = snap.repeatVariations
            var counterLabel = snap.counterLabel
            var stepChanged = false
            
            let p = patchByIndex[snap.index]
            
            // 1. Applica le sostituzioni testuali puntuali validate (solo cifre cambiate)
            for rep in p?.replacements ?? [] {
                guard isNumericOnlyChange(original: rep.original, replacement: rep.replacement) else {
                    discarded += 1
                    continue
                }
                let allTexts = [title, instruction, counterLabel ?? ""] + subSteps + variations
                guard allTexts.contains(where: { $0.contains(rep.original) }) else {
                    discarded += 1
                    continue
                }
                title = title.replacingOccurrences(of: rep.original, with: rep.replacement)
                instruction = instruction.replacingOccurrences(of: rep.original, with: rep.replacement)
                subSteps = subSteps.map { $0.replacingOccurrences(of: rep.original, with: rep.replacement) }
                variations = variations.map { $0.replacingOccurrences(of: rep.original, with: rep.replacement) }
                counterLabel = counterLabel?.replacingOccurrences(of: rep.original, with: rep.replacement)
                stepChanged = true
            }
            
            // 2. Campi numerici aggiornati solo se presenti nel passaggio originale
            let newBefore = snap.stitchCountBefore != nil ? (p?.stitchCountBefore ?? snap.stitchCountBefore) : nil
            let newAfter = snap.stitchCountAfter != nil ? (p?.stitchCountAfter ?? snap.stitchCountAfter) : nil
            let newRowsPerRepeat = snap.rowsPerRepeat != nil ? (p?.rowsPerRepeat ?? snap.rowsPerRepeat) : nil
            let newRepeats = snap.totalRepeats != nil ? (p?.totalRepeats ?? snap.totalRepeats) : nil
            var newTarget = snap.targetStepCount != nil ? (p?.targetStepCount ?? snap.targetStepCount) : nil
            if snap.stepType == "repeat_pattern", let r = newRepeats, let rpr = newRowsPerRepeat {
                newTarget = r * rpr
            }
            
            // 3. Allineamento automatico dei numeri nei testi in unica passata sicura
            var stitchMap: [Int: Int] = [:]
            if let oldB = snap.stitchCountBefore, let recB = newBefore, oldB != recB {
                stitchMap[oldB] = recB
            }
            if let oldA = snap.stitchCountAfter, let recA = newAfter, oldA != recA {
                stitchMap[oldA] = recA
            }
            
            var repeatMap: [Int: Int] = [:]
            if let oldR = snap.totalRepeats, let recR = newRepeats, oldR != recR {
                repeatMap[oldR] = recR
            }
            
            var rowMap: [Int: Int] = [:]
            if let oldT = snap.targetStepCount, let recT = newTarget, oldT != recT {
                rowMap[oldT] = recT
            }
            
            title = replaceNumbersInText(title, stitchMap: stitchMap, repeatMap: repeatMap, rowMap: rowMap)
            instruction = replaceNumbersInText(instruction, stitchMap: stitchMap, repeatMap: repeatMap, rowMap: rowMap)
            subSteps = subSteps.map { replaceNumbersInText($0, stitchMap: stitchMap, repeatMap: repeatMap, rowMap: rowMap) }
            variations = variations.map { replaceNumbersInText($0, stitchMap: stitchMap, repeatMap: repeatMap, rowMap: rowMap) }
            if let lbl = counterLabel {
                counterLabel = replaceNumbersInText(lbl, stitchMap: stitchMap, repeatMap: repeatMap, rowMap: rowMap)
            }
            
            if newBefore != snap.stitchCountBefore || newAfter != snap.stitchCountAfter
                || newRepeats != snap.totalRepeats || newTarget != snap.targetStepCount
                || newRowsPerRepeat != snap.rowsPerRepeat {
                stepChanged = true
            }
            if stepChanged {
                changeLog.append(snap.title.isEmpty ? snap.sectionTitle : snap.title)
            }
            
            let genStep = GeneratedStep(
                stepId: snap.stepId,
                title: title,
                stepType: snap.stepType,
                instruction: instruction,
                subSteps: subSteps,
                repeatVariations: variations,
                rowsPerRepeat: newRowsPerRepeat,
                totalRepeats: newRepeats,
                stitchCountBefore: newBefore,
                stitchCountAfter: newAfter,
                targetMeasureCm: snap.targetMeasureCm,
                hasCounter: snap.hasCounter,
                counterLabel: counterLabel,
                counterKind: snap.counterKind,
                targetStepCount: newTarget,
                sourcePage: snap.sourcePage,
                sourceQuote: snap.sourceQuote
            )
            
            if stepsBySection[snap.sectionTitle] == nil {
                stepsBySection[snap.sectionTitle] = []
                sectionOrder.append(snap.sectionTitle)
            }
            stepsBySection[snap.sectionTitle]?.append(genStep)
        }
        
        var summary = patch.recalculationSummary ?? ""
        summary += summary.isEmpty ? "" : "\n"
        summary += "Testi originali preservati parola per parola: aggiornati solo i numeri in \(changeLog.count) schede."
        if discarded > 0 {
            summary += " (\(discarded) modifiche non numeriche scartate)."
        }
        
        return GeneratedGuideResponse(
            patternTitle: patternTitle,
            designer: designer,
            targetSize: targetSize,
            gauge: "\(formatGaugeNumber(userStitches)) maglie × \(formatGaugeNumber(userRows)) ferri = 10 × 10 cm (Campione Utente)",
            needles: nil,
            recalculationSummary: summary,
            changedStepTitles: changeLog,
            sections: sectionOrder.map { GeneratedSection(name: $0, steps: stepsBySection[$0] ?? []) }
        )
    }
    
    /// Ricalcolo matematico locale istantaneo di fallback (funziona anche offline e senza API key),
    /// mantiene i testi identici parola per parola sostituendo esclusivamente i valori numerici.
    static func recalculateGuideLocally(
        project: KnittingProject,
        patternStitches: Double,
        patternRows: Double,
        userStitches: Double,
        userRows: Double
    ) -> GeneratedGuideResponse? {
        guard patternStitches > 0, patternRows > 0, userStitches > 0, userRows > 0 else {
            return nil
        }
        
        let stitchRatio = userStitches / patternStitches
        let rowRatio = userRows / patternRows
        
        let sortedSteps = project.guideSteps.sorted(by: { $0.orderIndex < $1.orderIndex })
        
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
        var changedTitles: [String] = []
        
        // Riconciliazione topologica catena maglie: stitchCountBefore(n+1) = stitchCountAfter(n) quando collegati
        var previousCalculatedAfter: Int? = nil
        var previousOriginalAfter: Int? = nil
        
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
                var newSubSteps = step.safeSubSteps
                var newVariations = step.safeRepeatVariations
                var newCounterLabel = step.counterLabel
                
                // Ricalcola maglie con continuità verificata
                if let b = step.stitchCountBefore, b > 0 {
                    if let prevOrig = previousOriginalAfter, let prevCalc = previousCalculatedAfter, b == prevOrig {
                        newBefore = prevCalc
                    } else {
                        var recalculatedB = max(1, Int(round(Double(b) * stitchRatio)))
                        if step.sectionTitle.localizedCaseInsensitiveContains("Collo") || step.title.localizedCaseInsensitiveContains("Avvio") {
                            if recalculatedB % 2 != 0 { recalculatedB += 1 }
                        }
                        newBefore = recalculatedB
                    }
                }
                if let a = step.stitchCountAfter, a > 0 {
                    if let b = step.stitchCountBefore, b == a, let nb = newBefore {
                        newAfter = nb
                    } else {
                        var recalculatedA = max(1, Int(round(Double(a) * stitchRatio)))
                        if step.sectionTitle.localizedCaseInsensitiveContains("Collo") || step.title.localizedCaseInsensitiveContains("Avvio") {
                            if recalculatedA % 2 != 0 { recalculatedA += 1 }
                        }
                        newAfter = recalculatedA
                    }
                }
                
                if step.stitchCountAfter != nil {
                    previousOriginalAfter = step.stitchCountAfter
                    previousCalculatedAfter = newAfter
                }
                
                // Ricalcola ferri / ripetizioni
                if step.stepType == "repeat_pattern" {
                    if let repeats = step.totalRepeats, repeats > 0 {
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
                
                // Aggiorna i testi in un'unica passata sicura con regex (zero collisioni a cascata)
                var stitchMap: [Int: Int] = [:]
                if let oldB = step.stitchCountBefore, let recB = newBefore, oldB != recB {
                    stitchMap[oldB] = recB
                }
                if let oldA = step.stitchCountAfter, let recA = newAfter, oldA != recA {
                    stitchMap[oldA] = recA
                }
                
                var repeatMap: [Int: Int] = [:]
                if let oldR = step.totalRepeats, let recR = newTotalRepeats, oldR != recR {
                    repeatMap[oldR] = recR
                }
                
                var rowMap: [Int: Int] = [:]
                if let oldT = step.targetStepCount, let recT = newTargetStepCount, oldT != recT {
                    rowMap[oldT] = recT
                }
                
                newTitle = replaceNumbersInText(newTitle, stitchMap: stitchMap, repeatMap: repeatMap, rowMap: rowMap)
                newInstruction = replaceNumbersInText(newInstruction, stitchMap: stitchMap, repeatMap: repeatMap, rowMap: rowMap)
                newSubSteps = newSubSteps.map { replaceNumbersInText($0, stitchMap: stitchMap, repeatMap: repeatMap, rowMap: rowMap) }
                newVariations = newVariations.map { replaceNumbersInText($0, stitchMap: stitchMap, repeatMap: repeatMap, rowMap: rowMap) }
                if let lbl = newCounterLabel {
                    newCounterLabel = replaceNumbersInText(lbl, stitchMap: stitchMap, repeatMap: repeatMap, rowMap: rowMap)
                }
                
                if newBefore != step.stitchCountBefore || newAfter != step.stitchCountAfter
                    || newTotalRepeats != step.totalRepeats || newTargetStepCount != step.targetStepCount {
                    changedTitles.append(newTitle.isEmpty ? secTitle : newTitle)
                }
                
                let genStep = GeneratedStep(
                    stepId: step.id.uuidString,
                    title: newTitle,
                    stepType: step.stepType,
                    instruction: newInstruction,
                    subSteps: newSubSteps,
                    repeatVariations: newVariations,
                    rowsPerRepeat: step.rowsPerRepeat,
                    totalRepeats: newTotalRepeats,
                    stitchCountBefore: newBefore,
                    stitchCountAfter: newAfter,
                    targetMeasureCm: step.targetMeasureCm,
                    hasCounter: step.hasCounter,
                    counterLabel: newCounterLabel,
                    counterKind: step.counterKind,
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
        let patStsStr = formatGaugeNumber(patternStitches)
        let patRowsStr = formatGaugeNumber(patternRows)
        let userStsStr = formatGaugeNumber(userStitches)
        let userRowsStr = formatGaugeNumber(userRows)
        let summary = "Ricalcolo Matematico Locale: Campione adattato da \(patStsStr) m × \(patRowsStr) f a \(userStsStr) m × \(userRowsStr) f per 10 cm (Maglie: \(stitchPct), Ferri: \(rowPct)). Testi originali intatti: aggiornati solo i numeri in \(changedTitles.count) schede."
        
        return GeneratedGuideResponse(
            patternTitle: project.title,
            designer: project.designer,
            targetSize: project.selectedSize,
            gauge: "\(userStsStr) maglie × \(userRowsStr) ferri = 10 × 10 cm (Campione Utente)",
            needles: nil,
            recalculationSummary: summary,
            changedStepTitles: changedTitles,
            sections: generatedSections
        )
    }
}
