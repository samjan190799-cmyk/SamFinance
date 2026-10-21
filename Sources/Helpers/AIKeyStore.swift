import Foundation
import Security

/// Ключ Claude API пользователя в Keychain. Доступен только при разблокированном телефоне,
/// не переезжает на другие устройства и в резервные копии, в файлах приложения не хранится.
public enum AIKeyStore {
    private static let service = "com.samvel.samfinance.anthropic-api-key"
    private static let account = "default"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// Сохраняет (или заменяет) ключ. Возвращает false, если Keychain отказал в записи.
    @discardableResult
    public static func setKey(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }

        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    /// Ключ или nil, если его нет или телефон заблокирован
    public static func key() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    public static func deleteKey() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
