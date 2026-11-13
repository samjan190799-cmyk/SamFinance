import XCTest
import UserNotifications
@testable import SamFinance

/// Подписки: стоимость в месяц и в год, ближайшее списание, порядок в списке, напоминания, хранение и переводы
@MainActor
final class SubscriptionTests: XCTestCase {
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

    /// 26 октября 2026, 08:00 — раньше времени напоминаний (10:00)
    private func now() throws -> Date {
        try date(2026, 10, 26, hour: 8)
    }

    private func makeSubscription(
        name: String = "Кино",
        amount: Double = 1_000,
        currency: AppCurrency = .amd,
        period: SubscriptionPeriod = .monthly,
        interval: Int? = nil,
        first: Date,
        status: SubscriptionStatus = .active,
        reminder: DebtReminder? = nil
    ) -> AppSubscription {
        AppSubscription(
            name: name, amount: amount, currency: currency, period: period, interval: interval,
            firstChargeDate: first, status: status, reminder: reminder
        )
    }

    // MARK: - Стоимость в месяц и в год

    func testMonthlySubscriptionCosts() throws {
        let subscription = makeSubscription(amount: 1_000, first: try date(2026, 10, 5))
        XCTAssertEqual(subscription.costPerMonth, 1_000, accuracy: 0.001)
        XCTAssertEqual(subscription.costPerYear, 12_000, accuracy: 0.001)
    }

    func testWeeklySubscriptionCostsUseFiftyTwoWeeks() throws {
        let subscription = makeSubscription(amount: 100, period: .weekly, first: try date(2026, 10, 5))
        XCTAssertEqual(subscription.costPerYear, 5_200, accuracy: 0.001)
        XCTAssertEqual(subscription.costPerMonth, 5_200.0 / 12, accuracy: 0.001)
    }

    func testYearlySubscriptionCosts() throws {
        let subscription = makeSubscription(amount: 12_000, period: .yearly, first: try date(2026, 3, 10))
        XCTAssertEqual(subscription.costPerYear, 12_000, accuracy: 0.001)
        XCTAssertEqual(subscription.costPerMonth, 1_000, accuracy: 0.001)
    }

    func testEveryThreeMonthsCostsAFourthOfTheYear() throws {
        let subscription = makeSubscription(amount: 3_000, interval: 3, first: try date(2026, 1, 15))
        XCTAssertEqual(subscription.costPerYear, 12_000, accuracy: 0.001)
        XCTAssertEqual(subscription.costPerMonth, 1_000, accuracy: 0.001)
    }

    func testEveryTwoWeeksCostsHalfOfWeekly() throws {
        let subscription = makeSubscription(amount: 100, period: .weekly, interval: 2, first: try date(2026, 1, 5))
        XCTAssertEqual(subscription.costPerYear, 2_600, accuracy: 0.001)
    }

    func testIntervalBelowOneCountsAsEveryPeriod() throws {
        let subscription = makeSubscription(amount: 500, interval: 0, first: try date(2026, 1, 5))
        XCTAssertEqual(subscription.effectiveInterval, 1)
        XCTAssertEqual(subscription.costPerYear, 6_000, accuracy: 0.001)
    }

    func testTotalsConvertEachCurrencyAndCountOnlyActive() throws {
        let first = try date(2026, 10, 5)
        let subscriptions = [
            makeSubscription(amount: 1_000, first: first),
            makeSubscription(amount: 10, currency: .usd, first: first),
            makeSubscription(amount: 12_000, period: .yearly, first: first),
            makeSubscription(amount: 5_000, first: first, status: .paused),
            makeSubscription(amount: 7_000, first: first, status: .archived)
        ]
        // Условный курс: 1 доллар — 400 драмов
        let totals = SubscriptionTotals(subscriptions) { amount, currency in
            currency == .usd ? amount * 400 : amount
        }
        XCTAssertEqual(totals.count, 3)
        XCTAssertEqual(totals.perMonth, 1_000 + 4_000 + 1_000, accuracy: 0.001)
        XCTAssertEqual(totals.perYear, 12_000 + 48_000 + 12_000, accuracy: 0.001)
    }

