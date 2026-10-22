import XCTest
@testable import SamFinance

/// Локальный помощник должен понимать вопросы на русском, английском и армянском независимо от языка телефона.
/// Тексты ответов зависят от языка, поэтому проверяется, что ответ не «справка» и содержит нужные числа и имена.
@MainActor
final class LocalFinanceAssistantTests: XCTestCase {
    private var service: FinanceService { FinanceService.shared }

    override func setUp() async throws {
        try await super.setUp()
        service.resetAllData()
        let groceries = try XCTUnwrap(service.categories.first { $0.name == "Продукты" })
        service.addTransaction(Transaction(title: "SAS", amount: 5_000, type: .expense, category: groceries, brandName: "SAS"))
        service.addTransaction(Transaction(title: "Carrefour", amount: 3_000, type: .expense, category: groceries, brandName: "Carrefour"))
        let salary = try XCTUnwrap(service.categories.first { $0.name == "Зарплата" })
        service.addTransaction(Transaction(title: "Salary", amount: 400_000, type: .income, category: salary))
        service.addCard(
            Card(last4: "7642", holderName: "TEST USER", balance: 845_300, colorHex: "#C6F432", gradientColors: ["#C6F432"]),
            number: ""
        )
        service.addDebt(Debt(name: "Armen", amount: 45_000, dueDate: Date().addingTimeInterval(5 * 86_400), isLent: false))
    }

    override func tearDown() async throws {
        service.resetAllData()
        try await super.tearDown()
    }

    private func answer(_ question: String) -> String {
        LocalFinanceAssistant.answer(question, financeService: service)
    }

    private func money(_ amount: Double) -> String {
        CurrencyManager.shared.format(amount)
    }

    func testSpendingQuestionInThreeLanguages() {
        let expected = money(8_000)
        for question in ["сколько я потратил за неделю?", "how much did I spend this week?", "որքա՞ն եմ ծախսել այս շաբաթ"] {
            let reply = answer(question)
            XCTAssertNotEqual(reply, LocalFinanceAssistant.helpText, question)
            XCTAssertTrue(reply.contains(expected), "\(question) → \(reply)")
        }
    }

    func testCategoryQuestionInThreeLanguages() {
        let expected = money(8_000)
        for question in ["сколько ушло на продукты за месяц?", "how much did I spend on groceries this month?", "որքա՞ն է գնացել մթերքի վրա այս ամիս"] {
            let reply = answer(question)
            XCTAssertTrue(reply.contains(expected), "\(question) → \(reply)")
        }
    }

    func testBalanceQuestionInThreeLanguages() {
        for question in ["какой у меня баланс?", "what is my balance?", "ի՞նչ հաշվեկշիռ ունեմ"] {
            let reply = answer(question)
            XCTAssertTrue(reply.contains("7642"), "\(question) → \(reply)")
            XCTAssertTrue(reply.contains(money(845_300)), "\(question) → \(reply)")
        }
    }

    func testDebtQuestionInThreeLanguages() {
        for question in ["кому я должен?", "whom do I owe?", "ու՞մ եմ պարտք"] {
            let reply = answer(question)
            XCTAssertTrue(reply.contains("Armen"), "\(question) → \(reply)")
            XCTAssertTrue(reply.contains(money(45_000)), "\(question) → \(reply)")
        }
    }

    func testIncomeQuestionInThreeLanguages() {
        for question in ["сколько я заработал за месяц?", "how much did I earn this month?", "որքա՞ն եկամուտ եմ ստացել այս ամիս"] {
            let reply = answer(question)
            XCTAssertTrue(reply.contains(money(400_000)), "\(question) → \(reply)")
        }
    }

    func testAdviceQuestionReturnsInsights() {
        for question in ["дай совет", "give me advice", "խորհուրդ տուր"] {
            let reply = answer(question)
            XCTAssertNotEqual(reply, LocalFinanceAssistant.helpText, question)
            XCTAssertTrue(reply.hasPrefix("•"), "\(question) → \(reply)")
        }
    }

    func testUnknownQuestionGivesHelp() {
        XCTAssertEqual(answer("blah blah"), LocalFinanceAssistant.helpText)
    }

    func testEmptyDataGivesFriendlyAnswers() {
        service.resetAllData()
        XCTAssertNotEqual(answer("what is my balance?"), LocalFinanceAssistant.helpText)
        XCTAssertNotEqual(answer("whom do I owe?"), LocalFinanceAssistant.helpText)
        XCTAssertNotEqual(answer("how much did I spend this week?"), LocalFinanceAssistant.helpText)
    }
}
