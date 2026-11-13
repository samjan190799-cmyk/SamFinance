import Foundation

/// Что для облачного ИИ задаёт сборка. Пользователь ничего не вводит: ключ, сервис и модель подставляются в Info.plist
/// при сборке из секретов GitHub (шаг «Inject AI Settings» в testflight.yml). В сборке без секрета ключа нет,
/// и чат отвечает только локальным помощником.
struct AIConfig: Sendable, Equatable {
    /// Ключи Info.plist, в которые сборка кладёт значения
    enum InfoKey {
        static let apiKey = "AIAPIKey"
        static let provider = "AIProviderName"
        static let model = "AIModelName"
    }

    /// Ключ API; nil, если сборка без секрета
    var apiKey: String?
    var provider: AIProvider
    /// Своя модель из настроек сборки; nil — стандартная модель сервиса
    var modelName: String?

    static let standard = AIConfig(info: Bundle.main.infoDictionary ?? [:])

    init(apiKey: String?, provider: AIProvider = .gemini, modelName: String? = nil) {
        self.apiKey = apiKey
        self.provider = provider
        self.modelName = modelName
    }

    /// Настройки из словаря Info.plist. Сервис без названия или с неизвестным названием — Gemini.
    init(info: [String: Any]) {
        self.apiKey = Self.value(info[InfoKey.apiKey])
        self.provider = Self.provider(named: Self.value(info[InfoKey.provider]))
        self.modelName = Self.value(info[InfoKey.model])
    }

    /// Значение без пробелов по краям. Пустое и неподставленное «$(…)» считаются отсутствующими.
    private static func value(_ raw: Any?) -> String? {
        guard let text = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              !text.hasPrefix("$(") else {
            return nil
        }
        return text
    }

    /// Название сервиса в любом регистре: «gemini», «Claude»
    private static func provider(named name: String?) -> AIProvider {
        guard let name else { return .gemini }
        return AIProvider.allCases.first { $0.rawValue.caseInsensitiveCompare(name) == .orderedSame } ?? .gemini
    }
}