    func testTotalsOfNothingAreZero() {
        let totals = SubscriptionTotals([]) { amount, _ in amount }
        XCTAssertEqual(totals, SubscriptionTotals([]) { amount, _ in amount })
        XCTAssertEqual(totals.perMonth, 0)
        XCTAssertEqual(totals.perYear, 0)
        XCTAssertEqual(totals.count, 0)
    }

    func testYearlyTotalIsTwelveMonthlyTotals() throws {
        let first = try date(2026, 10, 5)
        let subscriptions = [
            makeSubscription(amount: 1_234, first: first),
            makeSubscription(amount: 99, period: .weekly, first: first),
            makeSubscription(amount: 5_000, period: .yearly, first: first)
        ]
        let totals = SubscriptionTotals(subscriptions) { amount, _ in amount }
        XCTAssertEqual(totals.perYear, totals.perMonth * 12, accuracy: 0.001)
    }

    func testCurrencyFormattingKeepsOwnSymbol() {
        XCTAssertEqual(AppCurrency.amd.formatAmount(4_500), "4 500 ֏")
        XCTAssertEqual(AppCurrency.rub.formatAmount(300), "300 ₽")
        XCTAssertEqual(AppCurrency.usd.formatAmount(12), "$12")
        XCTAssertEqual(AppCurrency.eur.formatAmount(5), "5 €")
    }

    // MARK: - Ближайшее списание

    func testNextChargeIsTheFirstDateWhileItIsInTheFuture() throws {
        let subscription = makeSubscription(first: try date(2026, 11, 5))
        XCTAssertEqual(subscription.nextChargeDate(now: try now(), calendar: calendar), try date(2026, 11, 5))
    }

    func testNextChargeTodayIsStillUpcoming() throws {
        let subscription = makeSubscription(first: try date(2026, 10, 26))
        XCTAssertEqual(subscription.nextChargeDate(now: try now(), calendar: calendar), try date(2026, 10, 26))
        XCTAssertEqual(subscription.daysUntilNextCharge(now: try now(), calendar: calendar), 0)
    }

    func testChargeWithATimeOfDayEarlierThanNowIsStillToday() throws {
        // Дата списания записана в 03:00, сейчас 08:00 того же дня: списание сегодняшнее, а не прошедшее
        let subscription = makeSubscription(first: try date(2026, 10, 26, hour: 3))
        XCTAssertEqual(subscription.daysUntilNextCharge(now: try now(), calendar: calendar), 0)
    }

    func testNextChargeMovesToTheNextMonthAfterThePast() throws {
        let subscription = makeSubscription(first: try date(2026, 8, 5))
        XCTAssertEqual(subscription.nextChargeDate(now: try now(), calendar: calendar), try date(2026, 11, 5))
        XCTAssertEqual(subscription.daysUntilNextCharge(now: try now(), calendar: calendar), 10)
    }

    func testNextChargeDoesNotDriftAfterAShortMonth() throws {
        // Первое списание 31 января: в феврале 28-е, но в марте снова 31-е, а не 28-е
        let subscription = makeSubscription(first: try date(2026, 1, 31))
        XCTAssertEqual(subscription.nextChargeDate(now: try date(2026, 2, 15), calendar: calendar), try date(2026, 2, 28))
        XCTAssertEqual(subscription.nextChargeDate(now: try date(2026, 3, 1), calendar: calendar), try date(2026, 3, 31))
    }

    func testWeeklyNextChargeKeepsTheWeekday() throws {
        // 5 октября 2026 — понедельник; 26 октября — тоже понедельник, ровно через три недели
        let subscription = makeSubscription(period: .weekly, first: try date(2026, 10, 5))
        XCTAssertEqual(subscription.nextChargeDate(now: try now(), calendar: calendar), try date(2026, 10, 26))
        XCTAssertEqual(subscription.nextChargeDate(now: try date(2026, 10, 27), calendar: calendar), try date(2026, 11, 2))
    }

