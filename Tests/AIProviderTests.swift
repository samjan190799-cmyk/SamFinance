import XCTest
@testable import SamFinance

final class AIProviderTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        resetPreferences()
    }

    override func tearDown() async throws {
        resetPreferences()
        try await super.tearDown()
    }

    private func resetPreferences() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AIProvider.storageKey)
        for provider in AIProvider.allCases {
            provider.setCustomModel("")
            provider.setConsent(false)
        }
    }

    // MARK: - Ключи и модели

    func testKeyFormatPerProvider() {
        XCTAssertTrue(AIProvider.claude.isPlausibleKey("sk-ant-api03-abcdef"))
        XCTAssertFalse(AIProvider.claude.isPlausibleKey("sk-proj-abcdef"))
        XCTAssertTrue(AIProvider.openAI.isPlausibleKey("sk-proj-abcdef"))
        XCTAssertFalse(AIProvider.openAI.isPlausibleKey("sk-ant-api03-abcdef"))
        XCTAssertTrue(AIProvider.gemini.isPlausibleKey("AIzaSyD-1234567890abcdefghij"))
        XCTAssertFalse(AIProvider.gemini.isPlausibleKey("short"))
        XCTAssertFalse(AIProvider.claude.isPlausibleKey("sk-ant-with space"))
    }

    func testDefaultAndCustomModel() {
        XCTAssertEqual(AIProvider.openAI.model, AIProvider.openAI.defaultModel)
        AIProvider.openAI.setCustomModel("  my-model  ")
        XCTAssertEqual(AIProvider.openAI.model, "my-model")
        XCTAssertEqual(AIProvider.openAI.customModel, "my-model")
        AIProvider.openAI.setCustomModel("")
        XCTAssertNil(AIProvider.openAI.customModel)
        XCTAssertEqual(AIProvider.openAI.model, AIProvider.openAI.defaultModel)
    }

    func testSelectedProviderDefaultsToClaude() {
        XCTAssertEqual(AIProvider.selected, .claude)
        UserDefaults.standard.set(AIProvider.gemini.rawValue, forKey: AIProvider.storageKey)
        XCTAssertEqual(AIProvider.selected, .gemini)
        UserDefaults.standard.set("unknown", forKey: AIProvider.storageKey)
        XCTAssertEqual(AIProvider.selected, .claude)
    }

    func testConsentIsStoredPerProvider() {
        XCTAssertFalse(AIProvider.claude.hasConsent)
        AIProvider.claude.setConsent(true)
        XCTAssertTrue(AIProvider.claude.hasConsent)
        XCTAssertFalse(AIProvider.openAI.hasConsent)
        AIProvider.claude.setConsent(false)
        XCTAssertFalse(AIProvider.claude.hasConsent)
    }

    func testConsentMessageNamesTheRecipient() {
        for provider in AIProvider.allCases {
            XCTAssertTrue(provider.consentMessage.contains(provider.company), provider.rawValue)
        }
    }

    // MARK: - Ошибки сервисов

    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    func testClaudeErrorMapping() {
        func map(_ status: Int, _ body: String = "{}") -> String {
            String(describing: AIAPIError.from(status: status, data: data(body), provider: .claude))
        }
        XCTAssertTrue(map(401).hasPrefix("invalidKey"))
        XCTAssertTrue(map(402).hasPrefix("noCredit"))
        XCTAssertTrue(map(429).hasPrefix("rateLimited"))
        XCTAssertTrue(map(529).hasPrefix("overloaded"))
        XCTAssertTrue(map(500, #"{"error":{"type":"api_error","message":"boom"}}"#).hasPrefix("server"))
    }

    func testOpenAIErrorMapping() {
        func map(_ status: Int, _ body: String) -> String {
            String(describing: AIAPIError.from(status: status, data: data(body), provider: .openAI))
        }
        XCTAssertTrue(map(401, #"{"error":{"code":"invalid_api_key","message":"bad"}}"#).hasPrefix("invalidKey"))
        XCTAssertTrue(map(429, #"{"error":{"code":"insufficient_quota","message":"quota"}}"#).hasPrefix("noCredit"))
        XCTAssertTrue(map(429, #"{"error":{"code":"rate_limit_exceeded","message":"slow"}}"#).hasPrefix("rateLimited"))
        XCTAssertTrue(map(503, "{}").hasPrefix("overloaded"))
    }

    func testGeminiErrorMapping() {
        func map(_ status: Int, _ body: String) -> String {
            String(describing: AIAPIError.from(status: status, data: data(body), provider: .gemini))
        }
        XCTAssertTrue(map(400, #"{"error":{"message":"API key not valid. Please pass a valid API key."}}"#).hasPrefix("invalidKey"))
        XCTAssertTrue(map(401, "{}").hasPrefix("invalidKey"))
        XCTAssertTrue(map(429, "{}").hasPrefix("rateLimited"))
        XCTAssertTrue(map(503, "{}").hasPrefix("overloaded"))
        XCTAssertTrue(map(400, #"{"error":{"message":"bad request"}}"#).hasPrefix("server"))
    }

    func testErrorTextsMentionTheService() {
        for provider in AIProvider.allCases {
            let text = AIAPIError.invalidKey(provider).errorDescription ?? ""
            XCTAssertTrue(text.contains(provider.displayName), text)
            XCTAssertFalse((AIAPIError.noCredit(provider).errorDescription ?? "").isEmpty)
        }
    }

    // MARK: - Запросы

    private func samplePrompt(images: [Data] = []) -> AIPrompt {
        AIPrompt(
            system: "SYSTEM",
            turns: [CloudTurn(isUser: true, text: "hi"), CloudTurn(isUser: false, text: "hello")],
            leadingText: "tail",
            images: images,
            text: "question"
        )
    }

    private let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "reply": ["type": "string"],
            "date": ["anyOf": [["type": "string", "format": "date-time"], ["type": "null"]]]
        ] as [String: Any],
        "required": ["reply", "date"],
        "additionalProperties": false
    ]

    private func json(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testClaudeRequestBody() throws {
        let body = try json(ClaudeAPI.requestBody(samplePrompt(images: [Data([1, 2, 3])]), schema: schema))
        XCTAssertEqual(body["model"] as? String, AIProvider.claude.model)
        XCTAssertEqual(body["system"] as? String, "SYSTEM")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 3)
        let content = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        XCTAssertEqual(content.map { $0["type"] as? String }, ["text", "image", "text"])
        let output = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual(output["effort"] as? String, "medium")
        XCTAssertEqual((output["format"] as? [String: Any])?["type"] as? String, "json_schema")
    }

    func testOpenAIRequestBody() throws {
        let body = try json(OpenAIAPI.requestBody(samplePrompt(images: [Data([1, 2, 3])]), schema: schema))
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        XCTAssertEqual(messages.count, 4)
        let content = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        let image = try XCTUnwrap(content.first { $0["type"] as? String == "image_url" })
        let url = (image["image_url"] as? [String: Any])?["url"] as? String
        XCTAssertEqual(url?.hasPrefix("data:image/jpeg;base64,"), true)
        let format = try XCTUnwrap(body["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let jsonSchema = try XCTUnwrap(format["json_schema"] as? [String: Any])
        XCTAssertEqual(jsonSchema["strict"] as? Bool, true)
    }

    func testGeminiRequestBodyUsesGeminiSchema() throws {
        let body = try json(GeminiAPI.requestBody(samplePrompt(), schema: schema))
        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.map { $0["role"] as? String }, ["user", "model", "user"])
        XCTAssertNotNil(body["systemInstruction"])

        let config = try XCTUnwrap(body["generationConfig"] as? [String: Any])
        XCTAssertEqual(config["responseMimeType"] as? String, "application/json")
        let responseSchema = try XCTUnwrap(config["responseSchema"] as? [String: Any])
        XCTAssertEqual(responseSchema["type"] as? String, "OBJECT")
        XCTAssertNil(responseSchema["additionalProperties"])

        let properties = try XCTUnwrap(responseSchema["properties"] as? [String: Any])
        let date = try XCTUnwrap(properties["date"] as? [String: Any])
        XCTAssertEqual(date["type"] as? String, "STRING")
        XCTAssertEqual(date["nullable"] as? Bool, true)
        XCTAssertNil(date["anyOf"])
    }
}
