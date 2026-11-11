import XCTest
@testable import SamFinance

/// Оплата долгов и платежей с карты: расход или доход в операциях, баланс карты, защита от дублей с банковскими СМС
@MainActor
final class DebtCardPaymentTests: XCTestCase {
    private var service: FinanceService { FinanceService.shared }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private var savedMerchantRules: Any?

    // Вызов super.setUp() здесь не нужен (он пустой) и не компилируется в Swift 6 для MainActor-классов
    override func setUp() async throws {
        service.resetAllData()
        savedMerchantRules = UserDefaults.standard.object(forKey: AutomationKeys.merchantRules)
        for key in [AutomationKeys.autoCreateCards, AutomationKeys.skipOwnTransfers, AutomationKeys.ownSurnames] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() async throws {
        if let savedMerchantRules {
            UserDefaults.standard.set(savedMerchantRules, forKey: AutomationKeys.merchantRules)
        } else {
            UserDefaults.standard.removeObject(forKey: AutomationKeys.merchantRules)
        }
        service.resetAllData()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private func now() throws -> Date {
        try date(2026, 10, 26, hour: 8)
    }

    /// Карта со сверенным давно балансом: сегодняшние операции его меняют
    @discardableResult
    private func addCard(last4: String = "1234", balance: Double = 100_000) -> Card {
        let card = Card(
            last4: last4, holderName: "TEST", balance: balance, colorHex: "#2A2B30", gradientColors: ["#2A2B30", "#1C1D21"],
            balanceUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        service.addCard(card, number: "")
        return card
    }

    private func makeBill(card: Card?, kind: BillKind = .internet, amount: Double = 4_500, variable: Bool? = nil) throws -> Debt {
        let due = try date(2026, 11, 5)
        return Debt(
            name: "Ucom", amount: amount, dueDate: due, isLent: false, type: .bill, billKind: kind, repeatRule: .monthly,
            firstDueDate: due, isVariableAmount: variable, cardId: card?.id
        )
    }

    private func balance(of card: Card) throws -> Double {
        try XCTUnwrap(service.cards.first { $0.id == card.id }).balance
    }

    // MARK: - Расход с карты

    func testPayingABillFromACardRecordsAnExpenseAndLowersTheBalance() throws {
        let card = addCard()
        let bill = try makeBill(card: card)
        service.addDebt(bill)

        service.payDebt(id: bill.id, now: try now(), calendar: calendar)

        XCTAssertEqual(service.transactions.count, 1)
        let transaction = try XCTUnwrap(service.transactions.first)
        XCTAssertEqual(transaction.type, .expense)
        XCTAssertEqual(transaction.amount, 4_500, accuracy: 0.001)
        XCTAssertEqual(transaction.title, "Ucom")
        XCTAssertEqual(transaction.category.name, "Жилье")
        XCTAssertEqual(transaction.cardId, card.id)
        XCTAssertEqual(transaction.debtId, bill.id)
        XCTAssertEqual(transaction.date, try now())
        XCTAssertEqual(transaction.balanceDelta ?? 0, -4_500, accuracy: 0.001)
        XCTAssertEqual(try balance(of: card), 95_500, accuracy: 0.001)
        XCTAssertEqual(service.debts.first?.dueDate, try date(2026, 12, 5), "срок платежа перешёл дальше, как и раньше")
    }

    func testWithoutACardNothingIsRecorded() throws {
        let card = addCard()
        let bill = try makeBill(card: nil)
        service.addDebt(bill)
        service.payDebt(id: bill.id, now: try now(), calendar: calendar)

        XCTAssertTrue(service.transactions.isEmpty)
        XCTAssertEqual(try balance(of: card), 100_000, accuracy: 0.001)
        XCTAssertEqual(service.debts.first?.dueDate, try date(2026, 12, 5))
    }

    func testTheCardCanBeChosenForOnePayment() throws {
        let card = addCard()
        let bill = try makeBill(card: nil)
        service.addDebt(bill)
        service.payDebt(id: bill.id, source: .card(card.id), now: try now(), calendar: calendar)
        XCTAssertEqual(service.transactions.count, 1)
        XCTAssertEqual(try balance(of: card), 95_500, accuracy: 0.001)
    }

    func testPaymentCanBeLeftOutOfTheOperations() throws {
        let card = addCard()
        let bill = try makeBill(card: card)
        service.addDebt(bill)
        service.payDebt(id: bill.id, source: .notRecorded, now: try now(), calendar: calendar)

        XCTAssertTrue(service.transactions.isEmpty)
        XCTAssertEqual(try balance(of: card), 100_000, accuracy: 0.001)
        XCTAssertEqual(service.debts.first?.dueDate, try date(2026, 12, 5), "срок всё равно переходит дальше")
    }

    func testDeletedCardIsIgnored() throws {
        addCard()
        let bill = Debt(name: "Ucom", amount: 4_500, dueDate: try date(2026, 11, 5), isLent: false, type: .bill, billKind: .internet, repeatRule: .monthly, cardId: UUID())
        service.addDebt(bill)
        service.payDebt(id: bill.id, now: try now(), calendar: calendar)
        XCTAssertTrue(service.transactions.isEmpty)
        XCTAssertEqual(service.debts.first?.dueDate, try date(2026, 12, 5))
    }

    func testDeletingTheCardClearsItFromDebts() throws {
        let card = addCard()
        let bill = try makeBill(card: card)
        service.addDebt(bill)
        service.deleteCard(id: card.id)
        XCTAssertNil(service.debts.first?.cardId)
    }

    func testNonsensePaymentRecordsNothing() throws {
        let card = addCard()
        let bill = try makeBill(card: card)
        service.addDebt(bill)
        service.payDebt(id: bill.id, amount: 0, now: try now(), calendar: calendar)
        service.payDebt(id: bill.id, amount: -50, now: try now(), calendar: calendar)
        XCTAssertTrue(service.transactions.isEmpty)
        XCTAssertEqual(try balance(of: card), 100_000, accuracy: 0.001)
        XCTAssertEqual(service.debts.first?.dueDate, try date(2026, 11, 5), "срок не двигается")
    }

    func testDeletingThePaymentOperationReturnsTheMoney() throws {
        let card = addCard()
        let bill = try makeBill(card: card)
        service.addDebt(bill)
        service.payDebt(id: bill.id, now: try now(), calendar: calendar)
        let transaction = try XCTUnwrap(service.transactions.first)

        service.deleteTransaction(transaction)
        XCTAssertEqual(try balance(of: card), 100_000, accuracy: 0.001)
    }

    // MARK: - Суммы

    func testWhatItCameToThisTimeIsRecorded() throws {
        let card = addCard()
        let bill = try makeBill(card: card, kind: .utilities, amount: 18_000, variable: true)
        service.addDebt(bill)
        service.payDebt(id: bill.id, amount: 21_300, now: try now(), calendar: calendar)

        XCTAssertEqual(service.transactions.first?.amount ?? 0, 21_300, accuracy: 0.001)
        XCTAssertEqual(try balance(of: card), 78_700, accuracy: 0.001)
    }

    func testCreditPaymentIsRecordedWholeNotOnlyThePartThatLowersTheBalance() throws {
        let card = addCard()
        let due = try date(2026, 11, 5)
        let credit = Debt(
            name: "IDBank", amount: 120_000, dueDate: due, isLent: false, type: .credit, firstDueDate: due,
            monthlyPayment: 10_000, interestRate: 12, paymentsLeft: 12, cardId: card.id
        )
        service.addDebt(credit)
        service.payDebt(id: credit.id, now: try now(), calendar: calendar)

        let transaction = try XCTUnwrap(service.transactions.first)
        XCTAssertEqual(transaction.amount, 10_000, accuracy: 0.001, "с карты ушёл весь платёж, вместе с процентами")
        XCTAssertEqual(transaction.category.name, "Долги")
        XCTAssertEqual(try balance(of: card), 90_000, accuracy: 0.001)
        XCTAssertEqual(service.debts.first?.amount ?? 0, 111_200, accuracy: 0.001)
    }

    func testPartOfADebtIsRecordedAsTheAmountPaid() throws {
        let card = addCard()
        let debt = Debt(name: "Ани", amount: 20_000, dueDate: try date(2026, 11, 5), isLent: false, cardId: card.id)
        service.addDebt(debt)
        service.repayDebt(id: debt.id, amount: 5_000, now: try now())

        let transaction = try XCTUnwrap(service.transactions.first)
        XCTAssertEqual(transaction.type, .expense)
        XCTAssertEqual(transaction.amount, 5_000, accuracy: 0.001)
        XCTAssertEqual(transaction.category.name, "Долги")
        XCTAssertEqual(try balance(of: card), 95_000, accuracy: 0.001)
        XCTAssertEqual(service.debts.first?.amount ?? 0, 15_000, accuracy: 0.001)
    }

    func testOverpaymentRecordsOnlyWhatWasOwed() throws {
        let card = addCard()
        let debt = Debt(name: "Ани", amount: 20_000, dueDate: try date(2026, 11, 5), isLent: false, cardId: card.id)
        service.addDebt(debt)
        service.payDebt(id: debt.id, amount: 30_000, now: try now(), calendar: calendar)
        XCTAssertEqual(service.transactions.first?.amount ?? 0, 20_000, accuracy: 0.001)
        XCTAssertEqual(service.debts.first?.isPaid, true)
    }

    func testPaidDebtDoesNotTakeAnotherPartPayment() throws {
        let card = addCard()
        var debt = Debt(name: "Ани", amount: 20_000, dueDate: try date(2026, 11, 5), isLent: false, cardId: card.id)
        debt.isPaid = true
        service.addDebt(debt)
        XCTAssertNil(service.repayDebt(id: debt.id, amount: 1_000, now: try now()))
        XCTAssertTrue(service.transactions.isEmpty)
    }

    // MARK: - Возврат долга вам

    func testRepaymentToMeIsIncomeOnTheCard() throws {
        let card = addCard()
        let debt = Debt(name: "Арам", amount: 20_000, dueDate: try date(2026, 11, 5), isLent: true, cardId: card.id)
        service.addDebt(debt)
        service.payDebt(id: debt.id, now: try now(), calendar: calendar)

        let transaction = try XCTUnwrap(service.transactions.first)
        XCTAssertEqual(transaction.type, .income)
        XCTAssertEqual(transaction.category, Category.debtReturn)
        XCTAssertEqual(transaction.amount, 20_000, accuracy: 0.001)
        XCTAssertEqual(try balance(of: card), 120_000, accuracy: 0.001)
    }

    // MARK: - Дубли с банковскими СМС

    func testSMSThatCameFirstIsNotCountedTwice() throws {
        let message = try XCTUnwrap(SMSParser.parse(text: SMSSamples.groceryPurchase))
        let smsDate = try XCTUnwrap(message.date)
        guard case .recorded = AutomationService.shared.ingest(message) else {
            return XCTFail("СМС должна записаться")
        }
        let card = try XCTUnwrap(service.card(withLast4: "0640"))
        let bill = Debt(name: "Магазин", amount: 3_500, dueDate: smsDate, isLent: false, type: .bill, billKind: .other, repeatRule: .monthly, cardId: card.id)
        service.addDebt(bill)

        service.payDebt(id: bill.id, now: smsDate.addingTimeInterval(300), calendar: calendar)

        XCTAssertEqual(service.transactions.count, 1, "расход уже есть из СМС")
        XCTAssertEqual(try balance(of: card), 120_000, accuracy: 0.001)
    }

    func testSMSThatCameAfterThePaymentIsNotCountedTwice() throws {
        let message = try XCTUnwrap(SMSParser.parse(text: SMSSamples.groceryPurchase))
        let smsDate = try XCTUnwrap(message.date)
        let card = addCard(last4: "0640")
        let bill = Debt(name: "Магазин", amount: 3_500, dueDate: smsDate, isLent: false, type: .bill, billKind: .other, repeatRule: .monthly, cardId: card.id)
        service.addDebt(bill)
        service.payDebt(id: bill.id, now: smsDate.addingTimeInterval(300), calendar: calendar)
        XCTAssertEqual(service.transactions.count, 1)

        guard case .duplicate = AutomationService.shared.ingest(message) else {
            return XCTFail("СМС об уже записанной оплате должна считаться дублем")
        }
        XCTAssertEqual(service.transactions.count, 1)
        XCTAssertEqual(try balance(of: card), 96_500, accuracy: 0.001)
        XCTAssertTrue(service.hasDebtPayment(cardID: card.id, amount: 3_500, type: .expense, near: smsDate))
        XCTAssertFalse(service.hasDebtPayment(cardID: card.id, amount: 9_999, type: .expense, near: smsDate))
        XCTAssertFalse(service.hasDebtPayment(cardID: card.id, amount: 3_500, type: .income, near: smsDate))
        XCTAssertFalse(service.hasDebtPayment(cardID: card.id, amount: 3_500, type: .expense, near: smsDate.addingTimeInterval(5 * 86_400)))
    }

    func testUnrelatedSMSIsStillRecorded() throws {
        let card = addCard(last4: "0640")
        let bill = Debt(name: "Ucom", amount: 4_500, dueDate: try date(2026, 11, 5), isLent: false, type: .bill, billKind: .internet, repeatRule: .monthly, cardId: card.id)
        service.addDebt(bill)
        let message = try XCTUnwrap(SMSParser.parse(text: SMSSamples.groceryPurchase))
        service.payDebt(id: bill.id, now: try XCTUnwrap(message.date).addingTimeInterval(60), calendar: calendar)

        guard case .recorded = AutomationService.shared.ingest(message) else {
            return XCTFail("покупка на другую сумму — это другая операция")
        }
        XCTAssertEqual(service.transactions.count, 2)
    }

    // MARK: - Категории и тип

    func testPaymentCategoryFollowsTheKindOfPayment() {
        func name(_ kind: BillKind) -> String {
            Debt(name: "x", amount: 1, isLent: false, type: .bill, billKind: kind, repeatRule: .monthly).paymentCategoryName
        }
        for kind in [BillKind.utilities, .rent, .internet, .phone] {
            XCTAssertEqual(name(kind), "Жилье", kind.rawValue)
        }
        XCTAssertEqual(name(.subscription), "Развлечения")
        for kind in [BillKind.insurance, .tax, .other] {
            XCTAssertEqual(name(kind), "Прочее", kind.rawValue)
        }
        XCTAssertEqual(Debt(name: "x", amount: 1, isLent: false, type: .credit).paymentCategoryName, "Долги")
        XCTAssertEqual(Debt(name: "x", amount: 1, isLent: false).paymentCategoryName, "Долги")
        XCTAssertEqual(Debt(name: "x", amount: 1, isLent: true).paymentCategoryName, Category.debtReturn.name)
    }

    func testEveryCategoryNameOfAPaymentExistsForItsType() {
        let expense = Set(Category.defaultCategories.filter { $0.type == .expense }.map(\.name))
        for name in ["Жилье", "Развлечения", "Прочее", "Долги"] {
            XCTAssertTrue(expense.contains(name), name)
        }
        XCTAssertEqual(Category.debtReturn.type, .income)
        XCTAssertTrue(Category.defaultCategories.contains(Category.debtReturn))
    }

    func testOnlyMoneyReturnedToMeIsIncome() {
        XCTAssertEqual(Debt(name: "x", amount: 1, isLent: true).paymentType, .income)
        XCTAssertEqual(Debt(name: "x", amount: 1, isLent: false).paymentType, .expense)
        XCTAssertEqual(Debt(name: "x", amount: 1, isLent: false, type: .credit).paymentType, .expense)
        XCTAssertEqual(Debt(name: "x", amount: 1, isLent: false, type: .bill).paymentType, .expense)
    }

    // MARK: - Хранение

    func testCardSurvivesSavingOfDebtsAndTransactions() throws {
        let cardID = UUID()
        let debt = Debt(name: "Ucom", amount: 4_500, dueDate: try date(2026, 11, 5), isLent: false, cardId: cardID)
        let transaction = Transaction(
            title: "Ucom", amount: 4_500, type: .expense, category: Category.defaultCategories[0], date: try now(), cardId: cardID, debtId: debt.id
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(Debt.self, from: encoder.encode(debt)), debt)
        XCTAssertEqual(try decoder.decode(Transaction.self, from: encoder.encode(transaction)), transaction)
    }

    func testOldTransactionsWithoutALinkStillOpen() throws {
        let transaction = Transaction(title: "Кофе", amount: 500, type: .expense, category: Category.defaultCategories[3], date: try now())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(Transaction.self, from: encoder.encode(transaction))
        XCTAssertNil(restored.debtId)
    }

    func testCardPickerTitleShowsTheEndOfTheNumberAndTheName() {
        var card = Card(last4: "4318", holderName: "A", balance: 0, type: "Карта для покупок", colorHex: "#000000", gradientColors: [])
        XCTAssertEqual(card.pickerTitle, "•••• 4318 · Карта для покупок")
        card.bankName = "Ameriabank"
        XCTAssertEqual(card.pickerTitle, "•••• 4318 · Ameriabank")
        card.bankName = ""
        XCTAssertEqual(card.pickerTitle, "•••• 4318 · Карта для покупок")
    }
}

/// ИИ и оплата с карты: карта вида подставляется в новые записи, а в карточке оплаты видно, куда пойдут деньги
@MainActor
final class DebtCardAIActionTests: XCTestCase {
    private var service: FinanceService { FinanceService.shared }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private var savedCurrency: AppCurrency = .amd
    private var savedSettings: Data?

    // Вызов super.setUp() здесь не нужен (он пустой) и не компилируется в Swift 6 для MainActor-классов
    override func setUp() async throws {
        service.resetAllData()
        savedCurrency = CurrencyManager.shared.currentCurrency
        CurrencyManager.shared.currentCurrency = .amd
        savedSettings = UserDefaults.standard.data(forKey: DebtTypeSettings.storageKey)
        UserDefaults.standard.removeObject(forKey: DebtTypeSettings.storageKey)
    }

    override func tearDown() async throws {
        CurrencyManager.shared.currentCurrency = savedCurrency
        if let savedSettings {
            UserDefaults.standard.set(savedSettings, forKey: DebtTypeSettings.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: DebtTypeSettings.storageKey)
        }
        service.resetAllData()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private func now() throws -> Date {
        try date(2026, 10, 26, hour: 8)
    }

    private func plan(_ action: AIAction) throws -> PlannedAction {
        AIActionExecutor.plan(action, service: service, now: try now(), calendar: calendar)
    }

    private func addCard() -> Card {
        let card = Card(
            last4: "1234", holderName: "TEST", balance: 100_000, colorHex: "#2A2B30", gradientColors: ["#2A2B30", "#1C1D21"],
            balanceUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        service.addCard(card, number: "")
        return card
    }

    func testNewPaymentFromTheAssistantTakesTheCardOfItsKind() throws {
        let card = addCard()
        var settings = DebtTypeSettings()
        settings[.bill(.internet)].cardId = card.id
        settings.save()

        let planned = try plan(AIAction(kind: .addDebt, name: "Ucom", amount: 4_500, date: try date(2026, 11, 5), debtType: .bill, billKind: .internet))
        XCTAssertTrue(planned.canApply, planned.problem ?? "")
        AIActionExecutor.apply(planned, service: service)
        XCTAssertEqual(service.debts.first?.cardId, card.id)
    }

    func testCardThatNoLongerExistsIsNotUsedForNewDebts() throws {
        var settings = DebtTypeSettings()
        settings[.iOwe].cardId = UUID()
        settings.save()

        let planned = try plan(AIAction(kind: .addDebt, name: "Ани", amount: 5_000, date: try date(2026, 11, 5), direction: .iOwe, debtType: .person))
        AIActionExecutor.apply(planned, service: service)
        XCTAssertNil(service.debts.first?.cardId)
    }

    func testPaymentProposalNamesTheCardWhereTheMoneyGoes() throws {
        let card = addCard()
        let bill = Debt(name: "Ucom", amount: 4_500, dueDate: try date(2099, 6, 15), isLent: false, type: .bill, billKind: .internet, repeatRule: .monthly, cardId: card.id)
        service.addDebt(bill)

        let planned = try plan(AIAction(kind: .markDebtPaid, target: "Ucom"))
        XCTAssertTrue(planned.summary.contains("•••• 1234"), planned.summary)

        let withAmount = try plan(AIAction(kind: .markDebtPaid, target: "Ucom", amount: 5_000))
        XCTAssertTrue(withAmount.summary.contains("•••• 1234"), withAmount.summary)
    }

    func testProposalOfARepaymentToMeSaysIncome() throws {
        let card = addCard()
        let debt = Debt(name: "Арам", amount: 20_000, dueDate: try date(2026, 11, 5), isLent: true, cardId: card.id)
        service.addDebt(debt)
        let planned = try plan(AIAction(kind: .markDebtPaid, target: "Арам"))
        XCTAssertTrue(planned.summary.contains("•••• 1234"), planned.summary)
    }

    func testProposalWithoutACardSaysNothingAboutCards() throws {
        addCard()
        let bill = Debt(name: "Ucom", amount: 4_500, dueDate: try date(2099, 6, 15), isLent: false, type: .bill, billKind: .internet, repeatRule: .monthly)
        service.addDebt(bill)
        let planned = try plan(AIAction(kind: .markDebtPaid, target: "Ucom"))
        XCTAssertFalse(planned.summary.contains("••••"), planned.summary)
    }

    func testApprovedPaymentFromTheAssistantRecordsTheExpense() throws {
        let card = addCard()
        let bill = Debt(name: "Ucom", amount: 4_500, dueDate: try date(2099, 6, 15), isLent: false, type: .bill, billKind: .internet, repeatRule: .monthly, firstDueDate: try date(2099, 6, 15), cardId: card.id)
        service.addDebt(bill)
        let planned = try plan(AIAction(kind: .markDebtPaid, target: "Ucom"))
        XCTAssertEqual(AIActionExecutor.apply(planned, service: service), .done)

        XCTAssertEqual(service.transactions.count, 1)
        XCTAssertEqual(service.transactions.first?.amount ?? 0, 4_500, accuracy: 0.001)
        XCTAssertEqual(service.cards.first?.balance ?? 0, 95_500, accuracy: 0.001)
    }
}

@MainActor
final class DebtTypeCardSettingTests: XCTestCase {
    func testCardOfAKindSurvivesSavingAndOldDataHasNone() throws {
        let card = UUID()
        var settings = DebtTypeSettings()
        settings[.credit].cardId = card
        let data = try JSONEncoder().encode(settings)
        let restored = try JSONDecoder().decode(DebtTypeSettings.self, from: data)
        XCTAssertEqual(restored[.credit].cardId, card)
        XCTAssertNil(restored[.iOwe].cardId)

        let old = try JSONDecoder().decode(DebtTypeSetting.self, from: Data(#"{"minutes":540}"#.utf8))
        XCTAssertNil(old.cardId)
        XCTAssertEqual(old.minutes, 540)
    }

    func testAKindWithOnlyACardCountsAsChanged() {
        var settings = DebtTypeSettings()
        XCTAssertFalse(settings.isCustomized(.owedToMe))
        settings[.owedToMe].cardId = UUID()
        XCTAssertTrue(settings.isCustomized(.owedToMe))
        settings.reset(.owedToMe)
        XCTAssertNil(settings[.owedToMe].cardId)
    }
}
