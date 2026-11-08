import Foundation

/// Облачный ИИ, на котором работает чат. Какой именно сервис, ключ и модель, задаёт сборка (AIConfig):
/// пользователь ничего не выбирает и не вводит. Здесь остаются названия сервисов, согласие на отправку данных и модели.
enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case claude
    case openAI
    case gemini

    var id: String { rawValue }

    /// Сервис, на который настроена эта сборка
    static var selected: AIProvider {
        AIConfig.standard.provider
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

    // MARK: - Согласие на отправку данных

    /// Версия 2: в ИИ теперь уходят ещё копилки и напоминания, поэтому прежнее согласие не действует и запрос повторяется один раз
    private var consentKey: String { "aiConsent.v2.\(rawValue)" }

    /// Пользователь разрешил отправлять этому сервису вопросы, скриншоты и сводку учёта.
    /// Спрашивается один раз; отзывается переключателем в Настройках.
    var hasConsent: Bool {
        UserDefaults.standard.bool(forKey: consentKey)
    }

    func setConsent(_ granted: Bool) {
        UserDefaults.standard.set(granted, forKey: consentKey)
    }

    /// Что именно уйдёт и кому: показывается перед первой отправкой
    var consentMessage: String {
        String(localized: "Чтобы ответить, приложение отправит в \(company) (\(displayName)) ваш вопрос и скриншоты, а также сводку ваших операций, карт (только последние 4 цифры), долгов, копилок и напоминаний. Банковские СМС распознаются на телефоне и не отправляются. Если вы просите что-то изменить, ИИ только предлагает изменения: они применяются после вашего нажатия «Применить». Данные обрабатывает \(company) по своим правилам. Разрешение можно отозвать в Настройках → ИИ-помощник.")
    }

    // MARK: - Модель

    /// Модель, на которую уходят запросы, если сборка не задала свою
    var defaultModel: String {
        switch self {
        case .claude: return "claude-opus-5-5"
        case .openAI: return "gpt-6.1-sol"
        case .gemini: return "gemini-3.5-flash-lite"
        }
    }

    /// Модель, на которую уходят запросы: своя из настроек сборки (для сервиса этой сборки) или стандартная
    var model: String {
        model(in: .standard)
    }

    /// То же для заданной конфигурации: своя модель относится только к сервису, для которого её задали
    func model(in config: AIConfig) -> String {
        (config.provider == self ? config.modelName : nil) ?? defaultModel
    }
}
