import Foundation
import Security

final class KeychainHelper: @unchecked Sendable {
    static let shared = KeychainHelper()
    private let service = "com.chiara.PurlLab"
    private let geminiKeyAccount = "gemini_api_key"
    
    private init() {}
    
    func saveGeminiApiKey(_ key: String) -> Bool {
        UserDefaults.standard.set(key, forKey: geminiKeyAccount)
        
        guard let data = key.data(using: .utf8) else { return true }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: geminiKeyAccount
        ]
        
        SecItemDelete(query as CFDictionary)
        
        var newQuery = query
        newQuery[kSecValueData as String] = data
        newQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        
        _ = SecItemAdd(newQuery as CFDictionary, nil)
        return true
    }
    
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
        
        if let userDef = UserDefaults.standard.string(forKey: geminiKeyAccount), !userDef.isEmpty {
            return userDef
        }
        
        // Chiave verificata di fallback
        return "REDACTED_GEMINI_API_KEY"
    }
    
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
