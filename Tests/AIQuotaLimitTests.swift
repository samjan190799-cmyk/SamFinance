import XCTest
@testable import SamFinance

/// Отказ Gemini по квоте: чат говорит, какой лимит исчерпан (минутный или дневной) и когда повторить
final class AIQuotaLimitTests: XCTestCase {
    private func error(_ body: String, provider: AIProvider = .gemini) -> AIAPIError {
        AIAPIError.from(status: 429, data: Data(body.utf8), provider: provider)
    }

    private func body(quotaId: String?, retryDelay: String?, message: String = "You exceeded your current quota") -> String {
        var details: [String] = []
        if let quotaId {
            details.append(#"{"@type":"type.googleapis.com/google.rpc.QuotaFailure","violations":[{"quotaMetric":"generativelanguage.googleapis.com/generate_content_free_tier_requests","quotaId":"\#(quotaId)"}]}"#)
        }
        if let retryDelay {
            details.append(#"{"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"\#(retryDelay)"}"#)
        }
        return #"{"error":{"code":429,"message":"\#(message)","status":"RESOURCE_EXHAUSTED","details":[\#(details.joined(separator: ","))]}}"#
    }

    private func limit(of error: AIAPIError, file: StaticString = #filePath, line: UInt = #line) -> AIQuotaLimit? {
        guard case .quotaLimited(_, let limit, _) = error else {
            XCTFail("ожидался отказ по квоте: \(error)", file: file, line: line)
            return nil
        }
        return limit
    }

    func testDailyQuotaIsRecognisedWhateverTheRetryHintSays() throws {
        let failure = error(body(quotaId: "GenerateRequestsPerDayPerProjectPerModel-FreeTier", retryDelay: "35s"))
        let quota = try XCTUnwrap(limit(of: failure))
        XCTAssertEqual(quota.period, .day)
        let text = try XCTUnwrap(failure.errorDescription)
        XCTAssertEqual(text.components(separatedBy: "\n\n").first, quota.summary)
        XCTAssertTrue(text.contains("You exceeded your current quota"), "настоящий текст сервиса остаётся ниже")
    }

    func testMinuteQuotaTellsHowLongToWait() throws {
        let failure = error(body(quotaId: "GenerateRequestsPerMinutePerProjectPerModel-FreeTier", retryDelay: "35.2s"))
        let quota = try XCTUnwrap(limit(of: failure))
        XCTAssertEqual(quota.period, .minute)
        XCTAssertEqual(quota.retryAfter, 36, "доли секунды округляются вверх")
        XCTAssertTrue(quota.summary.contains("36"), quota.summary)
    }

    func testLongWaitIsShownInMinutes() {
        XCTAssertTrue(AIQuotaLimit(period: .minute, retryAfter: 150).summary.contains("3"))
        XCTAssertFalse(AIQuotaLimit(period: .minute, retryAfter: 150).summary.contains("150"))
        XCTAssertTrue(AIQuotaLimit(period: .minute, retryAfter: 45).summary.contains("45"))
    }

    func testMinuteQuotaWithoutARetryHintAsksToWaitAMinute() throws {
        let failure = error(body(quotaId: "GenerateContentInputTokensPerModelPerMinute-FreeTier", retryDelay: nil))
        let quota = try XCTUnwrap(limit(of: failure))
        XCTAssertEqual(quota.period, .minute)
        XCTAssertNil(quota.retryAfter)
        XCTAssertFalse(quota.summary.isEmpty)
    }

    func testOldStyleAnswerWithTheWaitOnlyInTheText() throws {
        let failure = error(#"{"error":{"code":429,"message":"Quota exceeded for metric: generate_content_free_tier_requests, limit: 20\nPlease retry in 33.4s.","status":"RESOURCE_EXHAUSTED"}}"#)
        let quota = try XCTUnwrap(limit(of: failure))
        XCTAssertEqual(quota.period, .other)
        XCTAssertEqual(quota.retryAfter, 34)
        let text = try XCTUnwrap(failure.errorDescription)
        XCTAssertTrue(text.contains("limit: 20"), "текст сервиса показывается как раньше")
    }

    func testPeriodCanBeReadFromTheMessageToo() throws {
        let quota = try XCTUnwrap(limit(of: error(#"{"error":{"code":429,"message":"Quota exceeded for metric: GenerateRequestsPerDayPerProjectPerModel-FreeTier","status":"RESOURCE_EXHAUSTED"}}"#)))
        XCTAssertEqual(quota.period, .day)
    }

    func testDayWinsWhenBothQuotasAreMentioned() throws {
        let both = #"{"error":{"code":429,"message":"x","details":[{"@type":"type.googleapis.com/google.rpc.QuotaFailure","violations":[{"quotaId":"GenerateRequestsPerMinutePerProjectPerModel-FreeTier"},{"quotaId":"GenerateRequestsPerDayPerProjectPerModel-FreeTier"}]}]}}"#
        XCTAssertEqual(try XCTUnwrap(limit(of: error(both))).period, .day)
    }

    func testAnswerWithoutHintsStaysAPlainRateLimit() {
        for text in ["{}", #"{"error":{"code":429,"message":"slow down"}}"#, "не JSON"] {
            XCTAssertTrue(String(describing: error(text)).hasPrefix("rateLimited"), text)
        }
    }

    func testOtherServicesAreNotAffected() {
        let withHint = #"{"error":{"type":"rate_limit_error","message":"Please retry in 10s"}}"#
        XCTAssertTrue(String(describing: error(withHint, provider: .claude)).hasPrefix("rateLimited"))
        XCTAssertTrue(String(describing: error(withHint, provider: .openAI)).hasPrefix("rateLimited"))
    }

    func testNonsenseWaitIsIgnored() {
        XCTAssertNil(AIQuotaLimit(googleError: ["message": "Please retry in 999999999s"]))
        XCTAssertNil(AIQuotaLimit(googleError: ["message": "Please retry in 0s"]))
        XCTAssertNil(AIQuotaLimit(googleError: nil))
    }
}
