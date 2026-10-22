import XCTest
@testable import SamFinance

@MainActor
final class FinanceServiceTests: XCTestCase {
    private var service: FinanceService { FinanceService.shared }

    override func setUp() async throws {
        try await super.setUp()
        service.resetAllData()
    }

    override func tearDown() async throws {
        service.resetAllData()
        try await super.tearDown()
    }

    private func category(_ name: String, type: TransactionType = .expense) throws -> Category {
        try XCTUnwrap(service.categories.first { $0.name == name && $0.type == type })
    }

    private func makeCard(last4: String = "1111", balance: Double = 1_000, updatedAt: Date? = nil) -> Card {
        Card(last4: last4, holderName: "TEST USER", balance: balance, colorHex: "#2A2B30", gradientColors: ["#2A2B30"], balanceUpdatedAt: updatedAt)
    }

    func testAddAndDeleteTransaction() throws {
        let transaction = Transaction(title: "Coffee", amount: 1_500, type: .expense, category: try category("Рестораны"))
        XCTAssertTrue(service.addTransaction(transaction))
        XCTAssertEqual(service.transactions.count, 1)
        XCTAssertEqual(service.totalExpenses, 1_500, accuracy: 0.001)

        service.deleteTransaction(transaction)
        XCTAssertTrue(service.transactions.isEmpty)
    }

    func testTotalsSeparateIncomeAndExpenses() throws {
        service.addTransaction(Transaction(title: "Salary", amount: 400_000, type: .income, category: try category("Зарплата", type: .income)))
        service.addTransaction(Transaction(title: "Taxi", amount: 2_000, type: .expense, category: try category("Транспорт")))
        XCTAssertEqual(service.totalIncome, 400_000, accuracy: 0.001)
        XCTAssertEqual(service.totalExpenses, 2_000, accuracy: 0.001)
    }

    func testFrozenCardIsNotCountedInTotalBalance() {
        let active = makeCard(last4: "1111", balance: 100)
        let frozen = makeCard(last4: "2222", balance: 200)
        service.addCard(active, number: "")
        service.addCard(frozen, number: "")
        XCTAssertEqual(service.totalBalance, 300, accuracy: 0.001)

        service.toggleFreezeCard(id: frozen.id)
        XCTAssertEqual(service.totalBalance, 100, accuracy: 0.001)
    }

    func testSyncCardBalanceIgnoresOlderMessages() throws {
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        let card = makeCard(balance: 500, updatedAt: reference)
        service.addCard(card, number: "")

        service.syncCardBalance(id: card.id, balance: 111, asOf: reference.addingTimeInterval(-3_600))
        XCTAssertEqual(try XCTUnwrap(service.card(withLast4: "1111")).balance, 500, accuracy: 0.001)

        service.syncCardBalance(id: card.id, balance: 777, asOf: reference.addingTimeInterval(3_600))
        XCTAssertEqual(try XCTUnwrap(service.card(withLast4: "1111")).balance, 777, accuracy: 0.001)
    }

    func testApplyToCardBalanceNeedsNewerDate() throws {
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        let card = makeCard(balance: 1_000, updatedAt: reference)
        service.addCard(card, number: "")

        XCTAssertNil(service.applyToCardBalance(id: card.id, delta: -100, asOf: reference.addingTimeInterval(-60)))
        XCTAssertEqual(service.applyToCardBalance(id: card.id, delta: -100, asOf: reference.addingTimeInterval(60)), -100)
        XCTAssertEqual(try XCTUnwrap(service.card(withLast4: "1111")).balance, 900, accuracy: 0.001)
    }

    func testDeletingTransactionRevertsItsBalanceChange() throws {
        let card = makeCard(balance: 700)
        service.addCard(card, number: "")
        let transaction = Transaction(
            title: "Shop", amount: 300, type: .expense, category: try category("Продукты"),
            cardId: card.id, balanceDelta: -300
        )
        service.addTransaction(transaction)

        service.deleteTransaction(transaction)
        XCTAssertEqual(try XCTUnwrap(service.card(withLast4: "1111")).balance, 1_000, accuracy: 0.001)
    }

    func testDeletingCardRemovesItsGoals() {
        let card = makeCard()
        let other = makeCard(last4: "2222")
        service.addCard(card, number: "")
        service.addCard(other, number: "")
        service.addGoal(Goal(cardId: card.id, title: "Trip", targetAmount: 1_000, colorHex: "#C6F432", gradientColors: ["#C6F432"]))
        service.addGoal(Goal(cardId: other.id, title: "Laptop", targetAmount: 2_000, colorHex: "#C6F432", gradientColors: ["#C6F432"]))

        service.deleteCard(id: card.id)
        XCTAssertTrue(service.goalsForCard(cardId: card.id).isEmpty)
        XCTAssertEqual(service.goalsForCard(cardId: other.id).count, 1)
        XCTAssertEqual(service.goals.count, 1)
    }

    func testGoalDeposit() {
        let card = makeCard()
        service.addCard(card, number: "")
        let goal = Goal(cardId: card.id, title: "Trip", targetAmount: 1_000, colorHex: "#C6F432", gradientColors: ["#C6F432"])
        service.addGoal(goal)

        service.addFundsToGoal(id: goal.id, amount: 250)
        XCTAssertEqual(service.goalsForCard(cardId: card.id).first?.currentAmount ?? 0, 250, accuracy: 0.001)
    }

    func testDebtPaymentToggle() {
        let debt = Debt(name: "Armen", amount: 5_000, isLent: true)
        service.addDebt(debt)
        XCTAssertEqual(service.debts.first?.isPaid, false)

        service.togglePayDebt(id: debt.id)
        XCTAssertEqual(service.debts.first?.isPaid, true)

        service.deleteDebt(id: debt.id)
        XCTAssertTrue(service.debts.isEmpty)
    }

    func testExternalKeyAndReviewCount() throws {
        let transaction = Transaction(
            title: "Shop", amount: 100, type: .expense, category: try category("Прочее"),
            externalKey: "key-1", needsReview: true
        )
        service.addTransaction(transaction)
        XCTAssertTrue(service.hasTransaction(externalKey: "key-1"))
        XCTAssertFalse(service.hasTransaction(externalKey: "key-2"))
        XCTAssertEqual(service.reviewCount, 1)

        service.updateCategory(transactionID: transaction.id, category: try category("Продукты"))
        XCTAssertEqual(service.reviewCount, 0)
        XCTAssertEqual(service.transactions.first?.category.name, "Продукты")
    }

    func testCategoryLookupNeverMixesTypes() {
        XCTAssertEqual(service.category(named: "Зарплата", type: .income).type, .income)
        // Название расходной категории с типом «доход» не должно дать расходную категорию
        XCTAssertEqual(service.category(named: "Продукты", type: .income).type, .income)
    }

    func testDataSurvivesReload() throws {
        service.addTransaction(Transaction(title: "Persisted", amount: 42, type: .expense, category: try category("Прочее")))
        let reloaded = FinanceService()
        XCTAssertTrue(reloaded.transactions.contains { $0.title == "Persisted" })
    }

    func testResetClearsEverything() throws {
        service.addCard(makeCard(), number: "")
        service.addDebt(Debt(name: "X", amount: 1, isLent: false))
        service.addTransaction(Transaction(title: "T", amount: 1, type: .expense, category: try category("Прочее")))
        service.resetAllData()
        XCTAssertTrue(service.cards.isEmpty)
        XCTAssertTrue(service.debts.isEmpty)
        XCTAssertTrue(service.transactions.isEmpty)
    }
}