    func testYearlyNextCharge() throws {
        let subscription = makeSubscription(period: .yearly, first: try date(2025, 3, 10))
        XCTAssertEqual(subscription.nextChargeDate(now: try now(), calendar: calendar), try date(2027, 3, 10))
        XCTAssertEqual(subscription.nextChargeDate(now: try date(2026, 3, 10), calendar: calendar), try date(2026, 3, 10))
    }

    func testEveryThreeMonthsNextCharge() throws {
        let subscription = makeSubscription(interval: 3, first: try date(2026, 1, 15))
        XCTAssertEqual(subscription.nextChargeDate(now: try date(2026, 2, 1), calendar: calendar), try date(2026, 4, 15))
        XCTAssertEqual(subscription.nextChargeDate(now: try date(2026, 4, 16), calendar: calendar), try date(2026, 7, 15))
    }

    func testVeryOldFirstDateStillFindsTheNextWeeklyCharge() throws {
        // Первое списание двадцать лет назад: ответ находится прыжком, а не перебором всех недель, и попадает в тот же день недели
        let first = try date(2005, 1, 3)
        let subscription = makeSubscription(period: .weekly, first: first)
        let today = try date(2026, 11, 13)
        let next = try XCTUnwrap(subscription.nextChargeDate(now: today, calendar: calendar))
        XCTAssertGreaterThanOrEqual(next, today)
        XCTAssertLessThan(next, try date(2026, 11, 20))
        let days = calendar.dateComponents([.day], from: first, to: next).day ?? 0
        XCTAssertEqual(days % 7, 0)
    }

    func testUpcomingChargesFollowTheFirstDate() throws {
        let subscription = makeSubscription(first: try date(2026, 1, 31))
        let dates = subscription.upcomingChargeDates(count: 3, now: try date(2026, 1, 1), calendar: calendar)
        XCTAssertEqual(dates, [try date(2026, 1, 31), try date(2026, 2, 28), try date(2026, 3, 31)])
        XCTAssertTrue(subscription.upcomingChargeDates(count: 0, now: try now(), calendar: calendar).isEmpty)
    }

    func testPausedAndArchivedSubscriptionsHaveNoNextCharge() throws {
        let first = try date(2026, 11, 5)
        for status in [SubscriptionStatus.paused, .archived] {
            let subscription = makeSubscription(first: first, status: status)
            XCTAssertNil(subscription.nextChargeDate(now: try now(), calendar: calendar))
            XCTAssertNil(subscription.daysUntilNextCharge(now: try now(), calendar: calendar))
            // Дата для формы правки остаётся
            XCTAssertEqual(subscription.nextOccurrence(now: try now(), calendar: calendar), first)
        }
    }

    // MARK: - Порядок в списке

    func testListOrderActiveByNextChargeThenPausedThenArchived() throws {
        let later = makeSubscription(name: "Б", first: try date(2026, 11, 20))
        let sooner = makeSubscription(name: "Я", first: try date(2026, 10, 28))
        let paused = makeSubscription(name: "А", first: try date(2026, 10, 27), status: .paused)
        let archived = makeSubscription(name: "В", first: try date(2026, 10, 27), status: .archived)

        let sorted = AppSubscription.sortedForList([archived, later, paused, sooner], now: try now(), calendar: calendar)
        XCTAssertEqual(sorted.map(\.name), ["Я", "Б", "А", "В"])
    }

    func testListOrderTiesGoByName() throws {
        let first = try date(2026, 11, 5)
        let b = makeSubscription(name: "Бета", first: first)
        let a = makeSubscription(name: "Альфа", first: first)
        let sorted = AppSubscription.sortedForList([b, a], now: try now(), calendar: calendar)
        XCTAssertEqual(sorted.map(\.name), ["Альфа", "Бета"])
    }

