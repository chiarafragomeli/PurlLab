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
    let instruction: String
    let stitchCountAfter: Int?
    let targetMeasureCm: Double?
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
        
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidURL
        }
        
        let base64Pdf = pdfData.base64EncodedString()
        
        let systemPrompt = """
        Sei un'esperta direttrice tecnica ed editor di pattern di maglia (knitting).
        Il tuo compito è convertire il pattern PDF fornito in una guida passo-passo rigorosa, chiara e cronologica in LINGUA ITALIANA.
        
        TAGLIA RICHIESTA DALL'UTENTE: "\(targetSize)".
        
        REGOLE FONDAMENTALI:
        1. Filtra ed elimina tutti i numeri tra parentesi che non appartengono alla taglia scelta "\(targetSize)". Mostra solo ed esclusivamente i numeri corretti per questa taglia (es. numero di maglie da avviare, ferri, ripetizioni).
        2. Glossario tecnico obbligatorio dall'inglese all'italiano:
           - k (knit) -> dir (diritto)
           - p (purl) -> rov (rovescio)
           - stockinette stitch -> maglia rasata
           - garter stitch -> maglia legaccio
           - rib / ribbing -> coste (es. 1/1 o 2/2)
           - k2tog -> 2 dir ins (2 maglie insieme a diritto)
           - k2tog tbl / ssk -> acc (accavallato semplice) o 2 dir ins ritorto
           - M1R / M1L -> AID (aumento intercalare destro) / AIS (aumento intercalare sinistro)
           - yo (yarn over) -> gett (gettato)
           - cast on / bind off -> avvia / intreccia (chiudi)
           - marker -> marcapunti
           - short rows / German short rows -> ferri accorciati / ferri accorciati alla tedesca
        3. Suddividi il lavoro in sezioni logiche (es: Avvio e Collo, Sprone e Aumenti, Separazione Maniche, Corpo, Maniche).
        4. Ogni step deve avere:
           - instruction: testo chiaro in italiano
           - stitchCountAfter: numero totale di maglie sul ferro al termine dello step (se applicabile o calcolabile)
           - targetMeasureCm: misura in cm da raggiungere (se applicabile, es. 4 cm a coste)
           - sourcePage: numero della pagina del PDF da cui è tratta l'istruzione (1-based)
           - sourceQuote: breve frase originale in inglese dal PDF
        5. Rispondi ESCLUSIVAMENTE con un oggetto JSON valido conforme allo schema specificato.
        """
        
        let userPrompt = "Analizza questo pattern per la taglia \(targetSize) e genera la guida JSON passo-passo completa in italiano."
        
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
                                        "instruction": ["type": "STRING"],
                                        "stitchCountAfter": ["type": "INTEGER"],
                                        "targetMeasureCm": ["type": "NUMBER"],
                                        "sourcePage": ["type": "INTEGER"],
                                        "sourceQuote": ["type": "STRING"]
                                    ],
                                    "required": ["instruction"]
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
                "temperature": 0.1
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.networkError("Risposta del server non valida")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Status code: \(httpResponse.statusCode)"
            throw GeminiError.networkError("HTTP \(httpResponse.statusCode): \(errorText)")
        }
        
        // Parsing Gemini response structure
        struct GeminiAPIResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable {
                        let text: String?
                    }
                    let parts: [Part]?
                }
                let content: Content?
            }
            let candidates: [Candidate]?
        }
        
        let apiResponse = try JSONDecoder().decode(GeminiAPIResponse.self, from: data)
        guard let jsonString = apiResponse.candidates?.first?.content?.parts?.first?.text,
              let jsonData = jsonString.data(using: .utf8) else {
            throw GeminiError.parsingError("Nessun testo JSON generato da Gemini")
        }
        
        let guideResponse = try JSONDecoder().decode(GeneratedGuideResponse.self, from: jsonData)
        return guideResponse
    }
}
