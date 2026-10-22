import Foundation

/// Запросы к OpenAI (ChatGPT) через Chat Completions напрямую по HTTP.
/// Ключ берётся из Keychain пользователя и уходит только в заголовке запроса к api.openai.com.
enum OpenAIAPI {
    private typealias JSON = [String: Any]

    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    /// Тело запроса: ответ строго по JSON-схеме (Structured Outputs), скриншоты уходят как data-URL
    static func requestBody(_ prompt: AIPrompt, schema: [String: Any]) throws -> Data {
        var messages: [JSON] = [["role": "system", "content": prompt.system]]
        for turn in prompt.turns {
            messages.append(["role": turn.isUser ? "user" : "assistant", "content": turn.text])
        }

        // Текущая реплика: хвост переписки, картинки, затем вопрос
        var content: [JSON] = []
        if let leadingText = prompt.leadingText {
            content.append(["type": "text", "text": leadingText])
        }
        for image in prompt.images {
            content.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64," + image.base64EncodedString()]
            ] as JSON)
        }
        content.append(["type": "text", "text": prompt.text])
        messages.append(["role": "user", "content": content] as JSON)

        let jsonSchema: JSON = [
            "name": "finance_reply",
            "strict": true,
            "schema": schema
        ]
        let responseFormat: JSON = [
            "type": "json_schema",
            "json_schema": jsonSchema
        ]
        let body: JSON = [
            "model": AIProvider.openAI.model,
            "messages": messages,
            "max_completion_tokens": 16000,
            "response_format": responseFormat
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    /// Отправляет готовое тело запроса и возвращает текст ответа модели
    static func send(body: Data, apiKey: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let data = try await AIHTTP.send(request, provider: .openAI)
        return try text(from: data)
    }

    private static func text(from data: Data) throws -> String {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let choice = (json["choices"] as? [[String: Any]])?.first else {
            throw AIAPIError.badResponse(.openAI)
        }

        // Обрыв и отказ проверяем до чтения содержимого: оно может не соответствовать схеме
        let finishReason = choice["finish_reason"] as? String
        if finishReason == "length" {
            throw AIAPIError.cutOff
        }
        let message = choice["message"] as? [String: Any]
        if finishReason == "content_filter" || !((message?["refusal"] as? String) ?? "").isEmpty {
            throw AIAPIError.refused(.openAI)
        }

        guard let text = message?["content"] as? String, !text.isEmpty else {
            throw AIAPIError.badResponse(.openAI)
        }
        return text
    }
}
