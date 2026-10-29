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
        
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        
        var newQuery = query
        newQuery[kSecValueData as String] = data
        newQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        
        let addStatus = SecItemAdd(newQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }
    
    /// Recupera la chiave API dal Keychain di sistema senza effetti collaterali
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
            return str
        }
        
        return nil
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
