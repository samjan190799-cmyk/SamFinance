import XCTest
@testable import SamFinance

/// Платежи (коммуналка, интернет, подписки): следующий срок, оплата, напоминания, действия ИИ
@MainActor
final class BillTests: XCTestCase {
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

    private func makeBill(
        due: Date,
        rule: ReminderRepeat? = .monthly,
        first: Date? = nil,
        name: String = "Интернет",
        kind: BillKind = .internet,
        amount: Double = 4_500
    ) -> Debt {
        Debt(name: name, amount: amount, dueDate: due, isLent: false, type: .bill, billKind: kind, repeatRule: rule, firstDueDate: first ?? due)
    }

    // MARK: - Следующий срок

    func testMonthlyBillMovesToTheNextMonth() throws {
        let bill = makeBill(due: try date(2026, 11, 5))
        XCTAssertEqual(bill.nextDueDate(now: try now(), calendar: calendar), try date(2026, 12, 5))
    }

    func testDueDateDoesNotDriftAfterAShortMonth() throws {
        // Платёж «31-го числа»: в феврале срок 28-е, но в марте снова 31-е, а не 28-е
        let bill = makeBill(due: try date(2026, 2, 28), first: try date(2026, 1, 31))
        XCTAssertEqual(bill.nextDueDate(now: try date(2026, 2, 27), calendar: calendar), try date(2026, 3, 31))
    }

    func testOverdueBillSkipsToTheNextDateThatIsNotInThePast() throws {
        let bill = makeBill(due: try date(2026, 8, 5))
        XCTAssertEqual(bill.nextDueDate(now: try now(), calendar: calendar), try date(2026, 11, 5))
    }

    func testWeeklyAndYearlyBills() throws {
        let weekly = makeBill(due: try date(2026, 10, 26), rule: .weekly)
        XCTAssertEqual(weekly.nextDueDate(now: try now(), calendar: calendar), try date(2026, 11, 2))

        let yearly = makeBill(due: try date(2026, 12, 1), rule: .yearly)
        XCTAssertEqual(yearly.nextDueDate(now: try now(), calendar: calendar), try date(2027, 12, 1))
    }

    func testOneTimeBillsAndDebtsHaveNoNextDate() throws {
        XCTAssertNil(makeBill(due: try date(2026, 11, 5), rule: .never).nextDueDate(now: try now(), calendar: calendar))
        XCTAssertNil(makeBill(due: try date(2026, 11, 5), rule: nil).nextDueDate(now: try now(), calendar: calendar))
        let person = Debt(name: "Арам", amount: 1_000, dueDate: try date(2026, 11, 5), isLent: true)
        XCTAssertNil(person.nextDueDate(now: try now(), calendar: calendar))
        XCTAssertFalse(person.isRecurringBill)
        XCTAssertTrue(makeBill(due: try date(2026, 11, 5)).isRecurringBill)
    }

    func testBillSurvivesSavingToDisk() throws {
        let bill = makeBill(due: try date(2026, 11, 5))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(Debt.self, from: encoder.encode(bill))
        XCTAssertEqual(restored, bill)
        XCTAssertEqual(restored.billKind, .internet)
        XCTAssertEqual(restored.repeatRule, .monthly)
    }

    func testEveryBillKindHasATitleAndAnIcon() {
        for kind in BillKind.allCases {
            XCTAssertFalse(kind.title.isEmpty, kind.rawValue)
            XCTAssertFalse(kind.icon.isEmpty, kind.rawValue)
        }
        XCTAssertEqual(Set(BillKind.allCases.map(\.title)).count, BillKind.allCases.count, "названия видов не повторяются")
    }

    // MARK: - Оплата

    func testPayingARecurringBillMovesTheDueDateAndKeepsItActive() throws {
        let bill = makeBill(due: try date(2026, 11, 5))
        service.addDebt(bill)

        let paid = try XCTUnwrap(service.payDebt(id: bill.id, now: try now(), calendar: calendar))
        XCTAssertFalse(paid.isPaid)
        XCTAssertEqual(paid.dueDate, try date(2026, 12, 5))
        XCTAssertEqual(paid.lastPaidAt, try now())
        XCTAssertEqual(paid.firstDueDate, try date(2026, 11, 5), "точка отсчёта не сдвигается")
        XCTAssertEqual(service.debts.first?.dueDate, try date(2026, 12, 5))
    }

