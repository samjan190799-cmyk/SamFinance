import XCTest
@testable import SamFinance

/// ИИ и новые условия долгов: настройки видов, график кредита, период «каждые N», оплата с суммой
@MainActor
final class DebtTypeAIActionTests: XCTestCase {
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

    @discardableResult
    private func applied(_ action: AIAction, file: StaticString = #filePath, line: UInt = #line) throws -> PlannedAction {
        let planned = try plan(action)
        XCTAssertTrue(planned.canApply, planned.problem ?? "", file: file, line: line)
        XCTAssertEqual(AIActionExecutor.apply(planned, service: service), .done, file: file, line: line)
        return planned
    }

    // MARK: - Настройки видов

    func testNewBillTakesTheDefaultsOfItsKind() throws {
        try applied(AIAction(kind: .addDebt, name: "Свет и вода", amount: 18_000, date: try date(2026, 11, 10), debtType: .bill, billKind: .utilities))
        let bill = try XCTUnwrap(service.debts.first)
        XCTAssertEqual(bill.repeatRule, .monthly)
        XCTAssertEqual(bill.isVariableAmount, true, "коммуналка по умолчанию с переменной суммой")
        XCTAssertEqual(bill.reminder, .standard)
        XCTAssertNil(bill.repeatInterval)
    }

    func testNewBillFollowsTheUsersSettingsForItsKind() throws {
        var settings = DebtTypeSettings()
        settings[.bill(.insurance)] = DebtTypeSetting(reminder: .weekBefore, repeatRule: .yearly)
        settings[.bill(.subscription)] = DebtTypeSetting(isEnabled: false)
        settings.save()

        try applied(AIAction(kind: .addDebt, name: "КАСКО", amount: 90_000, date: try date(2027, 3, 1), debtType: .bill, billKind: .insurance))
        let insurance = try XCTUnwrap(service.debts.first)
        XCTAssertEqual(insurance.repeatRule, .yearly)
        XCTAssertEqual(insurance.reminder, .weekBefore)

        try applied(AIAction(kind: .addDebt, name: "Netflix", amount: 4_000, date: try date(2026, 11, 12), debtType: .bill, billKind: .subscription))
        let subscription = try XCTUnwrap(service.debts.first { $0.name == "Netflix" })
        XCTAssertEqual(subscription.reminder, DebtReminder.off, "вид выключен — новая запись без напоминания")
    }

    func testWhatTheUserSaidBeatsTheKindSettings() throws {
        var settings = DebtTypeSettings()
        settings[.bill(.internet)] = DebtTypeSetting(reminder: .weekBefore, repeatRule: .yearly, isVariableAmount: true)
        settings.save()

        try applied(AIAction(
            kind: .addDebt, name: "Ucom", amount: 4_500, date: try date(2026, 11, 5),
            debtType: .bill, billKind: .internet, reminder: .onDueDay, repeatRule: .monthly, variableAmount: false
        ))
        let bill = try XCTUnwrap(service.debts.first)
        XCTAssertEqual(bill.reminder, .onDueDay)
        XCTAssertEqual(bill.repeatRule, .monthly)
        XCTAssertNil(bill.isVariableAmount)
    }

    func testOneTimeBillUsesTheOneTimeSettings() throws {
        var settings = DebtTypeSettings()
        settings[.oneTimeBill].reminder = .threeDaysBefore
        settings[.bill(.tax)].reminder = .weekBefore
        settings.save()

        try applied(AIAction(kind: .addDebt, name: "Штраф", amount: 15_000, date: try date(2026, 11, 20), debtType: .bill, billKind: .tax, repeatRule: ReminderRepeat.never))
        let fine = try XCTUnwrap(service.debts.first)
        XCTAssertEqual(fine.reminder, .threeDaysBefore)
        XCTAssertNil(fine.isVariableAmount, "у разового платежа сумма известна")
    }

    func testPersonDebtTakesTheReminderOfItsDirection() throws {
        var settings = DebtTypeSettings()
        settings[.owedToMe].reminder = .threeDaysBefore
        settings.save()

        try applied(AIAction(kind: .addDebt, name: "Арам", amount: 20_000, date: try date(2026, 11, 5), direction: .owedToMe, debtType: .person))
        try applied(AIAction(kind: .addDebt, name: "Ани", amount: 5_000, date: try date(2026, 11, 6), direction: .iOwe, debtType: .person))
        XCTAssertEqual(service.debts.first { $0.name == "Арам" }?.reminder, .threeDaysBefore)
        XCTAssertEqual(service.debts.first { $0.name == "Ани" }?.reminder, .standard)
    }

    // MARK: - Платежи: период и заметка

