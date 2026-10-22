import Foundation

/// Запросы к Claude API (Messages) напрямую по HTTP: официального SDK для Swift нет.
/// Ключ берётся из Keychain пользователя и уходит только в заголовке запроса к api.anthropic.com.
enum ClaudeAPI {
    private typealias JSON = [String: Any]

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Тело запроса: ответ строго по JSON-схеме, скриншоты разбираются внимательнее, чем вопросы
    static func requestBody(_ prompt: AIPrompt, schema: [String: Any]) throws -> Data {
        // Текущая реплика: хвост переписки, картинки, затем вопрос
        var content: [JSON] = []
        if let leadingText = prompt.leadingText {
            content.append(["type": "text", "text": leadingText])
        }
        for image in prompt.images {
            content.append([
                "type": "image",
                "source": ["type": "base64", "media_type": "image/jpeg", "data": image.base64EncodedString()]
            ] as JSON)
        }
        content.append(["type": "text", "text": prompt.text])

        var messages: [JSON] = prompt.turns.map { turn -> JSON in
            ["role": turn.isUser ? "user" : "assistant", "content": turn.text]
        }
        messages.append(["role": "user", "content": content] as JSON)

        let outputConfig: JSON = [
            "effort": prompt.images.isEmpty ? "low" : "medium",
            "format": ["type": "json_schema", "schema": schema] as JSON
        ]
        let body: JSON = [
            "model": AIProvider.claude.model,
            "max_tokens": 16000,
            "system": prompt.system,
            "messages": messages,
            "output_config": outputConfig,
            "fallbacks": "default"
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

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

        let data = try await AIHTTP.send(request, provider: .claude)
        return try text(from: data)
    }

    /// Текст ответа из блоков типа text. Блоки читаются по типу, а не по месту:
    /// перед текстом бывают блоки размышлений и отметки о переходе на запасную модель.
    private static func text(from data: Data) throws -> String {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AIAPIError.badResponse(.claude)
        }

        // Отказ проверяем до чтения содержимого: в этом случае ответ может не соответствовать схеме
        let stopReason = json["stop_reason"] as? String
        if stopReason == "refusal" {
            throw AIAPIError.refused(.claude)
        }
        if stopReason == "max_tokens" {
            throw AIAPIError.cutOff
        }

        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.isEmpty else {
            throw AIAPIError.badResponse(.claude)
        }
        return text
    }
}
