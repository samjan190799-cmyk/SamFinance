import XCTest
@testable import SamFinance

/// Движок запросов ИИ к данным: отбор, итоги, разбивка, список и текст для модели
final class DataQueryEngineTests: XCTestCase {

    // Часовой пояс Гринвича: названия месяцев и дней не зависят от машины, на которой идут тесты
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        // Неделя с воскресенья: название недели в тесте не зависит от региона машины
        calendar.firstWeekday = 1
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private func category(_ name: String) throws -> AppCategory {
        try XCTUnwrap(AppCategory.defaultCategories.first { $0.name == name })
    }

    private let cardA = Card(last4: "0640", holderName: "TEST", balance: 0, colorHex: "#2A2B30", gradientColors: ["#2A2B30"])
    private let cardB = Card(last4: "1111", holderName: "TEST", balance: 0, colorHex: "#2A2B30", gradientColors: ["#2A2B30"])

    /// Сентябрь: 12 000 + 3 000 + 8 000, октябрь: 5 000 + 1 500, доход 400 000
    private func fixture() throws -> [Transaction] {
        let groceries = try category("Продукты")
        let transport = try category("Транспорт")
        let restaurants = try category("Рестораны")
        let salary = try category("Зарплата")
        return [
            Transaction(title: "Ararat Market", amount: 12_000, type: .expense, category: groceries, date: try date(2026, 9, 3), brandName: "Ararat Market", cardId: cardA.id),
            Transaction(title: "Yandex Go", amount: 3_000, type: .expense, category: transport, date: try date(2026, 9, 10), cardId: cardA.id),
            Transaction(title: "Ararat Market", amount: 8_000, type: .expense, category: groceries, date: try date(2026, 9, 20), brandName: "Ararat Market", cardId: cardB.id),
            Transaction(title: "Ararat Market", amount: 5_000, type: .expense, category: groceries, date: try date(2026, 10, 2), brandName: "Ararat Market", cardId: cardA.id),
            Transaction(title: "Cafe", amount: 1_500, type: .expense, category: restaurants, date: try date(2026, 10, 15)),
            Transaction(title: "Salary", amount: 400_000, type: .income, category: salary, date: try date(2026, 9, 5))
        ]
    }

    private func run(_ query: DataQuery, _ transactions: [Transaction]) -> DataQueryResult {
        DataQueryEngine.run(query, transactions: transactions, cards: [cardA, cardB], calendar: calendar)
    }

    // MARK: - Итоги и отбор

    func testSumCountsExpensesOnlyByDefault() throws {
        let result = run(DataQuery(kind: .sum), try fixture())
        XCTAssertEqual(result.total, 29_500, accuracy: 0.001)
        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(result.largest?.amount, 12_000)
        XCTAssertEqual(result.largest?.title, "Ararat Market")
    }

    func testIncomeQueryReturnsOnlyIncome() throws {
        let result = run(DataQuery(kind: .sum, type: .income), try fixture())
        XCTAssertEqual(result.total, 400_000, accuracy: 0.001)
        XCTAssertEqual(result.count, 1)
    }

    func testPeriodBoundsAreInclusive() throws {
        // Граница ровно в момент первой операции: она входит в период
        let september = DataQuery(kind: .sum, from: try date(2026, 9, 3), to: try date(2026, 9, 30, hour: 23))
        let result = run(september, try fixture())
        XCTAssertEqual(result.total, 23_000, accuracy: 0.001)
        XCTAssertEqual(result.count, 3)
    }

    func testSwappedBoundsGiveTheSameAnswer() throws {
        let swapped = DataQuery(kind: .sum, from: try date(2026, 9, 30, hour: 23), to: try date(2026, 9, 1))
        let result = run(swapped, try fixture())
        XCTAssertEqual(result.total, 23_000, accuracy: 0.001)
        XCTAssertEqual(result.query.from, try date(2026, 9, 1))
    }

