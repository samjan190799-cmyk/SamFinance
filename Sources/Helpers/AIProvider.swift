import Foundation

/// Облачный ИИ, на котором работает чат. Выбор лежит в UserDefaults (это не секрет),
/// ключ каждого сервиса хранится отдельно в Keychain (AIKeyStore).
enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case claude
    case openAI
    case gemini

    var id: String { rawValue }

    /// Ключ UserDefaults, под которым хранится выбранный сервис
    static let storageKey = "aiProvider"

    /// Выбранный в настройках сервис; по умолчанию Claude, как было до появления выбора
    static var selected: AIProvider {
        UserDefaults.standard.string(forKey: storageKey).flatMap { AIProvider(rawValue: $0) } ?? .claude
    }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .openAI: return "ChatGPT"
        case .gemini: return "Gemini"
        }
    }

    /// Кому уходят запросы
    var company: String {
        switch self {
        case .claude: return "Anthropic"
        case .openAI: return "OpenAI"
        case .gemini: return "Google"
        }
    }

    // MARK: - Ключ

    var keyPlaceholder: String {
        switch self {
        case .claude: return "sk-ant-…"
        case .openAI: return "sk-…"
        case .gemini: return "Ключ из Google AI Studio"
        }
    }

    var keyFormatHint: String {
        switch self {
        case .claude:
            return "Ключ Claude начинается с «sk-ant-». Скопируйте его из консоли Anthropic целиком."
        case .openAI:
            return "Ключ OpenAI начинается с «sk-». Нужен ключ API с platform.openai.com, а не пароль или подписка ChatGPT."
        case .gemini:
            return "Ключ Gemini не похож на ключ API. Скопируйте его из Google AI Studio целиком."
        }
    }

    /// Грубая проверка формата, чтобы не отправлять в Keychain очевидно чужой текст
    func isPlausibleKey(_ key: String) -> Bool {
        guard !key.contains(where: \.isWhitespace) else { return false }
        switch self {
        case .claude: return key.hasPrefix("sk-ant-")
        case .openAI: return key.hasPrefix("sk-") && !key.hasPrefix("sk-ant-")
        case .gemini: return key.count >= 20
        }
    }

    var consoleURL: URL {
        switch self {
        case .claude: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")!
        }
    }

    var consoleLinkTitle: String {
        switch self {
        case .claude: return "Создать ключ в консоли Anthropic"
        case .openAI: return "Создать ключ на platform.openai.com"
        case .gemini: return "Создать ключ в Google AI Studio"
        }
    }

    /// Где пополнить баланс ключа (для текста ошибки)
    var consoleName: String {
        switch self {
        case .claude: return "консоли Anthropic"
        case .openAI: return "кабинете OpenAI"
        case .gemini: return "Google AI Studio"
        }
    }

    // MARK: - Модель

    var defaultModel: String {
        switch self {
        case .claude: return "claude-opus-5-5"
        case .openAI: return "gpt-6.1-sol"
        case .gemini: return "gemini-3.8-flash"
        }
    }

    private var modelKey: String { "aiModel.\(rawValue)" }

    /// Модель, которую пользователь вписал в настройках вместо стандартной
    var customModel: String? {
        let value = UserDefaults.standard.string(forKey: modelKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// Модель, на которую уходят запросы: своя из настроек или стандартная
    var model: String { customModel ?? defaultModel }

    func setCustomModel(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: modelKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: modelKey)
        }
    }

    /// Подпись в шапке чата
    var statusTitle: String {
        if customModel == nil, self == .claude {
            return "Claude Opus 5.5"
        }
        return "\(displayName) · \(model)"
    }
}
