import XCTest
@testable import SamFinance

/// Оплата долгов по частям, платежи с меняющейся суммой и с периодом «каждые N», кредиты с графиком платежей
@MainActor
final class DebtPaymentTests: XCTestCase {
    private var service: FinanceService { FinanceService.shared }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    // Вызов super.setUp() здесь не нужен (он пустой) и не компилируется в Swift 6 для MainActor-классов
    override func setUp() async throws {
        service.resetAllData()
    }

    override func tearDown() async throws {
        service.resetAllData()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private func now() throws -> Date {
        try date(2026, 10, 26, hour: 8)
    }

    private func credit(amount: Double = 120_000, payment: Double? = 10_000, rate: Double? = 12, left: Int? = 12) throws -> Debt {
        let due = try date(2026, 11, 5)
        return Debt(name: "IDBank", amount: amount, dueDate: due, isLent: false, type: .credit, firstDueDate: due, monthlyPayment: payment, interestRate: rate, paymentsLeft: left)
    }

    private func person(amount: Double = 20_000) throws -> Debt {
        Debt(name: "Арам", amount: amount, dueDate: try date(2026, 11, 5), isLent: true)
    }

    private func bill(amount: Double = 4_500, variable: Bool? = nil, rule: ReminderRepeat? = .monthly, interval: Int? = nil) throws -> Debt {
        let due = try date(2026, 11, 5)
        return Debt(name: "Коммуналка", amount: amount, dueDate: due, isLent: false, type: .bill, billKind: .utilities, repeatRule: rule, firstDueDate: due, repeatInterval: interval, isVariableAmount: variable)
    }

    // MARK: - Кредит с графиком

    func testCreditPaymentLowersTheBalanceByThePartWithoutInterest() throws {
        var debt = try credit()
        debt.applyPayment(now: try now(), calendar: calendar)

        // 120 000 под 12% годовых: проценты за месяц 1 200, остальное с платежа 10 000 гасит долг
        XCTAssertEqual(debt.amount, 111_200, accuracy: 0.001)
        XCTAssertEqual(debt.originalAmount ?? 0, 120_000, accuracy: 0.001)
        XCTAssertEqual(debt.paymentsLeft, 11)
        XCTAssertEqual(debt.lastPaidAmount ?? 0, 10_000, accuracy: 0.001)
        XCTAssertEqual(debt.lastPaidAt, try now())
        XCTAssertEqual(debt.dueDate, try date(2026, 12, 5), "срок перешёл на следующий месяц")
        XCTAssertFalse(debt.isPaid)
        XCTAssertTrue(debt.hasPartialPayments)
    }

    func testCreditWithoutARateGoesDownByTheWholePayment() throws {
        var debt = try credit(rate: nil)
        debt.applyPayment(now: try now(), calendar: calendar)
        XCTAssertEqual(debt.amount, 110_000, accuracy: 0.001)

        debt.applyPayment(25_000, now: try now(), calendar: calendar)
        XCTAssertEqual(debt.amount, 85_000, accuracy: 0.001, "можно внести сумму не равную платежу")
    }

    func testCreditIsClosedByTheLastPayment() throws {
        var debt = try credit(amount: 5_000, rate: nil, left: 3)
        debt.applyPayment(now: try now(), calendar: calendar)
        XCTAssertTrue(debt.isPaid)
        XCTAssertEqual(debt.dueDate, try date(2026, 11, 5), "закрытый кредит срок не переносит")
    }

    func testCreditIsClosedWhenNoPaymentsAreLeft() throws {
        var debt = try credit(amount: 50_000, rate: nil, left: 1)
        debt.applyPayment(now: try now(), calendar: calendar)
        XCTAssertEqual(debt.paymentsLeft, 0)
        XCTAssertTrue(debt.isPaid)
    }

    func testPaymentSmallerThanTheInterestDoesNotLowerTheBalance() throws {
        var debt = try credit(amount: 1_200_000, payment: 1_000, rate: 12, left: nil)
        debt.applyPayment(now: try now(), calendar: calendar)
        XCTAssertEqual(debt.amount, 1_200_000, accuracy: 0.001)
        XCTAssertFalse(debt.isPaid)
        XCTAssertNil(debt.paymentsLeft)
    }

    func testCreditWithoutAScheduleHasNoNextDate() throws {
        let plain = try credit(payment: nil)
        XCTAssertFalse(plain.hasPaymentPlan)
        XCTAssertFalse(plain.isRecurring)
        XCTAssertNil(plain.nextDueDate(now: try now(), calendar: calendar))

        let planned = try credit()
        XCTAssertTrue(planned.hasPaymentPlan)
        XCTAssertEqual(planned.nextDueDate(now: try now(), calendar: calendar), try date(2026, 12, 5))
        XCTAssertEqual(planned.effectiveRepeat, .monthly)
    }

    func testExtraPaymentOnACreditKeepsTheDueDate() throws {
        let debt = try credit()
        service.addDebt(debt)

        let repaid = try XCTUnwrap(service.repayDebt(id: debt.id, amount: 30_000, now: try now()))
        XCTAssertEqual(repaid.amount, 90_000, accuracy: 0.001)
        XCTAssertEqual(repaid.dueDate, try date(2026, 11, 5), "досрочный взнос срок не двигает")
        XCTAssertEqual(repaid.paymentsLeft, 12)
        XCTAssertFalse(repaid.isPaid)
    }

    // MARK: - Оплата по частям

    func testPersonDebtCanBePaidInParts() throws {
        var debt = try person()
        debt.applyPayment(5_000, now: try now(), calendar: calendar)
        XCTAssertEqual(debt.amount, 15_000, accuracy: 0.001)
        XCTAssertEqual(debt.originalAmount ?? 0, 20_000, accuracy: 0.001)
        XCTAssertEqual(debt.lastPaidAmount ?? 0, 5_000, accuracy: 0.001)
        XCTAssertFalse(debt.isPaid)
        XCTAssertTrue(debt.hasPartialPayments)
        XCTAssertEqual(debt.dueDate, try date(2026, 11, 5))

        debt.applyPayment(5_000, now: try now(), calendar: calendar)
        XCTAssertEqual(debt.amount, 10_000, accuracy: 0.001)
        XCTAssertEqual(debt.originalAmount ?? 0, 20_000, accuracy: 0.001, "исходная сумма запоминается один раз")

        debt.applyPayment(10_000, now: try now(), calendar: calendar)
        XCTAssertTrue(debt.isPaid)
    }

    func testPayingMoreThanOwedClosesTheDebt() throws {
        var debt = try person()
        debt.applyPayment(30_000, now: try now(), calendar: calendar)
        XCTAssertTrue(debt.isPaid)
        XCTAssertEqual(debt.lastPaidAmount ?? 0, 20_000, accuracy: 0.001, "засчитывается только то, что должны")
    }

    func testPaymentWithoutAnAmountClosesTheDebt() throws {
        var debt = try person()
        debt.applyPayment(now: try now(), calendar: calendar)
        XCTAssertTrue(debt.isPaid)
        XCTAssertFalse(debt.hasPartialPayments)
    }

    func testNonsensePaymentsChangeNothing() throws {
        for payment in [0, -500, Double.nan, Double.infinity * -1] {
            var debt = try person()
            let before = debt
            debt.applyPayment(payment, now: try now(), calendar: calendar)
            XCTAssertEqual(debt, before, "сумма \(payment)")
        }
        var debt = try person()
        let before = debt
        debt.applyRepayment(0)
        debt.applyRepayment(-5)
        XCTAssertEqual(debt, before)
    }

    func testPaymentInPartsThroughTheService() throws {
        let debt = try person()
        service.addDebt(debt)

        let partly = try XCTUnwrap(service.payDebt(id: debt.id, amount: 8_000, now: try now(), calendar: calendar))
        XCTAssertFalse(partly.isPaid)
        XCTAssertEqual(service.debts.first?.amount ?? 0, 12_000, accuracy: 0.001)

        XCTAssertNil(service.repayDebt(id: debt.id, amount: 0))
        XCTAssertNil(service.repayDebt(id: UUID(), amount: 100))
        let closed = try XCTUnwrap(service.repayDebt(id: debt.id, amount: 12_000, now: try now()))
        XCTAssertTrue(closed.isPaid)
    }

    func testRaisingTheAmountOnEditForgetsEarlierParts() throws {
        let debt = try person()
        service.addDebt(debt)
        service.payDebt(id: debt.id, amount: 5_000, now: try now(), calendar: calendar)

        var edited = try XCTUnwrap(service.debts.first)
        edited.name = "Арам Б."
        service.updateDebt(edited)
        XCTAssertNotNil(service.debts.first?.originalAmount, "правка имени прогресс не сбрасывает")

        edited.amount = 25_000
        service.updateDebt(edited)
        XCTAssertNil(service.debts.first?.originalAmount)
        XCTAssertEqual(service.debts.first?.lastPaidAmount ?? 0, 5_000, accuracy: 0.001)
    }

    // MARK: - Платежи с меняющейся суммой

    func testVariableBillRemembersWhatItCostThisTime() throws {
        var bill = try bill(variable: true)
        bill.applyPayment(5_200, now: try now(), calendar: calendar)

        XCTAssertEqual(bill.amount, 5_200, accuracy: 0.001, "в следующий раз ждём столько же")
        XCTAssertEqual(bill.lastPaidAmount ?? 0, 5_200, accuracy: 0.001)
        XCTAssertEqual(bill.dueDate, try date(2026, 12, 5))
        XCTAssertFalse(bill.isPaid)
        XCTAssertNil(bill.originalAmount, "для платежа с переменной суммой «часть» не считается")
    }

    func testFixedBillKeepsItsAmount() throws {
        var bill = try bill(variable: nil)
        bill.applyPayment(3_000, now: try now(), calendar: calendar)
        XCTAssertEqual(bill.amount, 4_500, accuracy: 0.001)
        XCTAssertEqual(bill.lastPaidAmount ?? 0, 3_000, accuracy: 0.001)

        var other = try bill(variable: nil)
        other.applyPayment(now: try now(), calendar: calendar)
        XCTAssertEqual(other.lastPaidAmount ?? 0, 4_500, accuracy: 0.001)
    }

    func testWhichRecordsAskForTheAmountBeforePaying() throws {
        XCTAssertTrue(try bill(variable: true).asksAmountBeforePaying)
        XCTAssertFalse(try bill(variable: nil).asksAmountBeforePaying)
        XCTAssertFalse(try bill(variable: true, rule: .never).asksAmountBeforePaying, "у разового платежа сумма известна")
        XCTAssertTrue(try credit().asksAmountBeforePaying)
        XCTAssertFalse(try credit(payment: nil).asksAmountBeforePaying)
        XCTAssertFalse(try person().asksAmountBeforePaying)

        var paid = try bill(variable: true)
        paid.isPaid = true
        XCTAssertFalse(paid.asksAmountBeforePaying)
    }

    // MARK: - Период «каждые N»

    func testEveryThreeMonthsMovesTheDueDateByAQuarter() throws {
        let quarterly = try bill(interval: 3)
        XCTAssertEqual(quarterly.effectiveInterval, 3)
        XCTAssertEqual(quarterly.nextDueDate(now: try now(), calendar: calendar), try date(2027, 2, 5))

        var paid = quarterly
        paid.applyPayment(now: try now(), calendar: calendar)
        XCTAssertEqual(paid.dueDate, try date(2027, 2, 5))
        paid.applyPayment(now: try date(2027, 2, 1), calendar: calendar)
        XCTAssertEqual(paid.dueDate, try date(2027, 5, 5))
    }

    func testEveryTwoYearsAndEveryTwoWeeks() throws {
        XCTAssertEqual(try bill(rule: .yearly, interval: 2).nextDueDate(now: try now(), calendar: calendar), try date(2028, 11, 5))
        XCTAssertEqual(try bill(rule: .weekly, interval: 2).nextDueDate(now: try now(), calendar: calendar), try date(2026, 11, 19))
    }

    func testNonsenseIntervalCountsAsOne() throws {
        XCTAssertEqual(try bill(interval: 0).effectiveInterval, 1)
        XCTAssertEqual(try bill(interval: -4).effectiveInterval, 1)
        XCTAssertEqual(try bill(interval: nil).effectiveInterval, 1)
        XCTAssertEqual(try bill(interval: 1).nextDueDate(now: try now(), calendar: calendar), try date(2026, 12, 5))
    }

    func testRepeatTitleNamesThePeriod() {
        for rule in ReminderRepeat.allCases {
            XCTAssertEqual(rule.title(every: 1), rule.title)
            XCTAssertEqual(rule.title(every: 0), rule.title)
        }
        for rule in [ReminderRepeat.daily, .weekly, .monthly, .yearly] {
            XCTAssertTrue(rule.title(every: 3).contains("3"), rule.rawValue)
            XCTAssertNotEqual(rule.title(every: 3), rule.title, rule.rawValue)
        }
        XCTAssertEqual(ReminderRepeat.never.title(every: 5), ReminderRepeat.never.title)
    }

    // MARK: - Хранение

    func testNewFieldsSurviveSavingToDisk() throws {
        let debt = Debt(
            name: "IDBank", amount: 90_000, dueDate: try date(2026, 11, 5), isLent: false, type: .credit,
            firstDueDate: try date(2026, 10, 5), lastPaidAt: try now(), note: "договор 4411",
            repeatInterval: 2, isVariableAmount: true, lastPaidAmount: 10_000, originalAmount: 120_000,
            monthlyPayment: 10_000, interestRate: 12.5, paymentsLeft: 9
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(Debt.self, from: encoder.encode(debt))
        XCTAssertEqual(restored, debt)
        XCTAssertEqual(restored.note, "договор 4411")
        XCTAssertEqual(restored.paymentsLeft, 9)
    }

    func testOldSavedDebtsStillOpen() throws {
        let json = #"{"id":"\#(UUID().uuidString)","name":"Арам","amount":1000,"dueDate":"2026-11-05T00:00:00Z","isLent":true,"isPaid":false,"type":"person"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let debt = try decoder.decode(Debt.self, from: Data(json.utf8))
        XCTAssertEqual(debt.name, "Арам")
        XCTAssertNil(debt.note)
        XCTAssertNil(debt.monthlyPayment)
        XCTAssertNil(debt.originalAmount)
        XCTAssertFalse(debt.hasPartialPayments)
        XCTAssertFalse(debt.hasPaymentPlan)
    }
}
