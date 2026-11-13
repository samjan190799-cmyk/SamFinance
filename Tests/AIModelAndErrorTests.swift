import XCTest
@testable import SamFinance

/// Отказ по лимиту запросов: в чате должен быть настоящий текст сервиса, иначе причину не понять
final class AIRateLimitMessageTests: XCTestCase {
    private func error(_ provider: AIProvider, _ body: String) -> AIAPIError {
        AIAPIError.from(status: 429, data: Data(body.utf8), provider: provider)
    }

    func testGeminiQuotaTextIsShownAsIs() {
        let body = #"{"error":{"code":429,"message":"Quota exceeded for metric: generate_content_free_tier_requests, limit: 20, model: gemini-3.8-flash\nPlease retry in 33s.","status":"RESOURCE_EXHAUSTED"}}"#
        let text = error(.gemini, body).errorDescription ?? ""
        XCTAssertTrue(text.contains("limit: 20"), text)
        XCTAssertTrue(text.contains("Please retry in 33s."), text)
        XCTAssertFalse(text.contains("Настройк"), "пользователь не выбирает модель: отсылки к Настройкам нет")
    }

    func testOtherServicesShowTheirText() {
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
        XCTAssertEqual(error(.gemini, "{}").errorDescription, AIAPIError.rateLimited(.gemini, nil).errorDescription)
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
