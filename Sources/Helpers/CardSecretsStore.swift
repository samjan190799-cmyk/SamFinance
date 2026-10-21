import Foundation
import Security

/// Хранилище полных номеров карт в Keychain. В JSON-файлах остаются только последние 4 цифры (`Card.last4`),
/// а CVV приложение не хранит вообще.
/// Записи доступны только при разблокированном устройстве и не переезжают на другие устройства и в резервные копии.
public enum CardSecretsStore {
    private static let service = "com.samvel.samfinance.card-number"

    private static func baseQuery(for id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
    }

    /// Сохраняет (или заменяет) номер карты. Возвращает false, если Keychain отказал в записи.
    @discardableResult
    public static func setNumber(_ number: String, for id: UUID) -> Bool {
        guard let data = number.data(using: .utf8) else { return false }

        let status = SecItemUpdate(
            baseQuery(for: id) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var query = baseQuery(for: id)
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    /// Полный номер карты или nil, если его нет (карта создана на другом устройстве) или устройство заблокировано
    public static func number(for id: UUID) -> String? {
        var query = baseQuery(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public static func deleteNumber(for id: UUID) {
        SecItemDelete(baseQuery(for: id) as CFDictionary)
    }

    /// Удаляет номера всех карт приложения
    public static func deleteAll() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ] as CFDictionary)
    }
}
