import Foundation
import Security

final class KeychainService {
    static let shared = KeychainService()
    let serviceName = "com.zetssh.credentials"
    
    private init() {}
    
    func save(password: String, forSessionId sessionId: UUID) throws {
        guard let data = password.data(using: .utf8) else { return }
        
        let account = sessionId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
        }
    }
    
    func fetchPassword(forSessionId sessionId: UUID) throws -> String? {
        let account = sessionId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess, let data = dataTypeRef as? Data, let password = String(data: data, encoding: .utf8) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
        }
        
        return password
    }
    
    func deletePassword(forSessionId sessionId: UUID) throws {
        let account = sessionId.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
        }
    }

    // MARK: - Passphrase (private key)

    /// Stores the passphrase for a private key associated with `sessionId`.
    /// The account key is distinct from the password key (`"\(id)-passphrase"`).
    func savePassphrase(_ passphrase: String, forSessionId sessionId: UUID) throws {
        guard let data = passphrase.data(using: .utf8) else { return }
        let account = "\(sessionId.uuidString)-passphrase"

        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      serviceName,
            kSecAttrAccount as String:      account,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
        }
    }

    /// Returns the stored passphrase, or `nil` if none was saved (key has no passphrase).
    func fetchPassphrase(forSessionId sessionId: UUID) throws -> String? {
        let account = "\(sessionId.uuidString)-passphrase"

        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      serviceName,
            kSecAttrAccount as String:      account,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecItemNotFound { return nil }

        guard status == errSecSuccess,
              let data = dataTypeRef as? Data,
              let passphrase = String(data: data, encoding: .utf8) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
        }
        return passphrase
    }

    /// Removes the stored passphrase. Safe to call even if none exists.
    func deletePassphrase(forSessionId sessionId: UUID) throws {
        let account = "\(sessionId.uuidString)-passphrase"

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
        }
    }
}
