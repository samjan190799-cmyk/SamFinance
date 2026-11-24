import XCTest
@testable import SamFinance

/// ИИ-чат: любые языки, подписки и балансы карт и наличных в действиях ИИ
@MainActor
final class AIChatExpansionTests: XCTestCase {
    private var service: FinanceService { FinanceService.shared }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private var savedCurrency: AppCurrency = .amd

    // Вызов super.setUp() здесь не нужен (он пустой) и не компилируется в Swift 6 для MainActor-классов
    override func setUp() async throws {
        service.resetAllData()
        savedCurrency = CurrencyManager.shared.currentCurrency
        CurrencyManager.shared.currentCurrency = .amd
    }

    override func tearDown() async throws {
        CurrencyManager.shared.currentCurrency = savedCurrency
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

    @discardableResult
    private func addNetflix() -> AppSubscription {
        let subscription = AppSubscription(name: "Netflix", amount: 4_990, currency: .amd, period: .monthly, category: .video)
        service.addSubscription(subscription)
        return subscription
    }

    // MARK: - Язык: подсказка модели

    func testPromptAsksForAnswersInTheLanguageOfTheUser() {
        let prompt = CloudFinanceAssistant.systemPrompt()
        XCTAssertTrue(prompt.contains("на любом языке"))
        XCTAssertTrue(prompt.contains("на том языке, на котором он написал последнее сообщение"))
        XCTAssertTrue(prompt.contains(AppLanguage.current.promptName), "язык приложения нужен как запасной")
        XCTAssertFalse(prompt.contains("Отвечай на языке пользователя ("), "язык ответа больше не привязан к языку приложения")
    }

    func testPromptDescribesEveryKindOfAction() {
        let prompt = CloudFinanceAssistant.systemPrompt()
        for kind in AIAction.Kind.allCases {
            XCTAssertTrue(prompt.contains(kind.rawValue), "в подсказке нет действия \(kind.rawValue)")
        }
        for category in SubscriptionCategory.allCases {
            XCTAssertTrue(prompt.contains(category.rawValue), "в подсказке нет вида подписки \(category.rawValue)")
        }
    }

    // MARK: - Данные для модели

    func testContextListsSubscriptionsAndCash() throws {
        let subscription = addNetflix()
        XCTAssertTrue(service.setCashBalance(to: 12_000))

        let context = CloudFinanceAssistant.financeContext()
        XCTAssertTrue(context.contains("[s:\(AIActionExecutor.shortID(subscription.id))]"), context)
        XCTAssertTrue(context.contains("Netflix"))
        XCTAssertTrue(context.contains("Подписки (активных 1"))
        XCTAssertTrue(context.contains("вид: video"))
        XCTAssertTrue(context.contains("Наличные:"), "наличные нужны модели, чтобы отвечать про общий баланс")
    }

    func testContextSaysWhenThereAreNoSubscriptions() {
        XCTAssertTrue(CloudFinanceAssistant.financeContext().contains("Подписок нет."))
    }

    // MARK: - Разбор ответа

    func testNewKindsAreParsed() throws {
        let json = #"{"reply":"ок","operations":[],"actions":[{"kind":"add_subscription","name":"Netflix","amount":4990,"currency":"AMD","repeat_rule":"monthly","category":"video"},{"kind":"top_up_balance","target":"cash","amount":20000},{"kind":"set_balance","target":"7642","amount":0},{"kind":"archive_subscription","target":"Netflix"}]}"#
        let actions = try CloudFinanceAssistant.parse(json, provider: .gemini).actions
        XCTAssertEqual(actions.map(\.kind), [.addSubscription, .topUpBalance, .setBalance, .archiveSubscription])
        XCTAssertEqual(actions[0].category, "video")
        XCTAssertEqual(actions[0].repeatRule, .monthly)
        XCTAssertEqual(actions[1].target, "cash")
        XCTAssertEqual(actions[2].amount, 0)
    }

    func testDeletingASubscriptionIsMarkedAsDestructive() {
        XCTAssertTrue(AIAction.Kind.deleteSubscription.isDestructive)
        XCTAssertFalse(AIAction.Kind.archiveSubscription.isDestructive)
    }

    // MARK: - Подписки

    func testAddingASubscription() throws {
        try applied(AIAction(
            kind: .addSubscription,
            name: "Netflix",
            amount: 4_990,
            currency: .amd,
            date: try date(2026, 11, 5),
            reminder: .dayBefore,
            repeatRule: .monthly,
            category: "video"
        ))
        let subscription = try XCTUnwrap(service.subscriptions.first)
        XCTAssertEqual(subscription.name, "Netflix")
        XCTAssertEqual(subscription.amount, 4_990)
        XCTAssertEqual(subscription.currency, .amd)
        XCTAssertEqual(subscription.period, .monthly)
        XCTAssertEqual(subscription.category, .video)
        XCTAssertEqual(subscription.reminder, .dayBefore)
        XCTAssertEqual(subscription.firstChargeDate, calendar.startOfDay(for: try date(2026, 11, 5)))
        XCTAssertEqual(subscription.status, .active)
    }

    func testSubscriptionDefaultsAndTheCurrencyKeepsItsOwnAmount() throws {
        try applied(AIAction(kind: .addSubscription, name: "iCloud", amount: 2.99, currency: .usd))
        let subscription = try XCTUnwrap(service.subscriptions.first)
        XCTAssertEqual(subscription.amount, 2.99, accuracy: 0.0001, "сумма подписки хранится в её валюте, без пересчёта")
        XCTAssertEqual(subscription.currency, .usd)
        XCTAssertEqual(subscription.period, .monthly, "без повтора подписка месячная")
        XCTAssertEqual(subscription.category, .other)
        XCTAssertEqual(subscription.firstChargeDate, calendar.startOfDay(for: try now()), "без даты первое списание сегодня")
    }

    func testSubscriptionCategoryIsFoundByNameOrTitle() throws {
        try applied(AIAction(kind: .addSubscription, name: "Хостинг", amount: 3_000, category: "Hosting"))
        XCTAssertEqual(service.subscriptions.first?.category, .hosting)
        try applied(AIAction(kind: .addSubscription, name: "Курс", amount: 9_000, repeatRule: .yearly, category: "unknown-kind"))
        XCTAssertEqual(service.subscriptions.first?.category, .other, "незнакомый вид не мешает добавить подписку")
        XCTAssertEqual(service.subscriptions.first?.period, .yearly)
    }

    func testQuarterlySubscriptionUsesAnInterval() throws {
        try applied(AIAction(kind: .addSubscription, name: "Страховка", amount: 30_000, repeatRule: .monthly, interval: 3))
        XCTAssertEqual(service.subscriptions.first?.interval, 3)
    }

    func testSubscriptionProblemsAreReported() throws {
        XCTAssertFalse(try plan(AIAction(kind: .addSubscription, amount: 100)).canApply, "нет названия")
        XCTAssertFalse(try plan(AIAction(kind: .addSubscription, name: "Netflix")).canApply, "нет суммы")
        XCTAssertFalse(try plan(AIAction(kind: .addSubscription, name: "Netflix", amount: -5)).canApply, "отрицательная сумма")
        XCTAssertFalse(try plan(AIAction(kind: .addSubscription, name: "Netflix", amount: 100, repeatRule: .daily)).canApply, "каждый день подписка не повторяется")
        XCTAssertFalse(try plan(AIAction(kind: .changeSubscription, target: "нет такой", amount: 100)).canApply)
        XCTAssertFalse(try plan(AIAction(kind: .pauseSubscription, target: "нет такой")).canApply)
        XCTAssertTrue(service.subscriptions.isEmpty)
    }

    func testChangingASubscription() throws {
        let subscription = addNetflix()
        try applied(AIAction(kind: .changeSubscription, target: AIActionExecutor.shortID(subscription.id), amount: 5_990, repeatRule: .yearly, category: "music"))
        let changed = try XCTUnwrap(service.subscriptions.first)
        XCTAssertEqual(changed.amount, 5_990)
        XCTAssertEqual(changed.period, .yearly)
        XCTAssertEqual(changed.category, .music)
        XCTAssertEqual(changed.name, "Netflix")

        let nothing = try plan(AIAction(kind: .changeSubscription, target: "Netflix"))
        XCTAssertFalse(nothing.canApply, "нечего менять")
    }

    func testPausingResumingAndArchivingASubscription() throws {
        addNetflix()
        try applied(AIAction(kind: .pauseSubscription, target: "Netflix"))
        XCTAssertEqual(service.subscriptions.first?.status, .paused)
        XCTAssertFalse(try plan(AIAction(kind: .pauseSubscription, target: "Netflix")).canApply, "уже на паузе")

        try applied(AIAction(kind: .resumeSubscription, target: "netflix"))
        XCTAssertEqual(service.subscriptions.first?.status, .active)

        try applied(AIAction(kind: .archiveSubscription, target: "Netflix"))
        XCTAssertEqual(service.subscriptions.first?.status, .archived)
    }

    func testDeletingASubscription() throws {
        addNetflix()
        let planned = try applied(AIAction(kind: .deleteSubscription, target: "Netflix"))
        XCTAssertTrue(planned.isDestructive)
        XCTAssertTrue(service.subscriptions.isEmpty)
    }

    func testSubscriptionRemindersNeedNotifications() throws {
        let planned = try plan(AIAction(kind: .addSubscription, name: "Netflix", amount: 4_990, reminder: .dayBefore))
        XCTAssertTrue(AIActionExecutor.needsNotifications(planned))
        let silent = try plan(AIAction(kind: .addSubscription, name: "Netflix", amount: 4_990, reminder: DebtReminder.off))
        XCTAssertFalse(AIActionExecutor.needsNotifications(silent))
    }

    // MARK: - Балансы наличных и карт

    func testTopUpAndReduceCash() throws {
        try applied(AIAction(kind: .topUpBalance, target: "cash", amount: 20_000))
        XCTAssertEqual(service.cashBalance, 20_000, accuracy: 0.001)

        try applied(AIAction(kind: .reduceBalance, target: "Наличные", amount: 5_000))
        XCTAssertEqual(service.cashBalance, 15_000, accuracy: 0.001)
        XCTAssertTrue(service.transactions.isEmpty, "правка баланса не операция")
    }

    func testSetBalanceMayBeZero() throws {
        XCTAssertTrue(service.setCashBalance(to: 80_000))
        try applied(AIAction(kind: .setBalance, target: "cash", amount: 0))
        XCTAssertEqual(service.cashBalance, 0)
        try applied(AIAction(kind: .setBalance, target: "наличка", amount: 1_500))
        XCTAssertEqual(service.cashBalance, 1_500, accuracy: 0.001)
    }

    func testBalanceOfACardIsFoundByItsLastDigits() throws {
        let card = Card(last4: "7642", holderName: "TEST USER", balance: 100_000, colorHex: "#2A2B30", gradientColors: ["#2A2B30"])
        service.addCard(card, number: "")

        try applied(AIAction(kind: .reduceBalance, target: "7642", amount: 30_000))
        XCTAssertEqual(try XCTUnwrap(service.cards.first).balance, 70_000, accuracy: 0.001)
        XCTAssertEqual(service.cashBalance, 0, "наличные не тронуты")

        try applied(AIAction(kind: .setBalance, target: "•••• 7642", amount: 500_000))
        XCTAssertEqual(try XCTUnwrap(service.cards.first).balance, 500_000, accuracy: 0.001)
    }

    func testBalanceProblemsAreReported() throws {
        XCTAssertFalse(try plan(AIAction(kind: .topUpBalance, target: "9999", amount: 10)).canApply, "такой карты нет")
        XCTAssertFalse(try plan(AIAction(kind: .topUpBalance, amount: 10)).canApply, "не назван счёт")
        XCTAssertFalse(try plan(AIAction(kind: .topUpBalance, target: "cash")).canApply, "нет суммы")
        XCTAssertFalse(try plan(AIAction(kind: .reduceBalance, target: "cash", amount: -10)).canApply, "отрицательная сумма")
        XCTAssertFalse(try plan(AIAction(kind: .setBalance, target: "cash", amount: -1)).canApply, "новый баланс не может быть отрицательным в просьбе")
        XCTAssertEqual(service.cashBalance, 0)
    }

    func testBalanceAmountInAnotherCurrencyIsConverted() throws {
        let planned = try plan(AIAction(kind: .topUpBalance, target: "cash", amount: 10, currency: .usd))
        XCTAssertTrue(planned.canApply)
        guard case .adjustBalance(.cash, let delta)? = planned.operation else {
            return XCTFail("ожидалась правка наличных")
        }
        let expected = CurrencyService.shared.convert(amount: 10, from: .usd, to: CurrencyManager.shared.baseCurrency)
        XCTAssertEqual(delta, expected, accuracy: 0.001)
    }

    // MARK: - Локальный помощник на других языках

    private func prepareLocalData() throws {
        let groceries = try XCTUnwrap(service.categories.first { $0.name == "Продукты" })
        service.addTransaction(Transaction(title: "SAS", amount: 5_000, type: .expense, category: groceries, brandName: "SAS"))
        service.addTransaction(Transaction(title: "Carrefour", amount: 3_000, type: .expense, category: groceries, brandName: "Carrefour"))
        service.addCard(
            Card(last4: "7642", holderName: "TEST USER", balance: 845_300, colorHex: "#C6F432", gradientColors: ["#C6F432"]),
            number: ""
        )
        addNetflix()
    }

    private func answer(_ question: String) -> String {
        LocalFinanceAssistant.answer(question, financeService: service)
    }

    private func money(_ amount: Double) -> String {
        CurrencyManager.shared.format(amount)
    }

    func testSpendingQuestionsInManyLanguages() throws {
        try prepareLocalData()
        let expected = money(8_000)
        let questions = [
            "¿cuánto gasté esta semana?",
            "combien ai-je dépensé cette semaine ?",
            "wie viel habe ich diese Woche ausgegeben?",
            "quanto ho speso questa settimana?",
            "quanto gastei esta semana?",
            "bu hafta ne kadar harcadım?",
            "ile wydałem w tym tygodniu?",
            "скільки я витратив за тиждень?",
            "كم أنفقت هذا الأسبوع",
            "这周我花了多少钱",
            "今週いくら使った",
            "이번 주 지출은?",
            "რამდენი დავხარჯე ამ კვირას"
        ]
        for question in questions {
            let reply = answer(question)
            XCTAssertNotEqual(reply, LocalFinanceAssistant.helpText, question)
            XCTAssertTrue(reply.contains(expected), "\(question) → \(reply)")
        }
    }

    func testBalanceQuestionsInManyLanguages() throws {
        try prepareLocalData()
        let questions = [
            "¿cuál es mi saldo?",
            "quel est mon solde ?",
            "wie hoch ist mein Kontostand?",
            "qual è il mio saldo?",
            "qual é o meu saldo?",
            "bakiyem ne kadar?",
            "jaki mam stan konta?",
            "який у мене залишок?",
            "ما هو رصيدي",
            "我的余额是多少",
            "残高を教えて",
            "잔액이 얼마야",
            "რა ბალანსი მაქვს"
        ]
        for question in questions {
            let reply = answer(question)
            XCTAssertTrue(reply.contains("7642"), "\(question) → \(reply)")
            XCTAssertTrue(reply.contains(money(845_300)), "\(question) → \(reply)")
        }
    }

    func testSubscriptionQuestionsInManyLanguages() throws {
        try prepareLocalData()
        let questions = [
            "сколько я трачу на подписки?",
            "how much do I spend on subscriptions?",
            "¿cuánto gasto en suscripciones?",
            "combien me coûtent mes abonnements ?",
            "wie viel kosten meine Abos?",
            "quanto pago di abbonamenti?",
            "quanto gasto com assinaturas?",
            "abonelikler ne kadar?",
            "скільки коштують підписки?",
            "اشتراكاتي",
            "我的订阅多少钱",
            "サブスクはいくら",
            "구독료는 얼마야",
            "բաժանորդագրություններս"
        ]
        for question in questions {
            let reply = answer(question)
            XCTAssertTrue(reply.contains("Netflix"), "\(question) → \(reply)")
            XCTAssertTrue(reply.contains(money(4_990)), "\(question) → \(reply)")
        }
    }

    func testSubscriptionAnswerWithoutSubscriptions() {
        let reply = answer("how much do I spend on subscriptions?")
        XCTAssertNotEqual(reply, LocalFinanceAssistant.helpText)
        XCTAssertFalse(reply.contains("Netflix"))
    }

    func testEnglishWordsNoLongerHijackOtherLanguages() throws {
        try prepareLocalData()
        // «gas» из бензина, «tip» из совета и «debit» из карты раньше ловились внутри слов других языков
        for question in ["¿cuánto gasté esta semana?", "quanto gastei esta semana?", "what did I spend with my debit card this week?"] {
            let reply = answer(question)
            XCTAssertTrue(reply.contains(money(8_000)), "\(question) → \(reply)")
        }
        // «stipendio» (зарплата) содержит «tip»: это вопрос про доход, а не про совет
        let income = answer("quanto ho ricevuto di stipendio questo mese?")
        XCTAssertNotEqual(income, LocalFinanceAssistant.helpText)
        XCTAssertFalse(income.contains("Netflix"))
    }
}
