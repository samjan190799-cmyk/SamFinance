import XCTest
@testable import SamFinance

/// Два вида баланса: карты и наличные. Ручная правка наличных, операции «из наличных», общий баланс, хранение
@MainActor
final class CashBalanceTests: XCTestCase {
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

    private func expense(_ amount: Double, on date: Date = Date()) throws -> Transaction {
        let category = try XCTUnwrap(service.categories.first { $0.name == "Продукты" && $0.type == .expense })
        return Transaction(title: "Shop", amount: amount, type: .expense, category: category, date: date)
    }

    private func income(_ amount: Double, on date: Date = Date()) throws -> Transaction {
        let category = try XCTUnwrap(service.categories.first { $0.type == .income })
        return Transaction(title: "Pay", amount: amount, type: .income, category: category, date: date)
    }

    // MARK: - Кошелёк и общий баланс

    func testCashStartsEmptyAndTotalIsCardsPlusCash() {
        XCTAssertEqual(service.cashBalance, 0)
        XCTAssertEqual(service.totalBalance, 0)

        service.addCard(makeCard(balance: 300), number: "")
        service.addCard(makeCard(last4: "2222", balance: 999, frozen: true), number: "")
        XCTAssertTrue(service.adjustCashBalance(by: 200))

        XCTAssertEqual(service.cardsBalance, 300, accuracy: 0.001, "замороженная карта в баланс не входит")
        XCTAssertEqual(service.cashBalance, 200, accuracy: 0.001)
        XCTAssertEqual(service.totalBalance, 500, accuracy: 0.001)
    }

    func testTopUpAndReduceCashWithoutMakingTransactions() {
        XCTAssertTrue(service.adjustCashBalance(by: 1_000))
        XCTAssertTrue(service.adjustCashBalance(by: -250.5))
        XCTAssertEqual(service.cashBalance, 749.5, accuracy: 0.001)

        XCTAssertTrue(service.transactions.isEmpty, "правка не операция: в доходы и расходы она не попадает")
        XCTAssertEqual(service.totalIncome, 0, accuracy: 0.001)
        XCTAssertEqual(service.totalExpenses, 0, accuracy: 0.001)
    }

    func testReducingCashByTheWholeAmountGivesPlainZero() {
        XCTAssertTrue(service.setCashBalance(to: 1_250.75))
        XCTAssertTrue(service.adjustCashBalance(by: -1_250.75))
        XCTAssertEqual(service.cashBalance, 0)
        XCTAssertEqual(service.cashBalance.sign, .plus, "должен получиться обычный ноль, а не «−0»")
    }

    func testCashMayGoBelowZero() {
        XCTAssertTrue(service.adjustCashBalance(by: -100))
        XCTAssertEqual(service.cashBalance, -100, accuracy: 0.001)
    }

    func testInvalidCashAdjustmentsAreIgnored() {
        XCTAssertTrue(service.setCashBalance(to: 100))
        XCTAssertFalse(service.adjustCashBalance(by: 0))
        XCTAssertFalse(service.adjustCashBalance(by: .nan))
        XCTAssertFalse(service.adjustCashBalance(by: .infinity))
        XCTAssertFalse(service.setCashBalance(to: .nan))
        XCTAssertEqual(service.cashBalance, 100, accuracy: 0.001)
    }

    func testZeroTotalBalanceAlsoZeroesCash() {
        service.addCard(makeCard(balance: 300), number: "")
        service.addCard(makeCard(last4: "2222", balance: 0), number: "")
        XCTAssertTrue(service.setCashBalance(to: 450))

        XCTAssertEqual(service.zeroTotalBalance(), 2, "обнулились карта с деньгами и наличные; пустая карта не тронута")
        XCTAssertEqual(service.totalBalance, 0, accuracy: 0.001)
        XCTAssertEqual(service.cashBalance, 0)
        XCTAssertEqual(service.zeroTotalBalance(), 0, "повторное обнуление ничего не меняет")
    }

    func testZeroTotalBalanceWithOnlyCash() {
        XCTAssertTrue(service.setCashBalance(to: 80))
        XCTAssertEqual(service.zeroTotalBalance(), 1)
        XCTAssertEqual(service.cashBalance, 0)
    }

    // MARK: - Операции из наличных

    func testCashExpenseLowersCashAndDeletingItRestoresIt() throws {
        XCTAssertTrue(service.setCashBalance(to: 1_000))
        let transaction = try expense(250)
        XCTAssertTrue(service.addTransaction(transaction, account: .cash))

        XCTAssertEqual(service.cashBalance, 750, accuracy: 0.001)
        let saved = try XCTUnwrap(service.transactions.first)
        XCTAssertEqual(saved.isCash, true)
        XCTAssertNil(saved.cardId)
        XCTAssertEqual(try XCTUnwrap(saved.balanceDelta), -250, accuracy: 0.001)
        XCTAssertEqual(service.totalExpenses, 250, accuracy: 0.001)

        service.deleteTransaction(saved)
        XCTAssertEqual(service.cashBalance, 1_000, accuracy: 0.001, "удалённый расход возвращает деньги в наличные")
    }

    func testCashIncomeRaisesCash() throws {
        XCTAssertTrue(service.setCashBalance(to: 100))
        XCTAssertTrue(service.addTransaction(try income(400), account: .cash))
        XCTAssertEqual(service.cashBalance, 500, accuracy: 0.001)
    }