    func testEveryThreeMonthsAndNoteAreSaved() throws {
        let planned = try applied(AIAction(
            kind: .addDebt, name: "Страховка квартиры", amount: 30_000, date: try date(2026, 12, 1),
            debtType: .bill, billKind: .insurance, repeatRule: .monthly, note: "полис 77-12", interval: 3
        ))
        let bill = try XCTUnwrap(service.debts.first)
        XCTAssertEqual(bill.repeatInterval, 3)
        XCTAssertEqual(bill.effectiveInterval, 3)
        XCTAssertEqual(bill.note, "полис 77-12")
        XCTAssertTrue(planned.summary.contains(ReminderRepeat.monthly.title(every: 3).lowercased()), planned.summary)
    }

    func testChangingBillPeriodNoteAndAmountVariability() throws {
        let bill = Debt(name: "Ucom", amount: 4_500, dueDate: try date(2026, 11, 5), isLent: false, type: .bill, billKind: .internet, repeatRule: .monthly, firstDueDate: try date(2026, 11, 5))
        service.addDebt(bill)

        let planned = try applied(AIAction(kind: .changeDebt, target: "Ucom", note: "лицевой счёт 5521", interval: 2, variableAmount: true))
        let updated = try XCTUnwrap(service.debts.first)
        XCTAssertEqual(updated.repeatInterval, 2)
        XCTAssertEqual(updated.isVariableAmount, true)
        XCTAssertEqual(updated.note, "лицевой счёт 5521")
        XCTAssertEqual(updated.repeatRule, .monthly)
        XCTAssertFalse(planned.summary.isEmpty)

        // Платёж стал разовым: период и признак «сумма меняется» уходят вместе с повтором
        try applied(AIAction(kind: .changeDebt, target: "Ucom", repeatRule: ReminderRepeat.never))
        let oneTime = try XCTUnwrap(service.debts.first)
        XCTAssertNil(oneTime.repeatInterval)
        XCTAssertNil(oneTime.isVariableAmount)
    }

    func testNothingToChangeIsReportedForANoteOnlyWhenItIsGiven() throws {
        let debt = Debt(name: "Арам", amount: 1_000, dueDate: try date(2026, 11, 5), isLent: true)
        service.addDebt(debt)
        let planned = try plan(AIAction(kind: .changeDebt, target: "Арам"))
        XCTAssertFalse(planned.canApply)
        XCTAssertTrue(try plan(AIAction(kind: .changeDebt, target: "Арам", note: "вернёт с зарплаты")).canApply)
    }

    // MARK: - Кредит с графиком

    func testCreditWithAScheduleIsAdded() throws {
        let due = try date(2026, 11, 20)
        try applied(AIAction(
            kind: .addDebt, name: "IDBank", amount: 1_200_000, date: due, debtType: .credit,
            monthlyPayment: 60_000, interestRate: 14.5, paymentsLeft: 24
        ))
        let credit = try XCTUnwrap(service.debts.first)
        XCTAssertEqual(credit.type, .credit)
        XCTAssertTrue(credit.hasPaymentPlan)
        XCTAssertEqual(credit.monthlyPayment ?? 0, 60_000, accuracy: 0.001)
        XCTAssertEqual(credit.interestRate ?? 0, 14.5, accuracy: 0.001)
        XCTAssertEqual(credit.paymentsLeft, 24)
        XCTAssertTrue(calendar.isDate(try XCTUnwrap(credit.firstDueDate), inSameDayAs: due), "от платежного дня считаются следующие сроки")
    }

    func testPaymentsLeftWithoutAPaymentAreIgnored() throws {
        try applied(AIAction(kind: .addDebt, name: "IDBank", amount: 500_000, date: try date(2026, 11, 20), debtType: .credit, interestRate: 12, paymentsLeft: 10))
        let credit = try XCTUnwrap(service.debts.first)
        XCTAssertFalse(credit.hasPaymentPlan)
        XCTAssertNil(credit.paymentsLeft)
        XCTAssertNil(credit.firstDueDate)
        XCTAssertEqual(credit.interestRate ?? 0, 12, accuracy: 0.001)
    }

    func testLoanTermsAreIgnoredForPeopleAndBills() throws {
        try applied(AIAction(kind: .addDebt, name: "Арам", amount: 20_000, date: try date(2026, 11, 5), direction: .owedToMe, debtType: .person, monthlyPayment: 5_000, interestRate: 10, paymentsLeft: 4))
        let person = try XCTUnwrap(service.debts.first)
        XCTAssertNil(person.monthlyPayment)
        XCTAssertNil(person.interestRate)
        XCTAssertNil(person.paymentsLeft)
    }