    func testCategoryFilterIgnoresCase() throws {
        let result = run(DataQuery(kind: .sum, category: "продукты"), try fixture())
        XCTAssertEqual(result.total, 25_000, accuracy: 0.001)
        XCTAssertEqual(result.count, 3)
    }

    func testMerchantFilterMatchesTitleOrBrand() throws {
        let byBrand = run(DataQuery(kind: .sum, merchant: "ararat"), try fixture())
        XCTAssertEqual(byBrand.count, 3)
        XCTAssertEqual(byBrand.total, 25_000, accuracy: 0.001)

        // У этой операции нет бренда: совпадение по названию
        let byTitle = run(DataQuery(kind: .sum, merchant: "yandex"), try fixture())
        XCTAssertEqual(byTitle.count, 1)
        XCTAssertEqual(byTitle.total, 3_000, accuracy: 0.001)
    }

    func testCardFilterUsesLastFourDigits() throws {
        XCTAssertEqual(run(DataQuery(kind: .sum, cardLast4: "0640"), try fixture()).total, 20_000, accuracy: 0.001)
        XCTAssertEqual(run(DataQuery(kind: .sum, cardLast4: "1111"), try fixture()).total, 8_000, accuracy: 0.001)
        XCTAssertEqual(run(DataQuery(kind: .sum, cardLast4: "9999"), try fixture()).count, 0)
    }

    // MARK: - Разбивка

    func testBreakdownByMonthGoesInChronologicalOrder() throws {
        let result = run(DataQuery(kind: .breakdown, groupBy: .month), try fixture())
        XCTAssertEqual(result.groups.map(\.name), ["2026-09", "2026-10"])
        XCTAssertEqual(result.groups.map(\.total), [23_000, 6_500])
        XCTAssertEqual(result.groups.map(\.count), [3, 2])
        XCTAssertEqual(result.groupCount, 2)
    }

    func testBreakdownByDayAndWeekNameGroupsByTheirStart() throws {
        let days = run(DataQuery(kind: .breakdown, groupBy: .day), try fixture())
        XCTAssertEqual(days.groups.first?.name, "2026-09-03")
        XCTAssertEqual(days.groupCount, 5)

        // 3 сентября 2026 — четверг, неделя названа по первому дню недели этого календаря
        let weeks = run(DataQuery(kind: .breakdown, groupBy: .week), try fixture())
        XCTAssertEqual(weeks.groups.first?.name, "2026-08-30")
    }

    func testBreakdownByMerchantSortsByTotalAndHonoursLimit() throws {
        let result = run(DataQuery(kind: .breakdown, groupBy: .merchant, limit: 2), try fixture())
        XCTAssertEqual(result.groups.map(\.name), ["Ararat Market", "Yandex Go"])
        XCTAssertEqual(result.groups.first?.total, 25_000)
        XCTAssertEqual(result.groups.first?.count, 3)
        XCTAssertEqual(result.groupCount, 3, "всего групп больше, чем показано")
    }

    func testBreakdownByCardNamesOperationsWithoutCard() throws {
        let result = run(DataQuery(kind: .breakdown, groupBy: .card), try fixture())
        XCTAssertEqual(result.groups.map(\.name), ["0640", "1111", "без карты"])
        XCTAssertEqual(result.groups.map(\.total), [20_000, 8_000, 1_500])
    }

    func testBreakdownWithoutGroupByUsesCategories() throws {
        let result = run(DataQuery(kind: .breakdown), try fixture())
        XCTAssertEqual(result.groupCount, 3)
        XCTAssertEqual(result.groups.first?.total, 25_000)
    }

    // MARK: - Список

    func testListIsNewestFirstByDefault() throws {
        let result = run(DataQuery(kind: .list), try fixture())
        XCTAssertEqual(result.lines.first?.title, "Cafe")
        XCTAssertEqual(result.lines.count, 5)
        XCTAssertEqual(result.lines.last?.date, try date(2026, 9, 3))
    }

