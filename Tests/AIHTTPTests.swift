import XCTest
@testable import SamFinance

/// Считает вызовы подменённой сети
private actor Calls {
    private var count = 0

    @discardableResult
    func record() -> Int {
        count += 1
        return count
    }

    var total: Int { count }
}

private let stubAddress = URL(string: "https://example.test/v1")!

/// Ответ подменённой сети с нужным кодом и телом
private func stubReply(_ status: Int, _ body: String = "{}") -> (Data, URLResponse) {
    let response = HTTPURLResponse(url: stubAddress, statusCode: status, httpVersion: nil, headerFields: nil)!
    return (Data(body.utf8), response)
}

/// Общий запрос к облачному ИИ: срок ожидания и повторы. Настоящая сеть не используется.
final class AIHTTPTests: XCTestCase {
    private var request: URLRequest { URLRequest(url: stubAddress) }

    // MARK: - Срок ожидания

    func testSilentServerEndsWithTimeoutInsteadOfWaitingForever() async {
        let started = ContinuousClock.now
        do {
            _ = try await AIHTTP.send(request, provider: .claude, deadline: .milliseconds(300)) { _ in
                try await Task.sleep(for: .seconds(60))
                return stubReply(200)
            }
            XCTFail("ответа не было, но запрос не завершился ошибкой")
        } catch AIAPIError.timedOut(let provider) {
            XCTAssertEqual(provider, .claude)
        } catch {
            XCTFail("ожидался timedOut, пришло \(error)")
        }
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(10))
    }

    func testURLSessionTimeoutIsReportedAndNotRetried() async {
        let calls = Calls()
        do {
            _ = try await AIHTTP.send(request, provider: .openAI) { _ in
                await calls.record()
                throw URLError(.timedOut)
            }
            XCTFail("тайм-аут сети не стал ошибкой")
        } catch AIAPIError.timedOut(let provider) {
            XCTAssertEqual(provider, .openAI)
        } catch {
            XCTFail("ожидался timedOut, пришло \(error)")
        }
        let total = await calls.total
        XCTAssertEqual(total, 1, "после тайм-аута запрос не повторяется")
    }

    func testRequestIsLimitedByTheDeadline() async throws {
        let seen = Calls()
        _ = try await AIHTTP.send(request, provider: .gemini, deadline: .seconds(40)) { sent in
            await seen.record()
            XCTAssertEqual(sent.timeoutInterval, 41, accuracy: 0.001)
            return stubReply(200, "{}")
        }
        let total = await seen.total
        XCTAssertEqual(total, 1)
    }

    // MARK: - Повторы и ошибки

    func testServerFailureIsRetriedOnce() async throws {
        let calls = Calls()
        let data = try await AIHTTP.send(request, provider: .claude) { _ in
            let attempt = await calls.record()
            return attempt == 1 ? stubReply(503) : stubReply(200, "ok")
        }
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "ok")
        let total = await calls.total
        XCTAssertEqual(total, 2)
    }

    func testInvalidKeyIsReportedWithoutRetry() async {
        let calls = Calls()
        do {
            _ = try await AIHTTP.send(request, provider: .claude) { _ in
                await calls.record()
                return stubReply(401, #"{"error":{"type":"authentication_error","message":"invalid x-api-key"}}"#)
            }
            XCTFail("неверный ключ не стал ошибкой")
        } catch AIAPIError.invalidKey(let provider) {
            XCTAssertEqual(provider, .claude)
        } catch {
            XCTFail("ожидался invalidKey, пришло \(error)")
        }
        let total = await calls.total
        XCTAssertEqual(total, 1)
    }

    func testCancelledRequestStopsWithoutAnError() async {
        let request = self.request
        let task = Task {
            try await AIHTTP.send(request, provider: .claude) { _ in
                try await Task.sleep(for: .seconds(60))
                return stubReply(200)
            }
        }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("отменённый запрос завершился ответом")
        } catch is CancellationError {
            // так чат понимает, что отмену нажал пользователь, и ничего не отвечает
        } catch {
            XCTFail("ожидалась отмена, пришло \(error)")
        }
    }
}