    func testChangingCreditTerms() throws {
        let credit = Debt(name: "IDBank", amount: 500_000, dueDate: try date(2026, 11, 20), isLent: false, type: .credit)
        service.addDebt(credit)

        try applied(AIAction(kind: .changeDebt, target: "IDBank", monthlyPayment: 30_000, interestRate: 9.5, paymentsLeft: 18))
        let updated = try XCTUnwrap(service.debts.first)
        XCTAssertTrue(updated.hasPaymentPlan)
        XCTAssertEqual(updated.monthlyPayment ?? 0, 30_000, accuracy: 0.001)
        XCTAssertEqual(updated.interestRate ?? 0, 9.5, accuracy: 0.001)
        XCTAssertEqual(updated.paymentsLeft, 18)
        XCTAssertNotNil(updated.firstDueDate, "после появления графика есть точка отсчёта сроков")

        // Ставка 0 убирает проценты
        try applied(AIAction(kind: .changeDebt, target: "IDBank", interestRate: 0))
        XCTAssertNil(service.debts.first?.interestRate)
    }

    func testWrongLoanTermsAreRefused() throws {
        let credit = Debt(name: "IDBank", amount: 500_000, dueDate: try date(2026, 11, 20), isLent: false, type: .credit)
        service.addDebt(credit)
        XCTAssertFalse(try plan(AIAction(kind: .changeDebt, target: "IDBank", monthlyPayment: -5)).canApply)
        XCTAssertFalse(try plan(AIAction(kind: .changeDebt, target: "IDBank", interestRate: 5_000)).canApply, "ставка выше 1000% — ошибка модели")
        XCTAssertFalse(try plan(AIAction(kind: .changeDebt, target: "IDBank", paymentsLeft: -1)).canApply)
    }

    // MARK: - Оплата с суммой

    /// Предложение — оплата с суммой (сумма может отличаться от названной на копейки после пересчёта валют)
    private func assertPayment(_ planned: PlannedAction, of id: UUID, amount: Double, file: StaticString = #filePath, line: UInt = #line) throws {
        guard case .payDebt(let target, let value)? = planned.operation else {
            return XCTFail("ожидалась оплата с суммой, а не \(String(describing: planned.operation))", file: file, line: line)
        }
        XCTAssertEqual(target, id, file: file, line: line)
        XCTAssertEqual(try XCTUnwrap(value, file: file, line: line), amount, accuracy: 0.001, file: file, line: line)
    }

    func testPartOfAPersonDebtIsPaid() throws {
        let debt = Debt(name: "Арам", amount: 20_000, dueDate: try date(2026, 11, 5), isLent: true)
        service.addDebt(debt)

        let planned = try applied(AIAction(kind: .markDebtPaid, target: "Арам", amount: 8_000))
        try assertPayment(planned, of: debt.id, amount: 8_000)
        let rest = try XCTUnwrap(service.debts.first)
        XCTAssertEqual(rest.amount, 12_000, accuracy: 0.001)
        XCTAssertFalse(rest.isPaid)
    }

    func testPayingTheWholeAmountClosesTheDebtTheUsualWay() throws {
        let debt = Debt(name: "Арам", amount: 20_000, dueDate: try date(2026, 11, 5), isLent: true)
        service.addDebt(debt)
        let planned = try applied(AIAction(kind: .markDebtPaid, target: "Арам", amount: 20_000))
        XCTAssertEqual(planned.operation, .setDebtPaid(debt.id, true))
        XCTAssertEqual(service.debts.first?.isPaid, true)
    }

    func testCreditPaymentLowersTheBalanceThroughTheAssistant() throws {
        let due = try date(2026, 11, 5)
        let credit = Debt(name: "IDBank", amount: 120_000, dueDate: due, isLent: false, type: .credit, firstDueDate: due, monthlyPayment: 10_000, interestRate: 12, paymentsLeft: 12)
        service.addDebt(credit)

        let planned = try applied(AIAction(kind: .markDebtPaid, target: "IDBank"))
        XCTAssertEqual(planned.operation, .payDebt(credit.id, nil))
        let paid = try XCTUnwrap(service.debts.first)
        XCTAssertEqual(paid.amount, 111_200, accuracy: 0.001)
        XCTAssertEqual(paid.paymentsLeft, 11)
        XCTAssertFalse(paid.isPaid)
        XCTAssertGreaterThan(paid.dueDate, due)
    }

