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

/// Общий запрос к облачному ИИ: срок ожидания, повторы и проверка подключения. Настоящая сеть не используется.
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

/// «Проверить подключение»: адреса запросов и понятные результаты
final class AIConnectionCheckTests: XCTestCase {
    func testEachServiceIsAskedAboutItsOwnModelWithItsOwnKeyHeader() throws {
        let claude = try XCTUnwrap(AIConnectionCheck.request(for: .claude, apiKey: "key-1"))
        XCTAssertEqual(claude.url?.absoluteString, "https://api.anthropic.com/v1/models/\(AIProvider.claude.model)")
        XCTAssertEqual(claude.value(forHTTPHeaderField: "x-api-key"), "key-1")
        XCTAssertEqual(claude.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(claude.httpMethod, "GET")

        let openAI = try XCTUnwrap(AIConnectionCheck.request(for: .openAI, apiKey: "key-2"))
        XCTAssertEqual(openAI.url?.absoluteString, "https://api.openai.com/v1/models/\(AIProvider.openAI.model)")
        XCTAssertEqual(openAI.value(forHTTPHeaderField: "Authorization"), "Bearer key-2")

        let gemini = try XCTUnwrap(AIConnectionCheck.request(for: .gemini, apiKey: "key-3"))
        XCTAssertEqual(gemini.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models/\(AIProvider.gemini.model)")
        XCTAssertEqual(gemini.value(forHTTPHeaderField: "x-goog-api-key"), "key-3")
    }

    func testModelNameCannotChangeTheAddress() throws {
        let saved = AIProvider.openAI.customModel
        defer { AIProvider.openAI.setCustomModel(saved ?? "") }

        AIProvider.openAI.setCustomModel("gpt/../x?y=1")
        let request = try XCTUnwrap(AIConnectionCheck.request(for: .openAI, apiKey: "k"))
        XCTAssertNil(request.url?.query, "из названия модели нельзя вписать параметры запроса")
        XCTAssertEqual(request.url?.host, "api.openai.com")
        XCTAssertTrue(request.url?.absoluteString.contains("gpt%2F..%2Fx%3Fy%3D1") ?? false, "\(String(describing: request.url))")
    }

    func testGeminiModelPrefixIsNotDuplicated() throws {
        let saved = AIProvider.gemini.customModel
        defer { AIProvider.gemini.setCustomModel(saved ?? "") }

        AIProvider.gemini.setCustomModel("models/gemini-test")
        let request = try XCTUnwrap(AIConnectionCheck.request(for: .gemini, apiKey: "k"))
        XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models/gemini-test")
    }

    func testWorkingKeyReportsTheModel() async {
        let outcome = await AIConnectionCheck.run(provider: .claude, apiKey: "k") { _ in stubReply(200) }
        XCTAssertTrue(outcome.isWorking)
        XCTAssertEqual(outcome, .works(AIProvider.claude.statusTitle))
        XCTAssertTrue(outcome.text.contains(AIProvider.claude.statusTitle))
    }

    func testRejectedKeyExplainsTheKey() async {
        let outcome = await AIConnectionCheck.run(provider: .claude, apiKey: "bad") { _ in
            stubReply(401, #"{"error":{"type":"authentication_error","message":"invalid x-api-key"}}"#)
        }
        XCTAssertFalse(outcome.isWorking)
        XCTAssertEqual(outcome, .failed(AIAPIError.invalidKey(.claude).errorDescription ?? ""))
    }

    func testUnknownModelShowsTheServiceMessage() async {
        let outcome = await AIConnectionCheck.run(provider: .openAI, apiKey: "k") { _ in
            stubReply(404, #"{"error":{"message":"The model does not exist","code":"model_not_found"}}"#)
        }
        XCTAssertFalse(outcome.isWorking)
        XCTAssertTrue(outcome.text.contains("The model does not exist"), outcome.text)
    }

    func testUnreachableServiceSaysTheNetworkIsTheProblem() async {
        let outcome = await AIConnectionCheck.run(provider: .claude, apiKey: "k", deadline: .milliseconds(200)) { _ in
            try await Task.sleep(for: .seconds(60))
            return stubReply(200)
        }
        XCTAssertFalse(outcome.isWorking)
        XCTAssertTrue(outcome.text.contains(AIProvider.claude.company), outcome.text)
    }
}