    func testListCanSortByLargestAndTakeTheCardNumber() throws {
        let result = run(DataQuery(kind: .list, sort: .largest, limit: 2), try fixture())
        XCTAssertEqual(result.lines.map(\.amount), [12_000, 8_000])
        XCTAssertEqual(result.lines.map(\.cardLast4), ["0640", "1111"])
        XCTAssertEqual(result.count, 5, "в итоге учтены все подходящие операции, а не только показанные")
    }

    func testListLimitIsCapped() throws {
        let groceries = try category("Продукты")
        let many = try (1...40).map { day in
            Transaction(title: "Shop \(day)", amount: Double(day), type: .expense, category: groceries, date: try date(2026, 9, 1).addingTimeInterval(Double(day) * 3_600))
        }
        let result = run(DataQuery(kind: .list, limit: 1_000), many)
        XCTAssertEqual(result.lines.count, DataQueryEngine.maxLines)
        XCTAssertEqual(result.count, 40)

        let byDefault = run(DataQuery(kind: .list), many)
        XCTAssertEqual(byDefault.lines.count, DataQueryEngine.defaultLines)

        let zero = run(DataQuery(kind: .list, limit: 0), many)
        XCTAssertEqual(zero.lines.count, DataQueryEngine.defaultLines, "ноль значит «по умолчанию»")
    }

    // MARK: - Текст для модели

    func testRenderedSumNamesTheTotalAndTheLargestOperation() throws {
        let result = run(DataQuery(kind: .sum), try fixture())
        let text = DataQueryEngine.render(result, number: 1, money: { String(Int($0)) }, date: { _ in "ДАТА" })
        XCTAssertTrue(text.hasPrefix("[1] расходы, за всё время"), text)
        XCTAssertTrue(text.contains("итого 29500"), text)
        XCTAssertTrue(text.contains("операций 5"), text)
        XCTAssertTrue(text.contains("в среднем 5900"), text)
        XCTAssertTrue(text.contains("самая крупная 12000 (Ararat Market, ДАТА)"), text)
    }

    func testRenderedEmptyResultSaysThereAreNoOperations() throws {
        let result = run(DataQuery(kind: .sum, category: "Образование"), try fixture())
        let text = DataQueryEngine.render(result, number: 2, money: { String(Int($0)) }, date: { _ in "ДАТА" })
        XCTAssertTrue(text.hasPrefix("[2] "), text)
        XCTAssertTrue(text.hasSuffix("операций нет"), text)
        XCTAssertTrue(text.contains("категория «Образование»"), text)
    }

    func testRenderedBreakdownShowsSharesOnlyForNonChronologicalGroups() throws {
        let byCategory = DataQueryEngine.render(
            run(DataQuery(kind: .breakdown, groupBy: .category), try fixture()),
            number: 1, money: { String(Int($0)) }, date: { _ in "Д" }
        )
        XCTAssertTrue(byCategory.contains("85%"), "25 000 из 29 500: \(byCategory)")

        let byMonth = DataQueryEngine.render(
            run(DataQuery(kind: .breakdown, groupBy: .month), try fixture()),
            number: 1, money: { String(Int($0)) }, date: { _ in "Д" }
        )
        XCTAssertFalse(byMonth.contains("%"), byMonth)
        XCTAssertTrue(byMonth.contains("2026-09 — 23000, операций 3"), byMonth)
    }

    func testRenderedListShowsSignCardAndTruncationNote() throws {
        let text = DataQueryEngine.render(
            run(DataQuery(kind: .list, sort: .largest, limit: 2), try fixture()),
            number: 3, money: { String(Int($0)) }, date: { _ in "Д" }
        )
        XCTAssertTrue(text.contains("найдено операций 5, показаны 2"), text)
        XCTAssertTrue(text.contains("• Д · −12000 · Ararat Market"), text)
        XCTAssertTrue(text.contains("карта 0640"), text)

        let income = DataQueryEngine.render(
            run(DataQuery(kind: .list, type: .income), try fixture()),
            number: 1, money: { String(Int($0)) }, date: { _ in "Д" }
        )
        XCTAssertTrue(income.contains("+400000"), income)
        XCTAssertTrue(income.contains("доходы"), income)
    }