    func testPayingAOneTimeBillClosesIt() throws {
        let bill = makeBill(due: try date(2026, 11, 5), rule: .never)
        service.addDebt(bill)
        let paid = try XCTUnwrap(service.payDebt(id: bill.id, now: try now(), calendar: calendar))
        XCTAssertTrue(paid.isPaid)
        XCTAssertEqual(paid.dueDate, try date(2026, 11, 5))
    }

    func testPayingAPersonDebtClosesIt() throws {
        let debt = Debt(name: "Арам", amount: 1_000, dueDate: try date(2026, 11, 5), isLent: true)
        service.addDebt(debt)
        service.payDebt(id: debt.id, now: try now(), calendar: calendar)
        XCTAssertEqual(service.debts.first?.isPaid, true)
        XCTAssertNil(service.payDebt(id: UUID()), "неизвестной записи нет")
    }

    func testSetDebtPaidRollsARecurringBillEachTime() throws {
        // Срок далеко в будущем: следующий срок не зависит от сегодняшней даты
        let bill = makeBill(due: try date(2099, 6, 15))
        service.addDebt(bill)

        service.setDebtPaid(id: bill.id, isPaid: true)
        XCTAssertEqual(service.debts.first?.isPaid, false)
        XCTAssertTrue(calendar.isDate(try XCTUnwrap(service.debts.first?.dueDate), inSameDayAs: try date(2099, 7, 15)))

        service.setDebtPaid(id: bill.id, isPaid: true)
        XCTAssertTrue(calendar.isDate(try XCTUnwrap(service.debts.first?.dueDate), inSameDayAs: try date(2099, 8, 15)))
    }

    func testTogglePayClosesAndReopensAPersonDebt() throws {
        let debt = Debt(name: "Арам", amount: 1_000, dueDate: try date(2026, 11, 5), isLent: false)
        service.addDebt(debt)
        service.togglePayDebt(id: debt.id)
        XCTAssertEqual(service.debts.first?.isPaid, true)
        service.togglePayDebt(id: debt.id)
        XCTAssertEqual(service.debts.first?.isPaid, false)
    }

    func testEditingABillKeepsTheLastPaymentDate() throws {
        let bill = makeBill(due: try date(2026, 11, 5))
        service.addDebt(bill)
        service.payDebt(id: bill.id, now: try now(), calendar: calendar)

        var edited = try XCTUnwrap(service.debts.first)
        edited.amount = 5_200
        edited.lastPaidAt = nil
        service.updateDebt(edited)

        XCTAssertEqual(service.debts.first?.amount ?? 0, 5_200, accuracy: 0.001)
        XCTAssertEqual(service.debts.first?.lastPaidAt, try now())
    }

    // MARK: - Напоминания

    func testBillRemindersHaveTheirOwnTitlesAndButtons() throws {
        let bill = makeBill(due: try date(2026, 11, 5))
        let specs = ReminderPlanner.debtSpecs(bill, snooze: nil, settings: ReminderSettings(), now: try now(), calendar: calendar)
        XCTAssertFalse(specs.isEmpty)
        XCTAssertTrue(specs.allSatisfy { $0.category == ReminderID.billCategory })
        XCTAssertEqual(specs.first?.title, String(localized: "Скоро срок платежа"))
        XCTAssertEqual(specs.map(\.target), Array(repeating: .debt(bill.id), count: specs.count))

        let person = Debt(name: "Арам", amount: 1_000, dueDate: try date(2026, 11, 5), isLent: false)
        let personSpecs = ReminderPlanner.debtSpecs(person, snooze: nil, settings: ReminderSettings(), now: try now(), calendar: calendar)
        XCTAssertTrue(personSpecs.allSatisfy { $0.category == ReminderID.debtCategory })
    }

    func testRemindersFollowTheNewDueDateAfterPayment() throws {
        let bill = makeBill(due: try date(2026, 10, 27))
        let before = ReminderPlanner.debtSpecs(bill, snooze: nil, settings: ReminderSettings(), now: try now(), calendar: calendar)
        XCTAssertEqual(before.compactMap(\.fireDate).first, try date(2026, 10, 26, hour: 10))

        var paid = bill
        paid.dueDate = try XCTUnwrap(bill.nextDueDate(now: try now(), calendar: calendar))
        let after = ReminderPlanner.debtSpecs(paid, snooze: nil, settings: ReminderSettings(), now: try now(), calendar: calendar)
        XCTAssertEqual(after.compactMap(\.fireDate).first, try date(2026, 11, 26, hour: 10))
    }

