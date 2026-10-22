import Foundation
import Security

/// Ключи облачных ИИ пользователя в Keychain: у каждого сервиса своя запись. Доступны только при разблокированном
/// телефоне, не переезжают на другие устройства и в резервные копии, в файлах приложения не хранятся.
enum AIKeyStore {
    private static let account = "default"

    /// Запись Claude осталась под прежним именем: ключи, сохранённые до появления выбора сервиса, продолжают работать
    private static func service(for provider: AIProvider) -> String {
        switch provider {
        case .claude: return "com.samvel.samfinance.anthropic-api-key"
        case .openAI: return "com.samvel.samfinance.openai-api-key"
        case .gemini: return "com.samvel.samfinance.gemini-api-key"
        }
    }

    private static func baseQuery(for provider: AIProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(for: provider),
            kSecAttrAccount as String: account
        ]
    }

    /// Сохраняет (или заменяет) ключ. Возвращает false, если Keychain отказал в записи.
    @discardableResult
    static func setKey(_ key: String, for provider: AIProvider) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }

        let status = SecItemUpdate(
            baseQuery(for: provider) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var query = baseQuery(for: provider)
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    /// Ключ или nil, если его нет или телефон заблокирован
    static func key(for provider: AIProvider) -> String? {
        var query = baseQuery(for: provider)
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

    static func deleteKey(for provider: AIProvider) {
        SecItemDelete(baseQuery(for: provider) as CFDictionary)
    }
}