    func testDescribeListsEveryCondition() throws {
        let query = DataQuery(kind: .sum, from: try date(2026, 9, 1), to: try date(2026, 9, 30), category: "Продукты", merchant: "Ararat", cardLast4: "0640")
        let text = DataQueryEngine.describe(query, date: { calendar.component(.month, from: $0) == 9 ? "сентябрь" : "?" })
        XCTAssertEqual(text, "расходы, с сентябрь по сентябрь, категория «Продукты», магазин или получатель «Ararat», карта 0640")
    }
}

/// Запросы в ответе модели: разбор, схема и продолжение переписки
@MainActor
final class DataQueryParsingTests: XCTestCase {

    private let sampleQueries = """
    {"reply":"Считаю…","operations":[],"actions":[],"queries":[
      {"kind":"sum","type":"expense","date_from":"2026-09-01","date_to":"2026-09-30","category":"Продукты","merchant":"","card_last4":"","group_by":"none","sort":"newest","limit":0},
      {"kind":"breakdown","type":"income","date_from":"","date_to":"","category":"","merchant":"Ararat","card_last4":"card 0640","group_by":"month","sort":"largest","limit":6.0},
      {"kind":"launch_rocket","type":"expense","date_from":"","date_to":"","category":"","merchant":"","card_last4":"","group_by":"none","sort":"newest","limit":0}
    ]}
    """

    func testQueriesAreParsedAndUnknownKindsAreDropped() throws {
        let reply = try CloudFinanceAssistant.parse(sampleQueries, provider: .claude)
        XCTAssertEqual(reply.queries.count, 2, "неизвестный вид запроса отбрасывается")

        let sum = reply.queries[0]
        XCTAssertEqual(sum.kind, .sum)
        XCTAssertEqual(sum.type, .expense)
        XCTAssertEqual(sum.category, "Продукты")
        XCTAssertNil(sum.merchant, "пустая строка значит «не задано»")
        XCTAssertNil(sum.cardLast4)
        XCTAssertNil(sum.groupBy, "none значит «не задано»")
        XCTAssertEqual(sum.sort, .newest)

        let from = try XCTUnwrap(sum.from)
        let to = try XCTUnwrap(sum.to)
        XCTAssertEqual(Calendar.current.component(.day, from: from), 1)
        XCTAssertEqual(Calendar.current.component(.day, from: to), 30)
        XCTAssertEqual(Calendar.current.component(.hour, from: to), 23, "названа только дата: период до конца этого дня")

        let breakdown = reply.queries[1]
        XCTAssertEqual(breakdown.kind, .breakdown)
        XCTAssertEqual(breakdown.type, .income)
        XCTAssertEqual(breakdown.merchant, "Ararat")
        XCTAssertEqual(breakdown.cardLast4, "0640", "из названия карты берутся только четыре цифры")
        XCTAssertEqual(breakdown.groupBy, .month)
        XCTAssertEqual(breakdown.sort, .largest)
        XCTAssertEqual(breakdown.limit, 6)
        XCTAssertNil(breakdown.from)
        XCTAssertNil(breakdown.to)
    }

