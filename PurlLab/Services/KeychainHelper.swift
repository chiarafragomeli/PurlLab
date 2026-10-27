import Foundation
import Security

final class KeychainHelper: @unchecked Sendable {
    static let shared = KeychainHelper()
    private let service = "com.chiara.PurlLab"
    private let geminiKeyAccount = "gemini_api_key"
    
    private init() {
        // Pulizia di sicurezza: rimuove eventuali chiavi API residue memorizzate
        // in chiaro nei UserDefaults da versioni precedenti
        UserDefaults.standard.removeObject(forKey: geminiKeyAccount)
    }
    
    static let defaultVerifiedKey = "REDACTED_GEMINI_API_KEY"
    
    /// Salva la chiave API esclusivamente nel Secure Enclave / Keychain di iOS
    /// con protezione vincolata a questo singolo dispositivo (non esportabile in backup non cifrati)
    func saveGeminiApiKey(_ key: String) -> Bool {
        // Garantisce che nessun dato sensibile finisca in UserDefaults
        UserDefaults.standard.removeObject(forKey: geminiKeyAccount)
        
        guard let data = key.data(using: .utf8) else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: geminiKeyAccount
        ]
        
        SecItemDelete(query as CFDictionary)
        
        var newQuery = query
        newQuery[kSecValueData as String] = data
        // Protezione massima: accessibile solo dopo il primo sblocco e vincolato a questo specifico dispositivo
        newQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        
        let status = SecItemAdd(newQuery as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Recupera la chiave API dal Keychain di sistema
    func getGeminiApiKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: geminiKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data, let str = String(data: data, encoding: .utf8), !str.isEmpty {
            // Se nel keychain era rimasta una chiave legacy non valida, ripristina la chiave verificata
            if str.hasPrefix("REDACTED_GEMINI_API_KEY") {
                _ = saveGeminiApiKey(Self.defaultVerifiedKey)
                return Self.defaultVerifiedKey
            }
            return str
        }
        
        // Se non ancora presente nel Keychain, salva la chiave predefinita in modo sicuro
        _ = saveGeminiApiKey(Self.defaultVerifiedKey)
        return Self.defaultVerifiedKey
    }
    
    /// Rimuove la chiave API dal Keychain di sistema
    func deleteGeminiApiKey() {
        UserDefaults.standard.removeObject(forKey: geminiKeyAccount)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: geminiKeyAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
