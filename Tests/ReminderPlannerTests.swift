import XCTest
@testable import SamFinance

/// Расписание напоминаний: долги, копилки, карты и вечернее «запишите траты». Проверяется план без уведомлений iOS.
@MainActor
final class ReminderPlannerTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    /// 26 октября 2026, 08:00 — раньше времени напоминаний (10:00)
    private func now() throws -> Date {
        try date(2026, 10, 26, hour: 8)
    }

    private func plan(
        debts: [Debt] = [],
        goals: [Goal] = [],
        cards: [Card] = [],
        transactions: [Transaction] = [],
        snoozes: [UUID: Date] = [:],
        settings: ReminderSettings = ReminderSettings()
    ) throws -> [ReminderSpec] {
        ReminderPlanner.specs(
            debts: debts,
            goals: goals,
            cards: cards,
            transactions: transactions,
            reviewCount: 0,
            snoozes: snoozes,
            settings: settings,
            now: try now(),
            calendar: calendar
        )
    }

    private func makeGoal(target: Double = 100_000, saved: Double = 0, deadline: Date?) -> Goal {
        Goal(
            title: "Отпуск", targetAmount: target, currentAmount: saved,
            colorHex: "#C6F432", gradientColors: ["#C6F432", "#B2E01E"],
            deadline: deadline, createdAt: nil
        )
    }

    // MARK: - Долги

    func testDebtGetsAdvanceDueAndOverdueReminders() throws {
        let debt = Debt(name: "Арам", amount: 20_000, dueDate: try date(2026, 10, 30), isLent: false, type: .person, reminder: .threeDaysBefore)
        let specs = try plan(debts: [debt])

        XCTAssertEqual(specs.map(\.fireDate), [
            try date(2026, 10, 27, hour: 10),
            try date(2026, 10, 30, hour: 10),
            try date(2026, 10, 31, hour: 10),
            try date(2026, 11, 6, hour: 10)
        ])
        XCTAssertTrue(specs.allSatisfy { $0.category == ReminderID.debtCategory && $0.target == .debt(debt.id) })
        XCTAssertTrue(specs.allSatisfy { $0.id.hasPrefix(ReminderID.prefix) })
        XCTAssertEqual(Set(specs.map(\.id)).count, specs.count, "у напоминаний одного долга разные идентификаторы")
    }

    func testOldDebtWithoutChoiceRemindsADayBefore() throws {
        let debt = Debt(name: "Банк", amount: 50_000, dueDate: try date(2026, 10, 30), isLent: false, type: .credit)
        XCTAssertNil(debt.reminder)
        XCTAssertEqual(debt.effectiveReminder, .dayBefore)
        XCTAssertEqual(try plan(debts: [debt]).first?.fireDate, try date(2026, 10, 29, hour: 10))
    }

    func testPaidOrSilencedDebtHasNoReminders() throws {
        let paid = Debt(name: "Арам", amount: 1_000, dueDate: try date(2026, 10, 30), isLent: true, isPaid: true)
        let silenced = Debt(name: "Ани", amount: 1_000, dueDate: try date(2026, 10, 30), isLent: true, reminder: .off)
        XCTAssertTrue(try plan(debts: [paid, silenced]).isEmpty)

        var settings = ReminderSettings()
        settings.debts = false
        let active = Debt(name: "Арам", amount: 1_000, dueDate: try date(2026, 10, 30), isLent: true)
        XCTAssertTrue(try plan(debts: [active], settings: settings).isEmpty)
    }

    func testPastDeadlineKeepsOnlyFutureOverdueReminders() throws {
        // Срок был позавчера: напоминание «на следующий день» уже прошло, остаётся только через неделю
        let debt = Debt(name: "Арам", amount: 5_000, dueDate: try date(2026, 10, 24), isLent: true, reminder: .weekBefore)
        XCTAssertEqual(try plan(debts: [debt]).map(\.fireDate), [try date(2026, 10, 31, hour: 10)])
    }

    func testDirectionChangesTheTitle() throws {
        let due = try date(2026, 10, 30)
        let credit = Debt(name: "Банк", amount: 1, dueDate: due, isLent: false, type: .credit, reminder: .onDueDay)
        let lent = Debt(name: "Арам", amount: 1, dueDate: due, isLent: true, type: .person, reminder: .onDueDay)
        let borrowed = Debt(name: "Ани", amount: 1, dueDate: due, isLent: false, type: .person, reminder: .onDueDay)

        let titles = try [credit, lent, borrowed].map { try XCTUnwrap(try plan(debts: [$0]).first?.title) }
        XCTAssertEqual(titles[0], String(localized: "Сегодня платёж по кредиту"))
        XCTAssertEqual(titles[1], String(localized: "Сегодня вам должны вернуть долг"))
        XCTAssertEqual(titles[2], String(localized: "Сегодня вернуть долг"))
    }

    func testSnoozeAddsOneMoreReminder() throws {
        let debt = Debt(name: "Арам", amount: 5_000, dueDate: try date(2026, 10, 30), isLent: false, reminder: .onDueDay)
        let snooze = try date(2026, 10, 27, hour: 10)
        let specs = try plan(debts: [debt], snoozes: [debt.id: snooze])
        XCTAssertEqual(specs.first?.fireDate, snooze)
        XCTAssertTrue(specs.first?.id.hasSuffix(".snooze") ?? false)
        XCTAssertEqual(specs.count, 4)
    }

    // MARK: - Копилки

    func testGoalDeadlineRemindsAWeekADayAndOnTheDay() throws {
        let goal = makeGoal(saved: 40_000, deadline: try date(2026, 11, 20))
        let specs = try plan(goals: [goal])
        XCTAssertEqual(specs.map(\.fireDate), [
            try date(2026, 11, 13, hour: 10),
            try date(2026, 11, 19, hour: 10),
            try date(2026, 11, 20, hour: 10)
        ])
        XCTAssertTrue(specs.allSatisfy { $0.target == .goal(goal.id) })
    }

    func testCompletedGoalOrGoalWithoutDeadlineIsQuiet() throws {
        let done = makeGoal(target: 10_000, saved: 10_000, deadline: try date(2026, 11, 20))
        let open = makeGoal(deadline: nil)
        XCTAssertTrue(try plan(goals: [done, open]).isEmpty)
    }

    func testSavingReminderRepeatsWeeklyOrMonthly() throws {
        let goal = makeGoal(deadline: try date(2027, 4, 26))
        var settings = ReminderSettings()
        settings.goalDeadlines = false

        settings.goalSaving = .weekly
        let weekly = try XCTUnwrap(try plan(goals: [goal], settings: settings).first)
        XCTAssertNil(weekly.fireDate)
        XCTAssertEqual(weekly.repeating?.weekday, 1)
        XCTAssertEqual(weekly.repeating?.hour, 10)
        XCTAssertEqual(weekly.target, .savings)
        XCTAssertTrue(weekly.body.contains("Отпуск"))

        settings.goalSaving = .monthly
        let monthly = try XCTUnwrap(try plan(goals: [goal], settings: settings).first)
        XCTAssertEqual(monthly.repeating?.day, 1)
        XCTAssertNil(monthly.repeating?.weekday)

        settings.goalSaving = .off
        XCTAssertTrue(try plan(goals: [goal], settings: settings).isEmpty)
    }

    // MARK: - Карты

    func testCardExpiryIsTheLastDayOfTheMonth() throws {
        let card = Card(last4: "0640", holderName: "SAMVEL", balance: 0, colorHex: "#000000", gradientColors: [], expiryDate: "02/28")
        XCTAssertEqual(ReminderPlanner.expiryDay(of: card, calendar: calendar), try date(2028, 2, 29, hour: 0))

        let unknown = Card(last4: "1111", holderName: "SAMVEL", balance: 0, colorHex: "#000000", gradientColors: [], expiryDate: "—")
        XCTAssertNil(ReminderPlanner.expiryDay(of: unknown, calendar: calendar))
    }

    func testCardRemindsAMonthAheadAndOnTheLastDay() throws {
        let card = Card(last4: "0640", holderName: "SAMVEL", balance: 0, colorHex: "#000000", gradientColors: [], expiryDate: "11/26")
        let specs = try plan(cards: [card])
        XCTAssertEqual(specs.map(\.fireDate), [try date(2026, 10, 31, hour: 10), try date(2026, 11, 30, hour: 10)])
        XCTAssertTrue(specs.allSatisfy { $0.target == .card(card.id) })
    }

    // MARK: - Учёт

    func testDailyLogSkipsTodayWhenSomethingIsLogged() throws {
        var settings = ReminderSettings()
        settings.dailyLog = true
        XCTAssertEqual(try plan(settings: settings).count, 14)

        let category = try XCTUnwrap(AppCategory.defaultCategories.first { $0.type == .expense })
        let today = Transaction(title: "Кофе", amount: 1_500, type: .expense, category: category, date: try now())
        let specs = try plan(transactions: [today], settings: settings)
        XCTAssertEqual(specs.count, 13)
        XCTAssertEqual(specs.first?.fireDate, try date(2026, 10, 27, hour: 21))
    }

    // MARK: - Общее

    func testNearestRemindersFitTheLimit() throws {
        let debts = try (0..<30).map { index in
            Debt(name: "Долг \(index)", amount: 1_000, dueDate: try date(2026, 11, 1 + index % 28), isLent: false, reminder: .weekBefore)
        }
        let specs = try plan(debts: debts)
        XCTAssertEqual(specs.count, ReminderPlanner.limit)
        let dates = specs.compactMap(\.fireDate)
        XCTAssertEqual(dates, dates.sorted())
    }

    func testTargetSurvivesTheRoundTripAndOpensItsTab() {
        let id = UUID()
        for target in [ReminderTarget.debt(id), .goal(id), .card(id), .savings, .overview] {
            XCTAssertEqual(ReminderTarget(raw: target.raw), target)
        }
        XCTAssertEqual(ReminderTarget.debt(id).tab, .debts)
        XCTAssertEqual(ReminderTarget.goal(id).tab, .cards)
        XCTAssertEqual(ReminderTarget.overview.tab, .overview)
        XCTAssertNil(ReminderTarget(raw: "debt:не-uuid"))
    }

    func testOldDebtFilesStillDecode() throws {
        let json = #"[{"id":"5A3F1C00-0000-4000-8000-000000000001","name":"Арам","amount":1000,"dueDate":"2026-10-30T12:00:00Z","isLent":true,"isPaid":false,"type":"person"}]"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let debts = try decoder.decode([Debt].self, from: Data(json.utf8))
        XCTAssertNil(debts.first?.reminder)
        XCTAssertEqual(debts.first?.effectiveReminder, .standard)
    }
}
