import Foundation

/// Проверка подключения к облачному ИИ: бесплатный запрос сведений о выбранной модели, токены не тратятся.
/// За пару секунд показывает, достижим ли сервис из сети пользователя, принял ли он ключ и доступна ли ему модель,
/// чтобы не гадать, почему чат молчит.
enum AIConnectionCheck {
    enum Outcome: Equatable, Sendable {
        /// Всё работает; в тексте название модели
        case works(String)
        /// Что-то не так; в тексте причина для пользователя
        case failed(String)

        var isWorking: Bool {
            if case .works = self { return true }
            return false
        }

        var text: String {
            switch self {
            case .works(let model): return String(localized: "Подключение работает: \(model)")
            case .failed(let reason): return reason
            }
        }
    }

    /// Проверка должна отвечать быстро: если за 20 секунд ответа нет, причина уже понятна
    static let deadline: Duration = .seconds(20)

    /// Безопасные для пути адреса символы: всё остальное в названии модели кодируется, вписать «/» или «?» нельзя
    private static let modelCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._:"))

    /// Запрос сведений о модели; nil, если из названия модели нельзя собрать адрес
    static func request(for provider: AIProvider, apiKey: String) -> URLRequest? {
        var name = provider.model
        if provider == .gemini, name.hasPrefix("models/") {
            name.removeFirst("models/".count)
        }
        guard !name.isEmpty, let model = name.addingPercentEncoding(withAllowedCharacters: modelCharacters) else { return nil }

        let address: String
        let headers: [String: String]
        switch provider {
        case .claude:
            address = "https://api.anthropic.com/v1/models/\(model)"
            headers = ["x-api-key": apiKey, "anthropic-version": "2023-06-01"]
        case .openAI:
            address = "https://api.openai.com/v1/models/\(model)"
            headers = ["Authorization": "Bearer \(apiKey)"]
        case .gemini:
            address = "https://generativelanguage.googleapis.com/v1beta/models/\(model)"
            headers = ["x-goog-api-key": apiKey]
        }
        guard let url = URL(string: address) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    static func run(
        provider: AIProvider,
        apiKey: String,
        deadline: Duration = AIConnectionCheck.deadline,
        transport: @escaping AIHTTP.Transport = AIHTTP.urlSession
    ) async -> Outcome {
        guard let request = request(for: provider, apiKey: apiKey) else {
            return .failed(String(localized: "название модели содержит недопустимые символы"))
        }
        do {
            _ = try await AIHTTP.send(request, provider: provider, deadline: deadline, transport: transport)
            return .works(provider.statusTitle)
        } catch AIAPIError.timedOut {
            return .failed(String(localized: "\(provider.company) не ответил за 20 секунд. Похоже, сервис недоступен из вашей сети: проверьте интернет и VPN."))
        } catch let error as AIAPIError {
            return .failed(error.errorDescription ?? String(localized: "Не получилось проверить подключение."))
        } catch {
            return .failed(String(localized: "Не получилось проверить подключение."))
        }
    }
}
