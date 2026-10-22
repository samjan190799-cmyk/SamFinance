import Foundation

/// Запросы к Google Gemini (generateContent) напрямую по HTTP.
/// Ключ берётся из Keychain пользователя и уходит только в заголовке запроса к generativelanguage.googleapis.com.
enum GeminiAPI {
    private typealias JSON = [String: Any]

    /// Тело запроса: ответ в формате JSON по схеме, скриншоты уходят встроенными данными
    static func requestBody(_ prompt: AIPrompt, schema: [String: Any]) throws -> Data {
        var contents: [JSON] = []
        for turn in prompt.turns {
            let turnParts: [JSON] = [["text": turn.text]]
            contents.append(["role": turn.isUser ? "user" : "model", "parts": turnParts] as JSON)
        }

        // Текущая реплика: хвост переписки, картинки, затем вопрос
        var parts: [JSON] = []
        if let leadingText = prompt.leadingText {
            parts.append(["text": leadingText])
        }
        for image in prompt.images {
            let blob: JSON = ["mimeType": "image/jpeg", "data": image.base64EncodedString()]
            parts.append(["inlineData": blob])
        }
        parts.append(["text": prompt.text])
        contents.append(["role": "user", "parts": parts] as JSON)

        let systemParts: [JSON] = [["text": prompt.system]]
        let generationConfig: JSON = [
            "responseMimeType": "application/json",
            "responseSchema": geminiSchema(schema),
            "maxOutputTokens": 16000
        ]
        let body: JSON = [
            "systemInstruction": ["parts": systemParts] as JSON,
            "contents": contents,
            "generationConfig": generationConfig
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    /// Общая схема ответа в виде, который понимает Gemini: его responseSchema — подмножество OpenAPI.
    /// Типы пишутся заглавными, вариант «или null» заменяется на nullable, additionalProperties не поддерживается.
    static func geminiSchema(_ schema: [String: Any]) -> [String: Any] {
        if let options = schema["anyOf"] as? [JSON] {
            let nonNull = options.filter { ($0["type"] as? String) != "null" }
            if nonNull.count == 1, options.count == 2 {
                var converted = geminiSchema(nonNull[0])
                converted["nullable"] = true
                return converted
            }
        }

        var result: JSON = [:]
        for (key, value) in schema {
            switch key {
            case "additionalProperties":
                continue
            case "type":
                if let name = value as? String {
                    result[key] = name.uppercased()
                }
            case "anyOf":
                if let options = value as? [JSON] {
                    result[key] = options.map { geminiSchema($0) }
                }
            case "properties":
                if let properties = value as? [String: JSON] {
                    result[key] = properties.mapValues { geminiSchema($0) }
                }
            case "items":
                if let item = value as? JSON {
                    result[key] = geminiSchema(item)
                }
            default:
                result[key] = value
            }
        }
        return result
    }

    /// Отправляет готовое тело запроса и возвращает текст ответа модели
    static func send(body: Data, apiKey: String) async throws -> String {
        guard let url = endpoint() else {
            throw AIAPIError.server(.gemini, String(localized: "название модели содержит недопустимые символы"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = body

        let data = try await AIHTTP.send(request, provider: .gemini)
        return try text(from: data)
    }

    /// Адрес зависит от модели. Из названия берутся только буквы, цифры и «-._»: оно вписывается пользователем.
    private static func endpoint() -> URL? {
        var name = AIProvider.gemini.model
        if name.hasPrefix("models/") {
            name.removeFirst("models/".count)
        }
        let allowed = name.filter { $0.isASCII && ($0.isLetter || $0.isNumber || "-._".contains($0)) }
        guard !allowed.isEmpty, allowed == name else { return nil }
        return URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(name):generateContent")
    }

    private static func text(from data: Data) throws -> String {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AIAPIError.badResponse(.gemini)
        }

        // Запрос заблокирован целиком: кандидатов нет, причина в promptFeedback
        guard let candidate = (json["candidates"] as? [[String: Any]])?.first else {
            let feedback = json["promptFeedback"] as? [String: Any]
            if feedback?["blockReason"] != nil {
                throw AIAPIError.refused(.gemini)
            }
            throw AIAPIError.badResponse(.gemini)
        }

        // Оборванный JSON не разобрать, поэтому обрыв проверяем до чтения содержимого
        let finishReason = candidate["finishReason"] as? String
        if finishReason == "MAX_TOKENS" {
            throw AIAPIError.cutOff
        }

        let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        let text = parts
            .filter { $0["thought"] as? Bool != true }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.isEmpty else {
            let blocked: Set<String> = ["SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII", "IMAGE_SAFETY", "IMAGE_PROHIBITED_CONTENT"]
            if let finishReason, blocked.contains(finishReason) {
                throw AIAPIError.refused(.gemini)
            }
            throw AIAPIError.badResponse(.gemini)
        }
        return text
    }
}
