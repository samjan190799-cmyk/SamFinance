import Foundation
import Security

/// Ключ облачного ИИ. Пользователь его не вводит: он задан сборкой (AIConfig) и подходит только тому сервису,
/// для которого сборка его получила. Ключи, которые люди вписывали в Настройках раньше, лежали в Keychain:
/// `removeLegacyKeys` их стирает, чтобы чужой старый ключ не оставался на телефоне.
enum AIKeyStore {
    /// Ключ сервиса или nil, если сборка без ключа или он выдан другому сервису
    static func key(for provider: AIProvider, config: AIConfig = .standard) -> String? {
        config.provider == provider ? config.apiKey : nil
    }

    private static let account = "default"

    /// Имена записей Keychain, под которыми ключи хранились до встроенного ключа
    private static func legacyService(for provider: AIProvider) -> String {
        switch provider {
        case .claude: return "com.samvel.samfinance.anthropic-api-key"
        case .openAI: return "com.samvel.samfinance.openai-api-key"
        case .gemini: return "com.samvel.samfinance.gemini-api-key"
        }
    }

    /// Стирает ключи, вписанные пользователем в прежних версиях. Безопасно вызывать при каждом запуске.
    static func removeLegacyKeys() {
        for provider in AIProvider.allCases {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: legacyService(for: provider),
                kSecAttrAccount as String: account
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}
