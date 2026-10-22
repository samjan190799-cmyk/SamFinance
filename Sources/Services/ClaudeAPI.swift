import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Ошибки облачного ИИ с понятным текстом для чата
enum ClaudeAPIError: LocalizedError {
    case invalidKey
    case noCredit
    case rateLimited
    case overloaded
    case refused
    case cutOff
    case badResponse
    case network
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "Ключ Claude не подошёл. Проверьте его в Настройках → ИИ-помощник."
        case .noCredit:
            return "На счёте ключа закончились средства. Пополните баланс в консоли Anthropic."
        case .rateLimited:
            return "Слишком много запросов подряд. Подождите минуту и повторите."
        case .overloaded:
            return "Сервис Claude сейчас перегружен. Повторите чуть позже."
        case .refused:
            return "Claude не стал отвечать на этот запрос. Попробуйте сформулировать иначе."
        case .cutOff:
            return "Ответ получился слишком длинным и оборвался. Пришлите меньше скриншотов за раз."
        case .badResponse:
            return "Не получилось разобрать ответ Claude. Повторите запрос."
        case .network:
            return "Нет связи с сервером Claude. Проверьте интернет."
        case .server(let message):
            return "Claude вернул ошибку: \(message)"
        }
    }
}

/// Запросы к Claude API (Messages) напрямую по HTTP: официального SDK для Swift нет.
/// Ключ берётся из Keychain пользователя и уходит только в заголовке запроса к api.anthropic.com.
enum ClaudeAPI {
    static let model = "claude-opus-5-5"

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Отправляет готовое тело запроса и возвращает текст ответа модели
    static func send(body: Data, apiKey: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // Нужен для fallbacks: "default" — отклонённый классификатором запрос сервер сам повторит на рекомендованной модели
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = body

        // Перегрузку, сбой сервера или связи пробуем переждать один раз
        for attempt in 0..<2 {
            let isLastAttempt = attempt == 1
            let result: (Data, URLResponse)
            do {
                result = try await URLSession.shared.data(for: request)
            } catch {
                try Task.checkCancellation()
                if isLastAttempt { throw ClaudeAPIError.network }
                try await Task.sleep(for: .seconds(2))
                continue
            }

            let (data, response) = result
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                return try text(from: data)
            }
            if !isLastAttempt && (500...599).contains(status) {
                try await Task.sleep(for: .seconds(2))
                continue
            }
            throw apiError(status: status, data: data)
        }
        throw ClaudeAPIError.overloaded
    }

    /// Текст ответа из блоков типа text. Блоки читаются по типу, а не по месту:
    /// перед текстом бывают блоки размышлений и отметки о переходе на запасную модель.
    private static func text(from data: Data) throws -> String {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ClaudeAPIError.badResponse
        }

        // Отказ проверяем до чтения содержимого: в этом случае ответ может не соответствовать схеме
        let stopReason = json["stop_reason"] as? String
        if stopReason == "refusal" {
            throw ClaudeAPIError.refused
        }
        if stopReason == "max_tokens" {
            throw ClaudeAPIError.cutOff
        }

        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.isEmpty else {
            throw ClaudeAPIError.badResponse
        }
        return text
    }

    private static func apiError(status: Int, data: Data) -> ClaudeAPIError {
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let details = body?["error"] as? [String: Any]
        let type = details?["type"] as? String ?? ""
        let message = details?["message"] as? String ?? "код \(status)"

        if status == 401 || type == "authentication_error" { return .invalidKey }
        if status == 402 || type == "billing_error" { return .noCredit }
        if status == 429 || type == "rate_limit_error" { return .rateLimited }
        if status == 529 || type == "overloaded_error" { return .overloaded }
        return .server(message)
    }

    // MARK: - Картинки

    /// Уменьшает скриншот до 1568 точек по длинной стороне и сжимает в JPEG: запрос меньше и дешевле,
    /// а текст на экране телефона остаётся читаемым
    static func preparedImage(_ data: Data) async -> Data? {
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
