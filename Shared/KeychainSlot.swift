import Foundation
import Security

/// One generic-password Keychain item. Secrets never go to UserDefaults or SwiftData (PRD 8.3).
struct KeychainSlot {
    let service: String
    let account: String

    private var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    func read() -> String? {
        var out: AnyObject?
        guard SecItemCopyMatching(base.merging([kSecReturnData as String: true], uniquingKeysWith: { $1 }) as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    func write(_ value: String) {
        SecItemDelete(base as CFDictionary)
        SecItemAdd(base.merging([kSecValueData as String: Data(value.utf8),
                                 kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly],
                                uniquingKeysWith: { $1 }) as CFDictionary, nil)
    }
    func clear() { SecItemDelete(base as CFDictionary) }
}
