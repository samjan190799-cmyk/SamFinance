import XCTest
@testable import SamFinance

/// Ручная правка баланса карты (пополнить, убавить, обнулить) и обнуление общего баланса
@MainActor
final class CardBalanceTests: XCTestCase {
    private var service: FinanceService { FinanceService.shared }

    // Вызов super.setUp() здесь не нужен (он пустой) и не компилируется в Swift 6 для MainActor-классов
    override func setUp() async throws {
        service.resetAllData()
    }

    override func tearDown() async throws {
        service.resetAllData()
    }

    private func makeCard(last4: String = "1111", balance: Double = 1_000, frozen: Bool = false, updatedAt: Date? = nil) -> Card {
        Card(last4: last4, holderName: "TEST USER", balance: balance, colorHex: "#2A2B30", gradientColors: ["#2A2B30"], isFrozen: frozen, balanceUpdatedAt: updatedAt)
    }

    private func balance(of card: Card) throws -> Double {
        try XCTUnwrap(service.cards.first { $0.id == card.id }).balance
    }

    // MARK: - Пополнить и убавить

    func testTopUpAndReduceChangeTheBalanceWithoutMakingTransactions() throws {
        let card = makeCard(balance: 1_000)
        service.addCard(card, number: "")

        XCTAssertTrue(service.adjustCardBalance(id: card.id, by: 250))
        XCTAssertEqual(try balance(of: card), 1_250, accuracy: 0.001)
        XCTAssertTrue(service.adjustCardBalance(id: card.id, by: -750.5))
        XCTAssertEqual(try balance(of: card), 499.5, accuracy: 0.001)

        XCTAssertTrue(service.transactions.isEmpty, "правка не операция: в доходы и расходы она не попадает")
        XCTAssertEqual(service.totalIncome, 0, accuracy: 0.001)
        XCTAssertEqual(service.totalExpenses, 0, accuracy: 0.001)
        XCTAssertEqual(service.totalBalance, 499.5, accuracy: 0.001)
    }

    func testReducingByTheWholeBalanceGivesPlainZero() throws {
        let card = makeCard(balance: 1_250.75)
        service.addCard(card, number: "")

        XCTAssertTrue(service.adjustCardBalance(id: card.id, by: -1_250.75))
        let result = try balance(of: card)
        XCTAssertEqual(result, 0)
        XCTAssertEqual(result.sign, .plus, "должен получиться обычный ноль, а не «−0»")
        XCTAssertEqual(service.totalBalance, 0, accuracy: 0.001)
    }

    func testBalanceMayGoBelowZero() throws {
        let card = makeCard(balance: 100)
        service.addCard(card, number: "")

        XCTAssertTrue(service.adjustCardBalance(id: card.id, by: -250))
        XCTAssertEqual(try balance(of: card), -150, accuracy: 0.001)
    }

    func testCentsAreRoundedToHundredths() throws {
        let card = makeCard(balance: 0.1)
        service.addCard(card, number: "")

        XCTAssertTrue(service.adjustCardBalance(id: card.id, by: 0.2))
        XCTAssertEqual(try balance(of: card), 0.3, accuracy: 0.0000001)
    }

    func testInvalidAdjustmentsAreIgnored() throws {
        let card = makeCard(balance: 100)
        service.addCard(card, number: "")

        XCTAssertFalse(service.adjustCardBalance(id: card.id, by: 0))
        XCTAssertFalse(service.adjustCardBalance(id: card.id, by: .nan))
        XCTAssertFalse(service.adjustCardBalance(id: card.id, by: .infinity))
        XCTAssertFalse(service.adjustCardBalance(id: UUID(), by: 10), "карты с таким номером нет")
        XCTAssertFalse(service.setCardBalance(id: card.id, to: .nan))
        XCTAssertEqual(try balance(of: card), 100, accuracy: 0.001)
    }

    func testManualAdjustmentBecomesTheNewReferencePoint() throws {
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let card = makeCard(balance: 1_000, updatedAt: old)
        service.addCard(card, number: "")

        let before = Date()
        XCTAssertTrue(service.adjustCardBalance(id: card.id, by: 100))
        let updatedAt = try XCTUnwrap(service.cards.first { $0.id == card.id }?.balanceUpdatedAt)
        XCTAssertGreaterThanOrEqual(updatedAt, before)

        // Операция, случившаяся раньше правки, баланс уже не меняет
        XCTAssertNil(service.applyToCardBalance(id: card.id, delta: -50, asOf: updatedAt.addingTimeInterval(-60)))
        XCTAssertEqual(try balance(of: card), 1_100, accuracy: 0.001)
    }

    func testAdjustedBalanceIsSaved() throws {
        let card = makeCard(balance: 100)
        service.addCard(card, number: "")
        XCTAssertTrue(service.adjustCardBalance(id: card.id, by: 50))

        let reloaded = FinanceService()
        XCTAssertEqual(try XCTUnwrap(reloaded.cards.first { $0.id == card.id }).balance, 150, accuracy: 0.001)
    }

    // MARK: - Обнулить

    func testSetCardBalanceToZero() throws {
        let card = makeCard(balance: 4_321.5)
        service.addCard(card, number: "")

        XCTAssertTrue(service.setCardBalance(id: card.id, to: 0))
        XCTAssertEqual(try balance(of: card), 0)
        XCTAssertTrue(service.transactions.isEmpty)
    }

    func testZeroTotalBalanceTouchesOnlyActiveCardsWithMoney() throws {
        let active = makeCard(last4: "1111", balance: 300)
        let secondActive = makeCard(last4: "2222", balance: -40)
        let empty = makeCard(last4: "3333", balance: 0)
        let frozen = makeCard(last4: "4444", balance: 700, frozen: true)
        for card in [active, secondActive, empty, frozen] {
            service.addCard(card, number: "")
        }
        XCTAssertEqual(service.totalBalance, 260, accuracy: 0.001)

        XCTAssertEqual(service.zeroTotalBalance(), 2, "обнулились две карты с деньгами; пустая и замороженная не тронуты")
        XCTAssertEqual(service.totalBalance, 0, accuracy: 0.001)
        XCTAssertEqual(try balance(of: active), 0)
        XCTAssertEqual(try balance(of: secondActive), 0)
        XCTAssertEqual(try balance(of: frozen), 700, accuracy: 0.001, "замороженная карта в общий баланс не входит и остаётся как была")

        XCTAssertEqual(service.zeroTotalBalance(), 0, "повторное обнуление ничего не меняет")
    }

    func testZeroTotalBalanceKeepsTransactionsAndTotals() throws {
        let card = makeCard(balance: 500)
        service.addCard(card, number: "")
        let category = try XCTUnwrap(service.categories.first { $0.name == "Продукты" && $0.type == .expense })
        service.addTransaction(Transaction(title: "Shop", amount: 120, type: .expense, category: category))

        XCTAssertEqual(service.zeroTotalBalance(), 1)
        XCTAssertEqual(service.transactions.count, 1)
        XCTAssertEqual(service.totalExpenses, 120, accuracy: 0.001)
    }
}
