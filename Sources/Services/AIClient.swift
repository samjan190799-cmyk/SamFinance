import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Ошибки облачного ИИ с понятным текстом для чата
enum AIAPIError: LocalizedError {
    case invalidKey(AIProvider)
    case noCredit(AIProvider)
    case rateLimited(AIProvider)
    case overloaded(AIProvider)
    case refused(AIProvider)
    case cutOff
    case badResponse(AIProvider)
    case network(AIProvider)
    /// Ответ не пришёл за отведённое время: сервис недоступен, перегружен или связь «висит»
    case timedOut(AIProvider)
    case server(AIProvider, String)

    var errorDescription: String? {
        switch self {
        case .invalidKey(let provider):
            return String(localized: "Ключ \(provider.displayName) не подошёл. Проверьте его в Настройках → ИИ-помощник.")
        case .noCredit(let provider):
            switch provider {
            case .claude: return String(localized: "На счёте ключа закончились средства. Пополните баланс в консоли Anthropic.")
            case .openAI: return String(localized: "На счёте ключа закончились средства. Пополните баланс в кабинете OpenAI.")
            case .gemini: return String(localized: "На счёте ключа закончились средства. Пополните баланс в Google AI Studio.")
            }
        case .rateLimited(let provider):
            return String(localized: "Слишком много запросов подряд или исчерпан лимит ключа \(provider.displayName). Подождите минуту и повторите.")
        case .overloaded(let provider):
            return String(localized: "Сервис \(provider.displayName) сейчас перегружен. Повторите чуть позже.")
        case .refused(let provider):
            return String(localized: "\(provider.displayName) не стал отвечать на этот запрос. Попробуйте сформулировать иначе.")
        case .cutOff:
            return String(localized: "Ответ получился слишком длинным и оборвался. Пришлите меньше скриншотов за раз.")
        case .badResponse(let provider):
            return String(localized: "Не получилось разобрать ответ \(provider.displayName). Повторите запрос.")
        case .network(let provider):
            return String(localized: "Нет связи с сервером \(provider.displayName). Проверьте интернет.")
        case .timedOut(let provider):
            return String(localized: "\(provider.displayName) не ответил вовремя. Проверьте интернет и VPN и повторите. Если так каждый раз, нажмите «Проверить подключение» в Настройках → ИИ-помощник.")
        case .server(let provider, let message):
            return String(localized: "\(provider.displayName) вернул ошибку: \(message)")
        }
    }

    /// Ошибка по коду и телу ответа сервиса: у каждого свой формат и свои коды
    static func from(status: Int, data: Data, provider: AIProvider) -> AIAPIError {
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let details = body?["error"] as? [String: Any]
        let message = details?["message"] as? String ?? String(localized: "код \(status)")
        let type = details?["type"] as? String ?? ""
        let code = details?["code"] as? String ?? ""

        switch provider {
        case .claude:
            if status == 401 || type == "authentication_error" { return .invalidKey(provider) }
            if status == 402 || type == "billing_error" { return .noCredit(provider) }
            if status == 429 || type == "rate_limit_error" { return .rateLimited(provider) }
            if status == 529 || type == "overloaded_error" { return .overloaded(provider) }
        case .openAI:
            if status == 401 || code == "invalid_api_key" { return .invalidKey(provider) }
            if status == 402 || code == "insufficient_quota" { return .noCredit(provider) }
            if status == 429 { return .rateLimited(provider) }
            if status == 503 { return .overloaded(provider) }
        case .gemini:
            if status == 401 || (status == 400 && message.localizedCaseInsensitiveContains("api key")) {
                return .invalidKey(provider)
            }
            if status == 402 { return .noCredit(provider) }
            if status == 429 { return .rateLimited(provider) }
            if status == 503 { return .overloaded(provider) }
        }
        return .server(provider, message)
    }
}

/// Запрос к модели в виде, общем для всех сервисов; тело запроса из него собирает клиент сервиса
struct AIPrompt: Sendable {
    let system: String
    /// Прежняя переписка: реплики чередуются, начинаются с пользователя и кончаются ответом помощника
    let turns: [CloudTurn]
    /// Хвост переписки от пользователя, который идёт в одной реплике с текущим вопросом
    let leadingText: String?
    /// Скриншоты, уже уменьшенные до JPEG
    let images: [Data]
    /// Текущий вопрос
    let text: String
}

enum AIHTTP {
    /// Как запрос уходит в сеть; в тестах подменяется, чтобы не обращаться к настоящим серверам
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let urlSession: Transport = { request in
        try await URLSession.shared.data(for: request)
    }

    /// Сколько ждать ответа целиком, с повтором. Раньше ждали до 6 минут (две попытки по 180 с), и чат казался зависшим.
    static let defaultDeadline: Duration = .seconds(120)

    /// Отправляет запрос и возвращает тело ответа 200. Если ответа нет дольше `deadline`, бросает `timedOut`.
    static func send(
        _ request: URLRequest,
        provider: AIProvider,
        deadline: Duration = defaultDeadline,
        transport: @escaping Transport = urlSession
    ) async throws -> Data {
        var request = request
        // Простой соединения без данных считается обрывом на том же сроке, что и весь запрос
        request.timeoutInterval = TimeInterval(deadline.components.seconds) + 1
        let limited = request

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await perform(limited, provider: provider, transport: transport)
            }
            group.addTask {
                try await Task.sleep(for: deadline)
                throw AIAPIError.timedOut(provider)
            }
            defer { group.cancelAll() }
            guard let data = try await group.next() else {
                throw AIAPIError.badResponse(provider)
            }
            return data
        }
    }

    /// Перегрузку, сбой сервера или обрыв связи пробует переждать один раз. Тайм-аут не повторяется: ждать ещё дольше нет смысла.
    private static func perform(_ request: URLRequest, provider: AIProvider, transport: Transport) async throws -> Data {
        for attempt in 0..<2 {
            let isLastAttempt = attempt == 1
            let result: (Data, URLResponse)
            do {
                result = try await transport(request)
            } catch {
                try Task.checkCancellation()
                if (error as? URLError)?.code == .timedOut { throw AIAPIError.timedOut(provider) }
                if isLastAttempt { throw AIAPIError.network(provider) }
                try await Task.sleep(for: .seconds(2))
                continue
            }

            let (data, response) = result
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                return data
            }
            if !isLastAttempt && (500...599).contains(status) {
                try await Task.sleep(for: .seconds(2))
                continue
            }
            throw AIAPIError.from(status: status, data: data, provider: provider)
        }
        throw AIAPIError.overloaded(provider)
    }
}

enum AIImages {
    /// Уменьшает скриншот до 1568 точек по длинной стороне и сжимает в JPEG: запрос меньше и дешевле,
    /// а текст на экране телефона остаётся читаемым
    static func prepared(_ data: Data) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            resized(data)
        }.value
    }

    private static func resized(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1568
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let quality: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.8]
        CGImageDestinationAddImage(destination, image, quality as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