    func testCashOperationsWorkBeforeAnyManualAdjustment() throws {
        XCTAssertTrue(service.addTransaction(try expense(50), account: .cash))
        XCTAssertEqual(service.cashBalance, -50, accuracy: 0.001, "пока наличные не правили вручную, баланс считается по операциям")
    }

    func testOperationOlderThanTheLastAdjustmentIsRecordedButKeepsTheBalance() throws {
        XCTAssertTrue(service.setCashBalance(to: 1_000))
        let yesterday = Date().addingTimeInterval(-86_400)
        XCTAssertFalse(service.willChangeBalance(of: .cash, on: yesterday))
        XCTAssertTrue(service.willChangeBalance(of: .cash, on: Date().addingTimeInterval(60)))

        XCTAssertTrue(service.addTransaction(try expense(300, on: yesterday), account: .cash))
        XCTAssertEqual(service.cashBalance, 1_000, accuracy: 0.001)
        let saved = try XCTUnwrap(service.transactions.first)
        XCTAssertEqual(saved.isCash, true)
        XCTAssertNil(saved.balanceDelta, "баланс не менялся, откатывать при удалении нечего")

        service.deleteTransaction(saved)
        XCTAssertEqual(service.cashBalance, 1_000, accuracy: 0.001)
    }

    func testBackdatedCashOperationsAfterNewerOnesStillCount() throws {
        XCTAssertTrue(service.setCashBalance(to: 1_000))
        let soon = Date().addingTimeInterval(120)
        let later = Date().addingTimeInterval(240)
        XCTAssertTrue(service.addTransaction(try expense(100, on: later), account: .cash))
        XCTAssertTrue(service.addTransaction(try expense(50, on: soon), account: .cash))
        XCTAssertEqual(service.cashBalance, 850, accuracy: 0.001, "точка отсчёта наличных двигается только правкой, а не операциями")
    }

    func testCardExpenseWithAnAccountChangesTheCardNotCash() throws {
        let card = makeCard(balance: 1_000, updatedAt: Date().addingTimeInterval(-3_600))
        service.addCard(card, number: "")
        XCTAssertTrue(service.setCashBalance(to: 500))

        XCTAssertTrue(service.addTransaction(try expense(100), account: .card(card.id)))
        XCTAssertEqual(try XCTUnwrap(service.cards.first).balance, 900, accuracy: 0.001)
        XCTAssertEqual(service.cashBalance, 500, accuracy: 0.001)
        let saved = try XCTUnwrap(service.transactions.first)
        XCTAssertEqual(saved.cardId, card.id)
        XCTAssertNil(saved.isCash)

        service.deleteTransaction(saved)
        XCTAssertEqual(try XCTUnwrap(service.cards.first).balance, 1_000, accuracy: 0.001)
    }

    func testUnknownCardIsRefused() throws {
        XCTAssertFalse(service.addTransaction(try expense(10), account: .card(UUID())))
        XCTAssertTrue(service.transactions.isEmpty)
    }

    func testWithoutAnAccountNoBalanceMoves() throws {
        let card = makeCard(balance: 1_000, updatedAt: Date().addingTimeInterval(-3_600))
        service.addCard(card, number: "")
        XCTAssertTrue(service.setCashBalance(to: 500))

        XCTAssertTrue(service.addTransaction(try expense(100), account: nil))
        XCTAssertEqual(service.totalBalance, 1_500, accuracy: 0.001, "как раньше: операция без счёта баланс не меняет")
        let saved = try XCTUnwrap(service.transactions.first)
        XCTAssertNil(saved.isCash)
        XCTAssertNil(saved.cardId)
    }

    // MARK: - Хранение

    func testCashIsSavedAndReloaded() throws {
        XCTAssertTrue(service.setCashBalance(to: 1_234.5))
        XCTAssertTrue(service.addTransaction(try expense(34.5), account: .cash))

        let reloaded = FinanceService()
        XCTAssertEqual(reloaded.cashBalance, 1_200, accuracy: 0.001)
        XCTAssertNotNil(reloaded.cash.balanceUpdatedAt)
        XCTAssertEqual(reloaded.transactions.first?.isCash, true)
    }

    func testResettingAllDataClearsCash() {
        XCTAssertTrue(service.setCashBalance(to: 700))
        service.resetAllData()
        XCTAssertEqual(service.cashBalance, 0)
        XCTAssertNil(service.cash.balanceUpdatedAt)
        XCTAssertEqual(FinanceService().cashBalance, 0)
    }

    func testOldTransactionsWithoutTheCashFlagStillDecode() throws {
        let transaction = try expense(10)
        let data = try JSONEncoder().encode(transaction)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("isCash"), "у обычной операции нового поля в файле нет")
        let decoded = try JSONDecoder().decode(Transaction.self, from: data)
        XCTAssertNil(decoded.isCash)
        XCTAssertEqual(decoded, transaction)
    }

    func testAccountStorageKeyRoundTrip() {
        let id = UUID()
        XCTAssertEqual(BalanceAccount(storageKey: BalanceAccount.cash.storageKey), .cash)
        XCTAssertEqual(BalanceAccount(storageKey: BalanceAccount.card(id).storageKey), .card(id))
        XCTAssertNil(BalanceAccount(storageKey: ""))
        XCTAssertNil(BalanceAccount(storageKey: "card:не-uuid"))
        XCTAssertNil(BalanceAccount(storageKey: "bank"))
    }
}
