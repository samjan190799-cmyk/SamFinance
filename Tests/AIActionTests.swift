import XCTest
@testable import SamFinance

/// Предложения ИИ: проверка (`plan`) и применение (`apply`). ИИ предлагает, пользователь подтверждает; исполнитель ничего не угадывает.
@MainActor
final class AIActionTests: XCTestCase {
    private var service: FinanceService { FinanceService.shared }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private var savedCurrency: AppCurrency = .amd
    private var savedDefaults: [String: Any] = [:]
    /// Настройки, которые тесты меняют: возвращаются на прежние значения после каждого теста
    private let restoredKeys = [ReminderKeys.debts, ReminderKeys.goalSaving, ReminderKeys.dailyLog, ReminderKeys.time, AutomationKeys.merchantRules]

    // Вызов super.setUp() здесь не нужен (он пустой) и не компилируется в Swift 6 для MainActor-классов
    override func setUp() async throws {
        service.resetAllData()
        savedCurrency = CurrencyManager.shared.currentCurrency
        CurrencyManager.shared.currentCurrency = .amd
        savedDefaults = [:]
        for key in restoredKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                savedDefaults[key] = value
            }
        }
    }

    override func tearDown() async throws {
        CurrencyManager.shared.currentCurrency = savedCurrency
        for key in restoredKeys {
            if let value = savedDefaults[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
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

    private func addDebt(_ name: String = "Арам", amount: Double = 20_000, due: Date? = nil, isLent: Bool = true) throws -> Debt {
        let debt = Debt(name: name, amount: amount, dueDate: try due ?? date(2026, 11, 5), isLent: isLent)
        service.addDebt(debt)
        return debt
    }

    // MARK: - Долги

    func testAddDebtIsPlannedAndApplied() throws {
        let due = try date(2026, 11, 5)
        let planned = try applied(AIAction(kind: .addDebt, name: "Арам", amount: 20_000, date: due, direction: .owedToMe, debtType: .person))
        XCTAssertFalse(planned.isDestructive)

        let debt = try XCTUnwrap(service.debts.first)
        XCTAssertEqual(debt.name, "Арам")
        XCTAssertEqual(debt.amount, 20_000, accuracy: 0.001)
        XCTAssertTrue(debt.isLent)
        XCTAssertEqual(debt.type, .person)
        XCTAssertTrue(calendar.isDate(debt.dueDate, inSameDayAs: due))
        XCTAssertEqual(debt.effectiveReminder, .standard)
    }

    func testAddDebtKeepsTheRequestedReminder() throws {
        try applied(AIAction(kind: .addDebt, name: "Ани", amount: 5_000, date: try date(2026, 11, 5), direction: .iOwe, reminder: .weekBefore))
        XCTAssertEqual(service.debts.first?.reminder, .weekBefore)
    }

    func testCreditIsAlwaysOnTheSideWhereIOwe() throws {
        try applied(AIAction(kind: .addDebt, name: "IDBank", amount: 126_000, date: try date(2026, 11, 26), debtType: .credit))
        let debt = try XCTUnwrap(service.debts.first)
        XCTAssertEqual(debt.type, .credit)
        XCTAssertFalse(debt.isLent)
    }

    func testIncompleteDebtIsNotGuessed() throws {
        let due = try date(2026, 11, 5)
        XCTAssertNotNil(try plan(AIAction(kind: .addDebt, name: "Арам", amount: 100, date: due)).problem, "не ясно, кто кому должен")
        XCTAssertNotNil(try plan(AIAction(kind: .addDebt, name: "Арам", amount: 100, direction: .owedToMe)).problem, "нет срока")
        XCTAssertNotNil(try plan(AIAction(kind: .addDebt, name: "Арам", date: due, direction: .owedToMe)).problem, "нет суммы")
        XCTAssertNotNil(try plan(AIAction(kind: .addDebt, amount: 100, date: due, direction: .owedToMe)).problem, "нет имени")
        XCTAssertNotNil(try plan(AIAction(kind: .addDebt, name: "Арам", amount: -5, date: due, direction: .owedToMe)).problem, "сумма меньше нуля")
        XCTAssertTrue(service.debts.isEmpty)
    }

    func testSameDebtIsNotAddedTwice() throws {
        _ = try addDebt("Арам", amount: 20_000, due: try date(2026, 11, 5))
        let planned = try plan(AIAction(kind: .addDebt, name: "арам", amount: 20_000, date: try date(2026, 11, 5), direction: .owedToMe))
        XCTAssertFalse(planned.canApply)
        XCTAssertNotNil(planned.problem)
    }

    func testDebtIsFoundByShortIdByNameAndByBracketedId() throws {
        let debt = try addDebt("Арам")
        let short = AIActionExecutor.shortID(debt.id)
        for target in [short, short.lowercased(), "[d:\(short)]", "арам", "Арам "] {
            let planned = try plan(AIAction(kind: .markDebtPaid, target: target))
            XCTAssertTrue(planned.canApply, "\(target): \(planned.problem ?? "")")
        }
        XCTAssertFalse(try plan(AIAction(kind: .markDebtPaid, target: "Тигран")).canApply)
    }

    func testMarkPaidAndBack() throws {
        let debt = try addDebt()
        try applied(AIAction(kind: .markDebtPaid, target: AIActionExecutor.shortID(debt.id)))
        XCTAssertEqual(service.debts.first?.isPaid, true)

        XCTAssertNotNil(try plan(AIAction(kind: .markDebtPaid, target: "Арам")).problem, "уже погашен")

        try applied(AIAction(kind: .markDebtUnpaid, target: "Арам"))
        XCTAssertEqual(service.debts.first?.isPaid, false)
    }

    func testAmbiguousNameIsNotGuessed() throws {
        _ = try addDebt("Арам", amount: 1_000)
        _ = try addDebt("Арам", amount: 2_000)
        let planned = try plan(AIAction(kind: .deleteDebt, target: "Арам"))
        XCTAssertFalse(planned.canApply)
        XCTAssertNotNil(planned.problem)
        XCTAssertEqual(service.debts.count, 2)
    }

    func testChangeDebtTouchesOnlyWhatWasAsked() throws {
        let debt = try addDebt("Арам", amount: 20_000, due: try date(2026, 11, 5))
        try applied(AIAction(kind: .changeDebt, target: "Арам", amount: 25_000, date: try date(2026, 12, 1), reminder: .off))

        let changed = try XCTUnwrap(service.debts.first)
        XCTAssertEqual(changed.id, debt.id)
        XCTAssertEqual(changed.name, "Арам")
        XCTAssertEqual(changed.amount, 25_000, accuracy: 0.001)
        XCTAssertTrue(calendar.isDate(changed.dueDate, inSameDayAs: try date(2026, 12, 1)))
        XCTAssertEqual(changed.reminder, DebtReminder.off)
        XCTAssertEqual(changed.isLent, debt.isLent)

        XCTAssertNotNil(try plan(AIAction(kind: .changeDebt, target: "Арам")).problem, "ничего не меняется")
    }

    func testChangeDebtKeepsThePaidMark() throws {
        let debt = try addDebt()
        service.setDebtPaid(id: debt.id, isPaid: true)
        try applied(AIAction(kind: .changeDebt, target: "Арам", amount: 30_000))
        XCTAssertEqual(service.debts.first?.isPaid, true)
    }

    func testDeleteIsMarkedDestructiveAndRemovesTheDebt() throws {
        let debt = try addDebt()
        let planned = try applied(AIAction(kind: .deleteDebt, target: AIActionExecutor.shortID(debt.id)))
        XCTAssertTrue(planned.isDestructive)
        XCTAssertTrue(service.debts.isEmpty)
    }

    func testAmountInAnotherCurrencyIsAccepted() throws {
        // Сумма пересчитывается по текущему курсу; сам курс зависит от сети, поэтому проверяется только результат
        let planned = try plan(AIAction(kind: .addDebt, name: "Арам", amount: 100, currency: .usd, date: try date(2026, 11, 5), direction: .owedToMe))
        XCTAssertTrue(planned.canApply)
        if case .addDebt(let debt)? = planned.operation {
            XCTAssertGreaterThan(debt.amount, 0)
        } else {
            XCTFail("ожидалась операция addDebt")
        }
    }

    // MARK: - Копилки

    func testGoalLifecycle() throws {
        try applied(AIAction(kind: .addGoal, name: "Отпуск", amount: 100_000, date: try date(2027, 6, 1)))
        let goal = try XCTUnwrap(service.goals.first)
        XCTAssertEqual(goal.title, "Отпуск")
        XCTAssertEqual(goal.targetAmount, 100_000, accuracy: 0.001)
        XCTAssertNotNil(goal.deadline)
        XCTAssertNil(goal.cardId)

        try applied(AIAction(kind: .depositGoal, target: "Отпуск", amount: 30_000))
        XCTAssertEqual(service.goals.first?.currentAmount ?? 0, 30_000, accuracy: 0.001)

        let tooMuch = try plan(AIAction(kind: .withdrawGoal, target: "Отпуск", amount: 50_000))
        XCTAssertFalse(tooMuch.canApply, "в копилке только 30 000")

        try applied(AIAction(kind: .withdrawGoal, target: "Отпуск", amount: 10_000))
        XCTAssertEqual(service.goals.first?.currentAmount ?? 0, 20_000, accuracy: 0.001)

        try applied(AIAction(kind: .changeGoal, target: "Отпуск", name: "Отпуск в Грузии", amount: 150_000))
        XCTAssertEqual(service.goals.first?.title, "Отпуск в Грузии")
        XCTAssertEqual(service.goals.first?.targetAmount ?? 0, 150_000, accuracy: 0.001)
        XCTAssertEqual(service.goals.first?.currentAmount ?? 0, 20_000, accuracy: 0.001, "накопленное не теряется при правке")

        let deletion = try applied(AIAction(kind: .deleteGoal, target: "Грузии"))
        XCTAssertTrue(deletion.isDestructive)
        XCTAssertTrue(service.goals.isEmpty)
    }

    func testGoalNeedsANameAndATarget() throws {
        XCTAssertNotNil(try plan(AIAction(kind: .addGoal, amount: 1_000)).problem)
        XCTAssertNotNil(try plan(AIAction(kind: .addGoal, name: "Машина")).problem)
        XCTAssertNotNil(try plan(AIAction(kind: .depositGoal, target: "Машина", amount: 10)).problem, "такой копилки нет")
    }

    // MARK: - Свои напоминания

    func testReminderLifecycle() throws {
        let when = try date(2026, 11, 7, hour: 10)
        try applied(AIAction(kind: .addReminder, name: "Оплатить интернет", date: when, repeatRule: .monthly, note: "счёт на почте"))
        let reminder = try XCTUnwrap(service.customReminders.first)
        XCTAssertEqual(reminder.title, "Оплатить интернет")
        XCTAssertEqual(reminder.date, when)
        XCTAssertEqual(reminder.repeatRule, .monthly)
        XCTAssertEqual(reminder.note, "счёт на почте")

        try applied(AIAction(kind: .changeReminder, target: "интернет", date: try date(2026, 11, 9, hour: 9), repeatRule: .weekly))
        let changed = try XCTUnwrap(service.customReminders.first)
        XCTAssertEqual(changed.id, reminder.id)
        XCTAssertEqual(changed.repeatRule, .weekly)
        XCTAssertEqual(changed.title, "Оплатить интернет")

        let deletion = try applied(AIAction(kind: .deleteReminder, target: AIActionExecutor.shortID(reminder.id)))
        XCTAssertTrue(deletion.isDestructive)
        XCTAssertTrue(service.customReminders.isEmpty)
    }

    func testReminderInThePastIsRejectedButARepeatingOneIsNot() throws {
        let past = try date(2026, 10, 1)
        XCTAssertNotNil(try plan(AIAction(kind: .addReminder, name: "Позвонить", date: past)).problem)
        XCTAssertTrue(try plan(AIAction(kind: .addReminder, name: "Позвонить", date: past, repeatRule: .weekly)).canApply)
        XCTAssertNotNil(try plan(AIAction(kind: .addReminder, date: try date(2026, 11, 1))).problem, "нет текста")
        XCTAssertNotNil(try plan(AIAction(kind: .addReminder, name: "Позвонить")).problem, "нет даты")
    }

    // MARK: - Карты и операции

    func testFreezeAndUnfreezeCardByItsLastDigits() throws {
        let card = Card(last4: "0640", holderName: "TEST", balance: 1_000, colorHex: "#2A2B30", gradientColors: ["#2A2B30"])
        service.addCard(card, number: "")

        try applied(AIAction(kind: .freezeCard, target: "0640"))
        XCTAssertEqual(service.cards.first?.isFrozen, true)
        XCTAssertNotNil(try plan(AIAction(kind: .freezeCard, target: "•••• 0640")).problem, "уже заморожена")

        try applied(AIAction(kind: .unfreezeCard, target: "0640"))
        XCTAssertEqual(service.cards.first?.isFrozen, false)
        XCTAssertFalse(try plan(AIAction(kind: .freezeCard, target: "9999")).canApply)
    }

    func testTransactionCategoryIsChangedAndDeleted() throws {
        let groceries = try XCTUnwrap(service.categories.first { $0.name == "Продукты" && $0.type == .expense })
        let other = try XCTUnwrap(service.categories.first { $0.name == "Прочее" && $0.type == .expense })
        let transaction = Transaction(title: "TestShop Zq", amount: 3_500, type: .expense, category: other)
        service.addTransaction(transaction)
        let short = AIActionExecutor.shortID(transaction.id)

        try applied(AIAction(kind: .setTransactionCategory, target: short, category: "продукты"))
        XCTAssertEqual(service.transactions.first?.category.id, groceries.id)

        XCTAssertNotNil(try plan(AIAction(kind: .setTransactionCategory, target: short, category: "Зарплата")).problem, "доходная категория для расхода")
        XCTAssertNotNil(try plan(AIAction(kind: .setTransactionCategory, target: short)).problem, "нет категории")

        let deletion = try applied(AIAction(kind: .deleteTransaction, target: short))
        XCTAssertTrue(deletion.isDestructive)
        XCTAssertTrue(service.transactions.isEmpty)
    }

    // MARK: - Настройки

    func testCurrencyIsChanged() throws {
        try applied(AIAction(kind: .setCurrency, value: "usd"))
        XCTAssertEqual(CurrencyManager.shared.currentCurrency, .usd)
        XCTAssertNotNil(try plan(AIAction(kind: .setCurrency, value: "XXX")).problem)
    }

    func testReminderSettingsAreChanged() throws {
        try applied(AIAction(kind: .setReminderSetting, setting: .dailyLog, value: "on"))
        XCTAssertEqual(UserDefaults.standard.bool(forKey: ReminderKeys.dailyLog), true)

        try applied(AIAction(kind: .setReminderSetting, setting: .debts, value: "off"))
        XCTAssertEqual(UserDefaults.standard.bool(forKey: ReminderKeys.debts), false)

        try applied(AIAction(kind: .setReminderSetting, setting: .reminderTime, value: "09:30"))
        XCTAssertEqual(UserDefaults.standard.integer(forKey: ReminderKeys.time), 570)

        try applied(AIAction(kind: .setReminderSetting, setting: .goalSaving, value: "weekly"))
        XCTAssertEqual(UserDefaults.standard.string(forKey: ReminderKeys.goalSaving), GoalSavingReminder.weekly.rawValue)

        XCTAssertNotNil(try plan(AIAction(kind: .setReminderSetting, setting: .reminderTime, value: "25:00")).problem)
        XCTAssertNotNil(try plan(AIAction(kind: .setReminderSetting, setting: .dailyLog, value: "maybe")).problem)
        XCTAssertNotNil(try plan(AIAction(kind: .setReminderSetting, value: "on")).problem, "не названа настройка")
    }

    // MARK: - Прочее

    func testNotificationsAreNeededOnlyForReminderLikeChanges() throws {
        let add = try plan(AIAction(kind: .addReminder, name: "Позвонить", date: try date(2026, 11, 1)))
        XCTAssertTrue(AIActionExecutor.needsNotifications(add))

        let deadlineGoal = try plan(AIAction(kind: .addGoal, name: "Машина", amount: 1_000, date: try date(2027, 1, 1)))
        XCTAssertTrue(AIActionExecutor.needsNotifications(deadlineGoal))

        let plainGoal = try plan(AIAction(kind: .addGoal, name: "Машина", amount: 1_000))
        XCTAssertFalse(AIActionExecutor.needsNotifications(plainGoal))

        let debt = try addDebt()
        let deletion = try plan(AIAction(kind: .deleteDebt, target: AIActionExecutor.shortID(debt.id)))
        XCTAssertFalse(AIActionExecutor.needsNotifications(deletion))
    }

    func testProblemPlanCannotBeApplied() throws {
        let broken = try plan(AIAction(kind: .markDebtPaid, target: "нет такого"))
        XCTAssertFalse(broken.canApply)
        if case .failed = AIActionExecutor.apply(broken, service: service) {
            // ожидаемо: проблемное предложение ничего не меняет
        } else {
            XCTFail("предложение с проблемой не должно применяться")
        }
    }

    func testEveryKindHasASummaryAndAnIcon() throws {
        for kind in AIAction.Kind.allCases {
            let planned = try plan(AIAction(kind: kind))
            XCTAssertFalse(planned.summary.isEmpty, kind.rawValue)
            XCTAssertFalse(planned.icon.isEmpty, kind.rawValue)
            XCTAssertEqual(planned.isDestructive, kind.isDestructive, kind.rawValue)
            XCTAssertFalse(planned.canApply, "пустое предложение «\(kind.rawValue)» ничего не знает и не должно применяться")
        }
    }
}

/// Ответ облачного ИИ с действиями: разбор и схема, которую получают все три сервиса
@MainActor
final class CloudActionParsingTests: XCTestCase {
    private let nullFields = #""target":null,"name":null,"amount":null,"currency":null,"date":null,"direction":null,"debt_type":null,"reminder":null,"repeat_rule":null,"note":null,"category":null,"setting":null,"value":null"#

    func testActionsAreParsedAndUnknownKindsAreDropped() throws {
        let json = """
        {"reply":"Добавлю долг и напоминание","operations":[],"actions":[
          {"kind":"add_debt","target":null,"name":"Арам","amount":20000,"currency":"AMD","date":"2026-11-05T00:00:00+04:00","direction":"owedToMe","debt_type":"person","reminder":"dayBefore","repeat_rule":null,"note":null,"category":null,"setting":null,"value":null},
          {"kind":"launch_rocket",\(nullFields)},
          {"kind":"add_reminder","target":null,"name":"Оплатить интернет","amount":null,"currency":null,"date":"2026-11-07T10:00:00+04:00","direction":null,"debt_type":null,"reminder":null,"repeat_rule":"monthly","note":"счёт на почте","category":null,"setting":null,"value":null}
        ]}
        """
        let reply = try CloudFinanceAssistant.parse(json, provider: .claude)
        XCTAssertEqual(reply.text, "Добавлю долг и напоминание")
        XCTAssertEqual(reply.actions.count, 2, "неизвестный вид действия отбрасывается")

        let debt = try XCTUnwrap(reply.actions.first)
        XCTAssertEqual(debt.kind, .addDebt)
        XCTAssertEqual(debt.name, "Арам")
        XCTAssertEqual(debt.amount, 20_000)
        XCTAssertEqual(debt.currency, .amd)
        XCTAssertEqual(debt.direction, .owedToMe)
        XCTAssertEqual(debt.debtType, .person)
        XCTAssertEqual(debt.reminder, .dayBefore)
        XCTAssertNotNil(debt.date)

        let reminder = try XCTUnwrap(reply.actions.last)
        XCTAssertEqual(reminder.kind, .addReminder)
        XCTAssertEqual(reminder.repeatRule, .monthly)
        XCTAssertEqual(reminder.note, "счёт на почте")
    }

    func testAnswerWithoutActionsStillParses() throws {
        let reply = try CloudFinanceAssistant.parse(#"{"reply":"Привет","operations":[]}"#, provider: .gemini)
        XCTAssertEqual(reply.text, "Привет")
        XCTAssertTrue(reply.actions.isEmpty)
    }

    func testBlankStringsBecomeNil() throws {
        let json = #"{"reply":"ок","operations":[],"actions":[{"kind":"delete_debt","target":"  ","name":"","amount":null,"currency":"zzz","date":"не дата","direction":"nobody","debt_type":null,"reminder":null,"repeat_rule":null,"note":null,"category":null,"setting":null,"value":null}]}"#
        let action = try XCTUnwrap(CloudFinanceAssistant.parse(json, provider: .openAI).actions.first)
        XCTAssertNil(action.target)
        XCTAssertNil(action.name)
        XCTAssertNil(action.currency)
        XCTAssertNil(action.date)
        XCTAssertNil(action.direction)
    }

    func testDatesMayLieInTheFutureAndMayBeDateOnly() {
        XCTAssertNotNil(CloudFinanceAssistant.parseISO("2099-01-01T10:00:00+04:00"))
        XCTAssertNotNil(CloudFinanceAssistant.parseISO("2026-11-05T10:00:00"))
        XCTAssertNotNil(CloudFinanceAssistant.parseISO("2026-11-05"))
        XCTAssertNil(CloudFinanceAssistant.parseISO("пятница"))
    }

    func testSchemaListsEveryActionFieldAsRequired() throws {
        let schema = CloudFinanceAssistant.responseSchema()
        XCTAssertEqual(Set(schema["required"] as? [String] ?? []), ["reply", "operations", "actions"])

        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let actions = try XCTUnwrap(properties["actions"] as? [String: Any])
        let item = try XCTUnwrap(actions["items"] as? [String: Any])
        let itemProperties = try XCTUnwrap(item["properties"] as? [String: Any])

        // Строгие схемы (OpenAI, Claude) требуют, чтобы все поля были обязательными и не было лишних
        XCTAssertEqual(Set(item["required"] as? [String] ?? []), Set(itemProperties.keys))
        XCTAssertEqual(item["additionalProperties"] as? Bool, false)

        let kind = try XCTUnwrap(itemProperties["kind"] as? [String: Any])
        XCTAssertEqual(kind["enum"] as? [String], AIAction.Kind.allCases.map(\.rawValue))
    }

    func testSchemaIsAcceptedInEveryFormat() throws {
        let schema = CloudFinanceAssistant.responseSchema()
        XCTAssertTrue(JSONSerialization.isValidJSONObject(schema))
        XCTAssertTrue(JSONSerialization.isValidJSONObject(GeminiAPI.geminiSchema(schema)))

        let prompt = AIPrompt(system: "SYSTEM", turns: [], leadingText: nil, images: [], text: "question")
        XCTAssertNoThrow(try ClaudeAPI.requestBody(prompt, schema: schema))
        XCTAssertNoThrow(try OpenAIAPI.requestBody(prompt, schema: schema))
        XCTAssertNoThrow(try GeminiAPI.requestBody(prompt, schema: schema))
    }
}
