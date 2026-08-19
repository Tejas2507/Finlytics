import Foundation
import Security

class KeychainHelper {
    static let shared = KeychainHelper()
    private let service = "com.finsense.app"
    
    func save(_ data: String, for account: String) {
        let data = Data(data.utf8)
        let baseQuery = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as [String : Any]
        let addQuery = baseQuery.merging([
            kSecValueData: data
        ] as [String : Any]) { _, new in new }
        
        SecItemDelete(baseQuery as CFDictionary)
        SecItemAdd(addQuery as CFDictionary, nil)
    }
    
    func read(for account: String) -> String? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as [String : Any]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess {
            if let data = dataTypeRef as? Data {
                return String(data: data, encoding: .utf8)
            }
        }
        return nil
    }
}
