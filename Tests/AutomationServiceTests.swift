import XCTest
@testable import SamFinance

@MainActor
final class AutomationServiceTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        FinanceService.shared.resetAllData()
        let defaults = UserDefaults.standard
        for key in [AutomationKeys.autoCreateCards, AutomationKeys.skipOwnTransfers, AutomationKeys.ownSurnames, AutomationKeys.merchantRules] {
            defaults.removeObject(forKey: key)
        }
    }

    override func tearDown() async throws {
        FinanceService.shared.resetAllData()
        try await super.tearDown()
    }

    private func parsed(_ text: String) throws -> ParsedSMSTransaction {
        try XCTUnwrap(SMSParser.parse(text: text))
    }

    func testIngestRecordsTransactionAndCreatesCardWithBalance() throws {
        let result = AutomationService.shared.ingest(try parsed(SMSSamples.groceryPurchase))
        guard case .recorded(let transaction, let createdCard) = result else {
            return XCTFail("Ожидалась записанная операция, получено \(result)")
        }
        XCTAssertTrue(createdCard)
        XCTAssertEqual(transaction.amount, 3_500, accuracy: 0.001)
        XCTAssertEqual(transaction.category.name, "Продукты")
        XCTAssertEqual(transaction.type, .expense)

        let card = try XCTUnwrap(FinanceService.shared.card(withLast4: "0640"))
        XCTAssertEqual(card.balance, 120_000, accuracy: 0.001)
        XCTAssertEqual(transaction.cardId, card.id)
        XCTAssertEqual(FinanceService.shared.transactions.count, 1)
    }

    func testSameMessageIsRecordedOnlyOnce() throws {
        let message = try parsed(SMSSamples.groceryPurchase)
        _ = AutomationService.shared.ingest(message)
        let second = AutomationService.shared.ingest(message)
        guard case .duplicate = second else {
            return XCTFail("Повторная СМС должна считаться дублем, получено \(second)")
        }
        XCTAssertEqual(FinanceService.shared.transactions.count, 1)
    }

    func testTransferToOwnNameIsNotCountedButBalanceIsSynced() throws {
        UserDefaults.standard.set("PETROSYAN", forKey: AutomationKeys.ownSurnames)
        let result = AutomationService.shared.ingest(try parsed(SMSSamples.transferOut))
        guard case .skippedTransfer = result else {
            return XCTFail("Перевод себе не должен записываться, получено \(result)")
        }
        XCTAssertTrue(FinanceService.shared.transactions.isEmpty)
        let card = try XCTUnwrap(FinanceService.shared.card(withLast4: "0640"))
        XCTAssertEqual(card.balance, 100_000, accuracy: 0.001)
    }

    func testTransferToSomeoneElseIsRecordedAsTransferExpense() throws {
        let result = AutomationService.shared.ingest(try parsed(SMSSamples.transferOut))
        guard case .recorded(let transaction, _) = result else {
            return XCTFail("Перевод чужому должен записываться, получено \(result)")
        }
        XCTAssertEqual(transaction.type, .expense)
        XCTAssertEqual(transaction.category.name, "Переводы")
    }

    func testCardIsNotCreatedWhenAutoCreateIsOff() throws {
        UserDefaults.standard.set(false, forKey: AutomationKeys.autoCreateCards)
        let result = AutomationService.shared.ingest(try parsed(SMSSamples.groceryPurchase))
        guard case .recorded(let transaction, let createdCard) = result else {
            return XCTFail("Операция должна записаться и без карты, получено \(result)")
        }
        XCTAssertFalse(createdCard)
        XCTAssertNil(transaction.cardId)
        XCTAssertTrue(FinanceService.shared.cards.isEmpty)
    }

    func testLearnedCategoryOverridesParserGuess() throws {
        let restaurants = try XCTUnwrap(FinanceService.shared.categories.first { $0.name == "Рестораны" })
        AutomationService.shared.learnCategory(merchant: "Sas Supermarket", category: restaurants)

        let result = AutomationService.shared.ingest(try parsed(SMSSamples.groceryPurchase))
        guard case .recorded(let transaction, _) = result else {
            return XCTFail("Ожидалась записанная операция, получено \(result)")
        }
        XCTAssertEqual(transaction.category.name, "Рестораны")
        XCTAssertNil(transaction.needsReview)
    }

    func testIngestAllCountsEachOutcome() throws {
        let messages = [
            try parsed(SMSSamples.groceryPurchase),
            try parsed(SMSSamples.salary),
            try parsed(SMSSamples.groceryPurchase)
        ]
        let summary = AutomationService.shared.ingestAll(messages)
        XCTAssertEqual(summary.recorded, 2)
        XCTAssertEqual(summary.duplicates, 1)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertFalse(summary.text.isEmpty)
    }

    func testOlderMessageDoesNotOverwriteNewerCardBalance() throws {
        // Сначала приходит более свежая СМС (15 января, остаток 120 000), потом более ранняя (10 января, остаток 270 000)
        _ = AutomationService.shared.ingest(try parsed(SMSSamples.groceryPurchase))
        _ = AutomationService.shared.ingest(try parsed(SMSSamples.salary))
        XCTAssertEqual(FinanceService.shared.transactions.count, 2)
        let card = try XCTUnwrap(FinanceService.shared.card(withLast4: "0640"))
        XCTAssertEqual(card.balance, 120_000, accuracy: 0.001)
    }
}
