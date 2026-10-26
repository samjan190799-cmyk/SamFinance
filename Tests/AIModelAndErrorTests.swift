import XCTest
@testable import SamFinance

/// Название модели из настроек: клавиатура телефона ставит пробелы вокруг тире и ломает его
final class AIModelNameTests: XCTestCase {
    func testSpacesAndLongDashesAreRemoved() {
        XCTAssertEqual(AIProvider.normalizedModel("gemini - 3.6 - flash"), "gemini-3.6-flash")
        XCTAssertEqual(AIProvider.normalizedModel("gemini–3.6—flash"), "gemini-3.6-flash")
        XCTAssertEqual(AIProvider.normalizedModel("  gpt-6.1-sol\n"), "gpt-6.1-sol")
        XCTAssertEqual(AIProvider.normalizedModel("claude-opus-5-5"), "claude-opus-5-5")
        XCTAssertEqual(AIProvider.normalizedModel("   "), "")
    }

    func testModelSavedWithSpacesIsCleanedOnRead() {
        let saved = AIProvider.gemini.customModel
        defer { AIProvider.gemini.setCustomModel(saved ?? "") }

        AIProvider.gemini.setCustomModel("gemini - 3.6 - flash")
        XCTAssertEqual(AIProvider.gemini.customModel, "gemini-3.6-flash")
        XCTAssertEqual(AIProvider.gemini.model, "gemini-3.6-flash")

        // Значение с пробелами, которое записала прежняя версия приложения
        UserDefaults.standard.set("gemini - 3.6 - flash", forKey: "aiModel.gemini")
        XCTAssertEqual(AIProvider.gemini.customModel, "gemini-3.6-flash")

        AIProvider.gemini.setCustomModel("  ")
        XCTAssertNil(AIProvider.gemini.customModel)
        XCTAssertEqual(AIProvider.gemini.model, AIProvider.gemini.defaultModel)
    }
}

/// Отказ по лимиту запросов: в чате должен быть настоящий текст сервиса, иначе причину не понять
final class AIRateLimitMessageTests: XCTestCase {
    private func error(_ provider: AIProvider, _ body: String) -> AIAPIError {
        AIAPIError.from(status: 429, data: Data(body.utf8), provider: provider)
    }

    func testGeminiQuotaTextIsShownWithAHint() {
        let body = #"{"error":{"code":429,"message":"Quota exceeded for metric: generate_content_free_tier_requests, limit: 20, model: gemini-3.8-flash\nPlease retry in 33s.","status":"RESOURCE_EXHAUSTED"}}"#
        let text = error(.gemini, body).errorDescription ?? ""
        XCTAssertTrue(text.contains("limit: 20"), text)
        XCTAssertTrue(text.contains("Please retry in 33s."), text)
        XCTAssertTrue(text.contains("gemini-3.5-flash-lite"), text)
    }

    func testOtherServicesShowTheirTextWithoutTheGeminiHint() {
        let body = #"{"error":{"type":"rate_limit_error","message":"Number of request tokens has exceeded your per-minute rate limit"}}"#
        let text = error(.claude, body).errorDescription ?? ""
        XCTAssertTrue(text.contains("per-minute rate limit"), text)
        XCTAssertFalse(text.contains("gemini-3.5-flash-lite"), text)
    }

    func testMissingServiceTextKeepsTheShortMessage() {
        for provider in AIProvider.allCases {
            let text = error(provider, "{}").errorDescription ?? ""
            XCTAssertFalse(text.contains("\n\n"), "\(provider.rawValue): \(text)")
            XCTAssertTrue(text.contains(provider.displayName), text)
        }
        XCTAssertEqual(error(.openAI, "{}").errorDescription, AIAPIError.rateLimited(.openAI, nil).errorDescription)
    }

    func testRateLimitStillMapsToTheSameCase() {
        XCTAssertTrue(String(describing: error(.claude, "{}")).hasPrefix("rateLimited"))
        XCTAssertTrue(String(describing: error(.gemini, "{}")).hasPrefix("rateLimited"))
    }

    func testLongServiceTextIsShortened() {
        let shortened = AIAPIError.shortened(String(repeating: "x", count: 1_000))
        XCTAssertEqual(shortened?.count, 301)
        XCTAssertTrue(shortened?.hasSuffix("…") ?? false)
        XCTAssertEqual(AIAPIError.shortened("short"), "short")
        XCTAssertNil(AIAPIError.shortened(""))
        XCTAssertNil(AIAPIError.shortened(nil))
    }
}