    // MARK: - Вопрос в чате без ключа

    func testLocalAnswerListsBillsSeparatelyFromDebts() throws {
        service.addDebt(Debt(name: "Арам", amount: 20_000, dueDate: try date(2099, 1, 5), isLent: true))
        service.addDebt(makeBill(due: try date(2099, 2, 5), name: "Ucom", amount: 4_500))

        let answer = LocalFinanceAssistant.answer("какие у меня долги и платежи?", financeService: service)
        XCTAssertTrue(answer.contains("Ucom"), answer)
        XCTAssertTrue(answer.contains(CurrencyManager.shared.format(20_000)), answer)

        service.resetAllData()
        service.addDebt(makeBill(due: try date(2099, 2, 5), name: "Ucom", amount: 4_500))
        let onlyBills = LocalFinanceAssistant.answer("какие у меня платежи?", financeService: service)
        XCTAssertTrue(onlyBills.contains("Ucom"), onlyBills)
    }
}

/// Платежи в предложениях ИИ
@MainActor
final class BillActionTests: XCTestCase {
    private var service: FinanceService { FinanceService.shared }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private var savedCurrency: AppCurrency = .amd

    override func setUp() async throws {
        service.resetAllData()
        savedCurrency = CurrencyManager.shared.currentCurrency
        CurrencyManager.shared.currentCurrency = .amd
    }