    func testVariableBillTakesTheAmountTheUserNamed() throws {
        let bill = Debt(name: "Коммуналка", amount: 18_000, dueDate: try date(2099, 6, 15), isLent: false, type: .bill, billKind: .utilities, repeatRule: .monthly, firstDueDate: try date(2099, 6, 15), isVariableAmount: true)
        service.addDebt(bill)

        let planned = try applied(AIAction(kind: .markDebtPaid, target: "Коммуналка", amount: 21_300))
        try assertPayment(planned, of: bill.id, amount: 21_300)
        let paid = try XCTUnwrap(service.debts.first)
        XCTAssertEqual(paid.amount, 21_300, accuracy: 0.001)
        XCTAssertEqual(paid.lastPaidAmount ?? 0, 21_300, accuracy: 0.001)
        XCTAssertFalse(paid.isPaid)
    }

    func testWrongPaymentAmountIsRefused() throws {
        let debt = Debt(name: "Арам", amount: 20_000, dueDate: try date(2026, 11, 5), isLent: true)
        service.addDebt(debt)
        XCTAssertFalse(try plan(AIAction(kind: .markDebtPaid, target: "Арам", amount: -100)).canApply)
        XCTAssertFalse(try plan(AIAction(kind: .markDebtPaid, target: "Арам", amount: 0)).canApply)
    }

    func testAlreadyPaidDebtCannotBePaidAgainWithAnAmount() throws {
        var debt = Debt(name: "Арам", amount: 20_000, dueDate: try date(2026, 11, 5), isLent: true)
        debt.isPaid = true
        service.addDebt(debt)
        XCTAssertFalse(try plan(AIAction(kind: .markDebtPaid, target: "Арам", amount: 5_000)).canApply)
    }

    func testPaymentIsCheckedAgainBeforeItIsApplied() throws {
        let debt = Debt(name: "Арам", amount: 20_000, dueDate: try date(2026, 11, 5), isLent: true)
        service.addDebt(debt)
        let planned = try plan(AIAction(kind: .markDebtPaid, target: "Арам", amount: 5_000))
        XCTAssertTrue(planned.canApply)

        service.setDebtPaid(id: debt.id, isPaid: true)
        guard case .failed = AIActionExecutor.apply(planned, service: service) else {
            return XCTFail("закрытый долг не должен принимать взнос")
        }
    }
}

/// Ответ облачного ИИ с новыми полями
@MainActor
final class CloudDebtTermsParsingTests: XCTestCase {
    private func action(_ fields: String) throws -> AIAction {
        let json = #"{"reply":"ок","operations":[],"actions":[{"kind":"add_debt",\#(fields)}]}"#
        return try XCTUnwrap(CloudFinanceAssistant.parse(json, provider: .claude).actions.first)
    }

    func testNewFieldsAreParsed() throws {
        let parsed = try action(#""name":"IDBank","debt_type":"credit","monthly_payment":60000,"interest_rate":14.5,"payments_left":24,"interval":3,"variable_amount":true,"note":"договор 4411""#)
        XCTAssertEqual(parsed.monthlyPayment, 60_000)
        XCTAssertEqual(parsed.interestRate, 14.5)
        XCTAssertEqual(parsed.paymentsLeft, 24)
        XCTAssertEqual(parsed.interval, 3)
        XCTAssertEqual(parsed.variableAmount, true)
        XCTAssertEqual(parsed.note, "договор 4411")
    }

    func testMissingFieldsStayEmpty() throws {
        let parsed = try action(#""name":"Арам""#)
        XCTAssertNil(parsed.monthlyPayment)
        XCTAssertNil(parsed.interestRate)
        XCTAssertNil(parsed.paymentsLeft)
        XCTAssertNil(parsed.interval)
        XCTAssertNil(parsed.variableAmount)
    }

    func testWholeNumbersMayArriveAsDecimals() throws {
        let parsed = try action(#""payments_left":11.0,"interval":2.4"#)
        XCTAssertEqual(parsed.paymentsLeft, 11)
        XCTAssertEqual(parsed.interval, 2, "дробное «каждые 2,4» не ломает ответ")
    }

    func testAbsurdNumbersAreDropped() throws {
        let parsed = try action(#""payments_left":9999999,"interval":1e30"#)
        XCTAssertNil(parsed.paymentsLeft)
        XCTAssertNil(parsed.interval)
    }

    func testSchemaListsTheNewFields() throws {
        let schema = CloudFinanceAssistant.responseSchema()
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let actions = try XCTUnwrap(properties["actions"] as? [String: Any])
        let item = try XCTUnwrap(actions["items"] as? [String: Any])
        let itemProperties = try XCTUnwrap(item["properties"] as? [String: Any])
        for key in ["interval", "variable_amount", "monthly_payment", "interest_rate", "payments_left"] {
            XCTAssertNotNil(itemProperties[key], key)
        }
        XCTAssertEqual(Set(item["required"] as? [String] ?? []), Set(itemProperties.keys))
        XCTAssertTrue(JSONSerialization.isValidJSONObject(GeminiAPI.geminiSchema(schema)))
    }
}