    func testListOrderSurvivesDuplicateIdentifiers() throws {
        let first = try date(2026, 11, 5)
        let one = makeSubscription(name: "Один", first: first)
        let two = AppSubscription(id: one.id, name: "Два", amount: 1_000, firstChargeDate: first)
        XCTAssertEqual(AppSubscription.sortedForList([one, two], now: try now(), calendar: calendar).count, 2)
    }

    // MARK: - Хранение

    func testEncodingRoundTripKeepsEverything() throws {
        let cardID = UUID()
        let original = AppSubscription(
            name: "Музыка", amount: 9.99, currency: .usd, period: .yearly, interval: 2,
            firstChargeDate: Date(timeIntervalSince1970: 1_800_000_000), category: .music, status: .paused,
            reminder: .threeDaysBefore, cardId: cardID, note: "Семейный тариф", createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AppSubscription.self, from: try encoder.encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testDecodingOnlyRequiredFieldsUsesDefaults() throws {
        let id = UUID()
        let json = """
        {"id": "\(id.uuidString)", "name": "Облако", "amount": 990, "firstChargeDate": "2026-11-05T00:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let subscription = try decoder.decode(AppSubscription.self, from: Data(json.utf8))
        XCTAssertEqual(subscription.id, id)
        XCTAssertEqual(subscription.currency, .amd)
        XCTAssertEqual(subscription.period, .monthly)
        XCTAssertEqual(subscription.category, .other)
        XCTAssertEqual(subscription.status, .active)
        XCTAssertNil(subscription.reminder)
        XCTAssertEqual(subscription.effectiveReminder, .dayBefore)
        XCTAssertNil(subscription.cardId)
        XCTAssertNil(subscription.interval)
    }

    func testUnknownValuesFromANewerVersionDoNotBreakReading() throws {
        let json = """
        [{"id": "\(UUID().uuidString)", "name": "Новая", "amount": 1, "firstChargeDate": "2026-11-05T00:00:00Z",
          "currency": "GBP", "period": "decade", "category": "space", "status": "frozen", "reminder": "monthBefore"},
         {"id": "\(UUID().uuidString)", "name": "Обычная", "amount": 2, "firstChargeDate": "2026-11-05T00:00:00Z"}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let list = try decoder.decode([AppSubscription].self, from: Data(json.utf8))
        XCTAssertEqual(list.map(\.name), ["Новая", "Обычная"])
        XCTAssertEqual(list[0].currency, .amd)
        XCTAssertEqual(list[0].period, .monthly)
        XCTAssertEqual(list[0].status, .active)
        XCTAssertNil(list[0].reminder)
    }

    func testServiceAddUpdateStatusAndDelete() throws {
        let subscription = makeSubscription(name: "Кино", amount: 2_000, first: try date(2026, 11, 5))
        service.addSubscription(subscription)
        XCTAssertEqual(service.subscriptions.count, 1)
        XCTAssertNotNil(service.subscriptions.first?.createdAt, "дата добавления проставляется сама")

        var edited = subscription
        edited.amount = 2_500
        edited.name = "Кино HD"
        service.updateSubscription(edited)
        XCTAssertEqual(service.subscriptions.first?.amount, 2_500)
        XCTAssertEqual(service.subscriptions.first?.name, "Кино HD")
        XCTAssertNotNil(service.subscriptions.first?.createdAt, "правка не стирает дату добавления")

        service.setSubscriptionStatus(id: subscription.id, status: .paused)
        XCTAssertEqual(service.subscriptions.first?.status, .paused)
        service.setSubscriptionStatus(id: subscription.id, status: .archived)
        XCTAssertEqual(service.subscriptions.first?.status, .archived)
        service.setSubscriptionStatus(id: subscription.id, status: .active)
        XCTAssertEqual(service.subscriptions.first?.status, .active)

        service.setSubscriptionReminder(id: subscription.id, reminder: .off)
        XCTAssertEqual(service.subscriptions.first?.reminder, DebtReminder.off)

        service.deleteSubscription(id: subscription.id)
        XCTAssertTrue(service.subscriptions.isEmpty)
    }

    func testUpdatingAnUnknownSubscriptionChangesNothing() throws {
        service.addSubscription(makeSubscription(name: "Кино", first: try date(2026, 11, 5)))
        service.updateSubscription(makeSubscription(name: "Чужая", first: try date(2026, 11, 5)))
        service.setSubscriptionStatus(id: UUID(), status: .archived)
        XCTAssertEqual(service.subscriptions.map(\.name), ["Кино"])
        XCTAssertEqual(service.subscriptions.first?.status, .active)
    }

    func testNewSubscriptionGoesFirst() throws {
        service.addSubscription(makeSubscription(name: "Первая", first: try date(2026, 11, 5)))
        service.addSubscription(makeSubscription(name: "Вторая", first: try date(2026, 11, 6)))
        XCTAssertEqual(service.subscriptions.map(\.name), ["Вторая", "Первая"])
    }

    func testSubscriptionsAreSavedToDisk() throws {
        let subscription = AppSubscription(
            name: "Облако", amount: 3.99, currency: .usd, period: .monthly,
            firstChargeDate: Date(timeIntervalSince1970: 1_800_000_000), category: .cloud
        )
        service.addSubscription(subscription)

        let reloaded = FinanceService()
        let saved = try XCTUnwrap(reloaded.subscriptions.first)
        XCTAssertEqual(reloaded.subscriptions.count, 1)
        XCTAssertEqual(saved.id, subscription.id)
        XCTAssertEqual(saved.name, "Облако")
        XCTAssertEqual(saved.amount, 3.99, accuracy: 0.0001)
        XCTAssertEqual(saved.currency, .usd)
        XCTAssertEqual(saved.category, .cloud)
        XCTAssertEqual(saved.firstChargeDate, subscription.firstChargeDate)
    }

    func testMissingFileMeansNoSubscriptionsAndOtherDataStays() throws {
        // Так выглядит телефон после обновления: файла подписок нет, а долги на месте
        service.addDebt(Debt(name: "Арам", amount: 5_000, isLent: true))
        service.addSubscription(makeSubscription(first: try date(2026, 11, 5)))
        try removeSubscriptionsFile()

        let reloaded = FinanceService()
        XCTAssertTrue(reloaded.subscriptions.isEmpty)
        XCTAssertEqual(reloaded.debts.map(\.name), ["Арам"])
        XCTAssertTrue(reloaded.isFullyLoaded)
    }

    func testUnreadableFileIsKeptAsBackupAndDoesNotBreakOtherStores() throws {
        service.addDebt(Debt(name: "Арам", amount: 5_000, isLent: true))
        let url = try subscriptionsFileURL()
        try Data("это не json".utf8).write(to: url)
        defer { removeBackups() }

        let reloaded = FinanceService()
        XCTAssertTrue(reloaded.subscriptions.isEmpty)
        XCTAssertEqual(reloaded.debts.map(\.name), ["Арам"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "испорченный файл переехал в резервную копию")
        XCTAssertFalse(backupFiles().isEmpty)
    }

    func testResetRemovesSubscriptions() throws {
        service.addSubscription(makeSubscription(first: try date(2026, 11, 5)))
        service.resetAllData()
        XCTAssertTrue(service.subscriptions.isEmpty)
        XCTAssertTrue(FinanceService().subscriptions.isEmpty)
    }

    func testDeletingCardClearsItFromSubscriptionsButKeepsThem() throws {
        let card = Card(last4: "4242", holderName: "TEST", balance: 1_000, colorHex: "#2A2B30", gradientColors: ["#2A2B30"])
        service.addCard(card, number: "")
        var withCard = makeSubscription(name: "С картой", first: try date(2026, 11, 5))
        withCard.cardId = card.id
        let without = makeSubscription(name: "Без карты", first: try date(2026, 11, 6))
        service.addSubscription(withCard)
        service.addSubscription(without)

        service.deleteCard(id: card.id)
        XCTAssertEqual(service.subscriptions.count, 2)
        XCTAssertTrue(service.subscriptions.allSatisfy { $0.cardId == nil })
    }

    private func documentsURL() throws -> URL {
        try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
    }

    private func subscriptionsFileURL() throws -> URL {
        try documentsURL().appendingPathComponent("subscriptions.json")
    }

    private func removeSubscriptionsFile() throws {
        let url = try subscriptionsFileURL()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func backupFiles() -> [URL] {
        guard let directory = try? documentsURL(),
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names
            .filter { $0.hasPrefix("subscriptions.corrupt-") }
            .map { directory.appendingPathComponent($0) }
    }

    private func removeBackups() {
        for url in backupFiles() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Напоминания

    private func plan(_ subscriptions: [AppSubscription], settings: ReminderSettings = ReminderSettings()) throws -> [ReminderSpec] {
        ReminderPlanner.specs(
            debts: [],
            goals: [],
            cards: [],
            subscriptions: subscriptions,
            transactions: [],
            reviewCount: 0,
            snoozes: [:],
            settings: settings,
            now: try now(),
            calendar: calendar
        )
    }

    func testSubscriptionRemindsADayBeforeEachUpcomingCharge() throws {
        // Списание 5-го числа каждого месяца, напоминание по умолчанию — за день, в 10:00
        let subscription = makeSubscription(first: try date(2026, 11, 5))
        let specs = try plan([subscription])

        XCTAssertEqual(specs.map(\.fireDate), [
            try date(2026, 11, 4, hour: 10),
            try date(2026, 12, 4, hour: 10),
            try date(2027, 1, 4, hour: 10)
        ])
        XCTAssertTrue(specs.allSatisfy { $0.category == ReminderID.subscriptionCategory })
        XCTAssertTrue(specs.allSatisfy { $0.target == .subscription(subscription.id) })
        XCTAssertTrue(specs.allSatisfy { $0.id.hasPrefix(ReminderID.prefix) })
        XCTAssertEqual(Set(specs.map(\.id)).count, specs.count, "у напоминаний одной подписки разные идентификаторы")
    }

    func testReminderOnTheChargeDayHasItsOwnTitle() throws {
        let soon = try XCTUnwrap(try plan([makeSubscription(first: try date(2026, 11, 5), reminder: .dayBefore)]).first)
        let today = try XCTUnwrap(try plan([makeSubscription(first: try date(2026, 11, 5), reminder: .onDueDay)]).first)
        XCTAssertEqual(today.fireDate, try date(2026, 11, 5, hour: 10))
        XCTAssertNotEqual(soon.title, today.title)
        XCTAssertTrue(soon.body.contains("Кино"))
        XCTAssertTrue(today.body.contains("Кино"))
    }

    func testReminderThreeDaysBeforeSkipsAMomentThatHasPassed() throws {
        // Списание завтра, а напоминание за три дня: время уже прошло, остаются следующие списания
        let subscription = makeSubscription(first: try date(2026, 10, 27), reminder: .threeDaysBefore)
        let specs = try plan([subscription])
        XCTAssertEqual(specs.first?.fireDate, try date(2026, 11, 24, hour: 10))
        let current = try now()
        XCTAssertTrue(specs.allSatisfy { ($0.fireDate ?? .distantPast) > current })
    }

    func testPausedArchivedAndSilencedSubscriptionsHaveNoReminders() throws {
        let first = try date(2026, 11, 5)
        let paused = makeSubscription(first: first, status: .paused)
        let archived = makeSubscription(first: first, status: .archived)
        let silenced = makeSubscription(first: first, reminder: .off)
        XCTAssertTrue(try plan([paused, archived, silenced]).isEmpty)
    }

    func testSubscriptionRemindersCanBeSwitchedOffAsAWhole() throws {
        var settings = ReminderSettings()
        settings.subscriptions = false
        XCTAssertTrue(try plan([makeSubscription(first: try date(2026, 11, 5))], settings: settings).isEmpty)
        XCTAssertTrue(ReminderSettings().subscriptions, "по умолчанию напоминания о подписках включены")
    }

    func testReminderCountDependsOnThePeriod() throws {
        let first = try date(2026, 10, 27)
        XCTAssertEqual(try plan([makeSubscription(period: .weekly, first: first)]).count, 4)
        XCTAssertEqual(try plan([makeSubscription(period: .monthly, first: first)]).count, 3)
        XCTAssertEqual(try plan([makeSubscription(period: .yearly, first: first)]).count, 1)
    }

    func testSubscriptionReminderTargetRoundTripsAndOpensDebts() {
        let id = UUID()
        XCTAssertEqual(ReminderTarget(raw: ReminderTarget.subscription(id).raw), .subscription(id))
        XCTAssertEqual(ReminderTarget.subscription(id).tab, .debts)
        XCTAssertNil(ReminderTarget(raw: "subscription:не-uuid"))
    }

    func testSubscriptionCategoryIsRegisteredWithNotifications() {
        let identifiers = ReminderService.notificationCategories().map(\.identifier)
        XCTAssertTrue(identifiers.contains(ReminderID.subscriptionCategory))
    }

    // MARK: - Вкладка и переводы

    func testSubscriptionsTabHoldsNoDebts() {
        XCTAssertTrue(DebtTab.allCases.contains(.subscriptions))
        XCTAssertEqual(DebtTab.allCases.count, 4)
        for debt in [
            Debt(name: "Арам", amount: 1, isLent: true),
            Debt(name: "Банк", amount: 1, isLent: false, type: .credit),
            Debt(name: "Интернет", amount: 1, isLent: false, type: .bill, billKind: .subscription, repeatRule: .monthly)
        ] {
            XCTAssertFalse(DebtTab.subscriptions.contains(debt))
            XCTAssertEqual(DebtTab.allCases.filter { $0.contains(debt) }.count, 1)
        }
    }

    func testNewTitlesAreTranslatedIntoEnglishAndArmenian() throws {
        let keys = [
            "tab_subscriptions", "Год", "На паузе", "В архиве", "Видео", "Музыка", "Облако", "Приложения", "Чтение",
            "Обучение", "Спорт", "Списание сегодня", "Списание завтра", "Списание через %lld дн.", "Списание %@",
            "Сегодня списание за подписку", "Скоро списание за подписку", "%@ · %@ · спишется %@", "≈ %@ в год",
            "Валюта", "Подписка", "Период", "Списание", "Ближайшее списание", "Следующее списание: %@", "Карта списания",
            "Не указана", "Новая подписка", "Изменить подписку", "Добавить подписку", "В месяц", "В год", "Пауза",
            "Возобновить", "В архив"
        ]
        for language in [AppLanguage.english, .armenian] {
            for key in keys {
                XCTAssertNotEqual(language.string(key), key, "[\(language.rawValue)] нет перевода: \(key)")
            }
        }
        XCTAssertEqual(AppLanguage.russian.string("tab_subscriptions"), "Подписки")
        XCTAssertEqual(AppLanguage.english.string("tab_subscriptions"), "Subscriptions")
    }

    func testEveryCategoryAndPeriodHasATitleAndSymbol() {
        for category in SubscriptionCategory.allCases {
            XCTAssertFalse(category.title.isEmpty)
            XCTAssertFalse(category.icon.isEmpty)
        }
        for period in SubscriptionPeriod.allCases {
            XCTAssertFalse(period.title.isEmpty)
            XCTAssertNotEqual(period.repeatRule, .never)
        }
        for status in SubscriptionStatus.allCases {
            XCTAssertFalse(status.title.isEmpty)
        }
    }
}