    override func tearDown() async throws {
        CurrencyManager.shared.currentCurrency = savedCurrency
        service.resetAllData()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    private func plan(_ action: AIAction) throws -> PlannedAction {
        AIActionExecutor.plan(action, service: service, now: try date(2026, 10, 26), calendar: calendar)
    }

    func testBillIsAddedWithMonthlyRepeatAndTheNameOfItsKind() throws {
        let planned = try plan(AIAction(kind: .addDebt, amount: 4_500, date: try date(2026, 11, 5), debtType: .bill, billKind: .internet))
        XCTAssertTrue(planned.canApply, planned.problem ?? "")
        XCTAssertEqual(planned.icon, BillKind.internet.icon)
        XCTAssertEqual(AIActionExecutor.apply(planned, service: service), .done)

        let bill = try XCTUnwrap(service.debts.first)
        XCTAssertEqual(bill.type, .bill)
        XCTAssertEqual(bill.name, BillKind.internet.title)
        XCTAssertEqual(bill.billKind, .internet)
        XCTAssertEqual(bill.repeatRule, .monthly)
        XCTAssertFalse(bill.isLent)
        XCTAssertTrue(calendar.isDate(bill.dueDate, inSameDayAs: try date(2026, 11, 5)))
        XCTAssertEqual(bill.firstDueDate, bill.dueDate)
        XCTAssertEqual(DebtTab(debt: bill), .bills)
    }

    func testBillHonorsNameKindAndOneTimeRepeat() throws {
        try AIActionExecutor.apply(plan(AIAction(kind: .addDebt, name: "Ucom", amount: 6_000, date: try date(2026, 11, 20), debtType: .bill, billKind: .internet, repeatRule: .never)), service: service)
        let bill = try XCTUnwrap(service.debts.first)
        XCTAssertEqual(bill.name, "Ucom")
        XCTAssertEqual(bill.repeatRule, ReminderRepeat.never)
        XCTAssertFalse(bill.isRecurringBill)
    }

    func testBillNeedsAnAmountAndADueDate() throws {
        XCTAssertNotNil(try plan(AIAction(kind: .addDebt, date: try date(2026, 11, 5), debtType: .bill, billKind: .utilities)).problem)
        XCTAssertNotNil(try plan(AIAction(kind: .addDebt, amount: 9_000, debtType: .bill, billKind: .utilities)).problem)
        XCTAssertTrue(service.debts.isEmpty)
    }

    func testSameBillIsNotAddedTwice() throws {
        let action = AIAction(kind: .addDebt, amount: 4_500, date: try date(2026, 11, 5), debtType: .bill, billKind: .internet)
        XCTAssertEqual(AIActionExecutor.apply(try plan(action), service: service), .done)
        XCTAssertFalse(try plan(action).canApply)
    }

    func testPayingABillThroughAIMovesItsDueDate() throws {
        let bill = Debt(name: "Интернет", amount: 4_500, dueDate: try date(2099, 6, 15), isLent: false, type: .bill, billKind: .internet, repeatRule: .monthly, firstDueDate: try date(2099, 6, 15))
        service.addDebt(bill)

        let planned = try plan(AIAction(kind: .markDebtPaid, target: "интернет"))
        XCTAssertTrue(planned.canApply, planned.problem ?? "")
        XCTAssertEqual(AIActionExecutor.apply(planned, service: service), .done)
        XCTAssertEqual(service.debts.first?.isPaid, false)
        XCTAssertTrue(calendar.isDate(try XCTUnwrap(service.debts.first?.dueDate), inSameDayAs: try date(2099, 7, 15)))

        XCTAssertFalse(try plan(AIAction(kind: .markDebtUnpaid, target: "интернет")).canApply, "срок уже перенесён, возвращать нечего")
    }

    func testOneTimeBillCannotBePaidTwice() throws {
        let bill = Debt(name: "Налог", amount: 20_000, dueDate: try date(2026, 12, 1), isLent: false, type: .bill, billKind: .tax, repeatRule: .never, firstDueDate: try date(2026, 12, 1))
        service.addDebt(bill)
        XCTAssertEqual(AIActionExecutor.apply(try plan(AIAction(kind: .markDebtPaid, target: "налог")), service: service), .done)
        XCTAssertEqual(service.debts.first?.isPaid, true)
        XCTAssertFalse(try plan(AIAction(kind: .markDebtPaid, target: "налог")).canApply)
    }

    func testChangingABillChangesKindAndRepeat() throws {
        let bill = Debt(name: "Интернет", amount: 4_500, dueDate: try date(2026, 11, 5), isLent: false, type: .bill, billKind: .internet, repeatRule: .monthly, firstDueDate: try date(2026, 11, 5))
        service.addDebt(bill)

        let planned = try plan(AIAction(kind: .changeDebt, target: "интернет", billKind: .phone, repeatRule: .yearly))
        XCTAssertTrue(planned.canApply, planned.problem ?? "")
        XCTAssertEqual(AIActionExecutor.apply(planned, service: service), .done)
        XCTAssertEqual(service.debts.first?.billKind, .phone)
        XCTAssertEqual(service.debts.first?.repeatRule, .yearly)

        // Новый срок становится точкой отсчёта для следующих
        XCTAssertEqual(AIActionExecutor.apply(try plan(AIAction(kind: .changeDebt, target: "интернет", date: try date(2026, 12, 20))), service: service), .done)
        XCTAssertTrue(calendar.isDate(try XCTUnwrap(service.debts.first?.firstDueDate), inSameDayAs: try date(2026, 12, 20)))
    }

    func testSchemaAndParsingKnowBills() throws {
        let schema = CloudFinanceAssistant.responseSchema()
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let actions = try XCTUnwrap(properties["actions"] as? [String: Any])
        let item = try XCTUnwrap(actions["items"] as? [String: Any])
        let itemProperties = try XCTUnwrap(item["properties"] as? [String: Any])
        XCTAssertNotNil(itemProperties["bill_kind"])
        XCTAssertEqual(Set(item["required"] as? [String] ?? []), Set(itemProperties.keys))

        let debtType = try XCTUnwrap(itemProperties["debt_type"] as? [String: Any])
        let options = try XCTUnwrap(debtType["anyOf"] as? [[String: Any]])
        let values = options.compactMap { $0["enum"] as? [String] }.flatMap { $0 }
        XCTAssertTrue(values.contains("bill"), "\(values)")

        let json = #"{"reply":"ок","operations":[],"actions":[{"kind":"add_debt","target":null,"name":null,"amount":4500,"currency":null,"date":"2026-11-05T00:00:00+04:00","direction":null,"debt_type":"bill","bill_kind":"internet","reminder":null,"repeat_rule":"monthly","note":null,"category":null,"setting":null,"value":null}]}"#
        let action = try XCTUnwrap(CloudFinanceAssistant.parse(json, provider: .claude).actions.first)
        XCTAssertEqual(action.debtType, .bill)
        XCTAssertEqual(action.billKind, .internet)
        XCTAssertEqual(action.repeatRule, .monthly)
    }
}