    func testReplyWithoutQueriesHasNone() throws {
        let reply = try CloudFinanceAssistant.parse(#"{"reply":"Привет","operations":[],"actions":[]}"#, provider: .gemini)
        XCTAssertTrue(reply.queries.isEmpty)
        let older = try CloudFinanceAssistant.parse(#"{"reply":"Привет","operations":[]}"#, provider: .gemini)
        XCTAssertTrue(older.queries.isEmpty)
    }

    func testSchemaListsQueriesWithoutNulls() throws {
        let schema = CloudFinanceAssistant.responseSchema()
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let queries = try XCTUnwrap(properties["queries"] as? [String: Any])
        XCTAssertEqual(queries["type"] as? String, "array")

        let item = try XCTUnwrap(queries["items"] as? [String: Any])
        let itemProperties = try XCTUnwrap(item["properties"] as? [String: Any])
        // Строгие схемы требуют, чтобы все поля были обязательными и не было лишних
        XCTAssertEqual(Set(item["required"] as? [String] ?? []), Set(itemProperties.keys))
        XCTAssertEqual(item["additionalProperties"] as? Bool, false)
        for (name, value) in itemProperties {
            let field = try XCTUnwrap(value as? [String: Any], name)
            XCTAssertNil(field["anyOf"], "поле \(name) без null: лишние union-типы утяжеляют схему")
        }

        let kind = try XCTUnwrap(itemProperties["kind"] as? [String: Any])
        XCTAssertEqual(kind["enum"] as? [String], DataQuery.Kind.allCases.map(\.rawValue))
        let groupBy = try XCTUnwrap(itemProperties["group_by"] as? [String: Any])
        XCTAssertEqual(groupBy["enum"] as? [String], ["none"] + DataQuery.GroupBy.allCases.map(\.rawValue))
    }

    func testSchemaWithQueriesIsAcceptedInEveryFormat() throws {
        let schema = CloudFinanceAssistant.responseSchema()
        XCTAssertTrue(JSONSerialization.isValidJSONObject(schema))
        XCTAssertTrue(JSONSerialization.isValidJSONObject(GeminiAPI.geminiSchema(schema)))

        let prompt = AIPrompt(system: "SYSTEM", turns: [], leadingText: nil, images: [], text: "question")
        XCTAssertNoThrow(try ClaudeAPI.requestBody(prompt, schema: schema))
        XCTAssertNoThrow(try OpenAIAPI.requestBody(prompt, schema: schema))
        XCTAssertNoThrow(try GeminiAPI.requestBody(prompt, schema: schema))
    }

    func testFollowUpKeepsRolesAlternatingAndCarriesTheResults() {
        let prompt = AIPrompt(
            system: "SYSTEM",
            turns: [CloudTurn(isUser: true, text: "привет"), CloudTurn(isUser: false, text: "здравствуйте")],
            leadingText: "ещё",
            images: [Data([1, 2, 3])],
            text: "сколько в сентябре?"
        )
        let reply = CloudReply(text: "Считаю…", operations: [], actions: [], queries: [DataQuery(kind: .sum, category: "Продукты")])

        let next = CloudFinanceAssistant.followUp(after: prompt, reply: reply, results: "[1] итого 100", isLast: false)
        XCTAssertEqual(next.system, "SYSTEM")
        XCTAssertEqual(next.turns.map(\.isUser), [true, false, true, false])
        XCTAssertEqual(next.turns[2].text, "ещё\n\nсколько в сентябре?", "вопрос и хвост переписки одной репликой")
        XCTAssertTrue(next.turns[3].text.contains("Продукты"), next.turns[3].text)
        XCTAssertNil(next.leadingText)
        XCTAssertTrue(next.images.isEmpty, "скриншоты уже разобраны на первом шаге")
        XCTAssertTrue(next.text.contains("[1] итого 100"))
        XCTAssertTrue(next.text.contains("можно запросить ещё"))

        let last = CloudFinanceAssistant.followUp(after: prompt, reply: reply, results: "[1] итого 100", isLast: true)
        XCTAssertTrue(last.text.contains("Новых запросов больше нет"))
        XCTAssertFalse(last.text.contains("можно запросить ещё"))
    }

    func testFollowUpWorksWithoutAnyHistory() {
        let prompt = AIPrompt(system: "S", turns: [], leadingText: nil, images: [], text: "вопрос")
        let reply = CloudReply(text: "", operations: [], actions: [], queries: [DataQuery(kind: .list)])
        let next = CloudFinanceAssistant.followUp(after: prompt, reply: reply, results: "R", isLast: false)
        XCTAssertEqual(next.turns.map(\.isUser), [true, false], "переписка начинается с пользователя и кончается ответом помощника")
        XCTAssertEqual(next.turns.first?.text, "вопрос")

        let body = try? ClaudeAPI.requestBody(next, schema: CloudFinanceAssistant.responseSchema())
        XCTAssertNotNil(body)
    }
}
