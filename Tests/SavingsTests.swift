import XCTest
@testable import SamFinance

/// План копилки, итоги, быстрые суммы и значки: чистая логика без экрана
final class GoalPlanTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    private func offset(_ days: Int, from date: Date) throws -> Date {
        try XCTUnwrap(calendar.date(byAdding: .day, value: days, to: date))
    }

    private func makeGoal(
        target: Double = 100_000,
        saved: Double = 0,
        deadline: Date? = nil,
        createdAt: Date? = nil,
        entries: [GoalEntry] = []
    ) -> Goal {
        Goal(
            title: "Test", targetAmount: target, currentAmount: saved,
            colorHex: "#C6F432", gradientColors: ["#C6F432", "#B2E01E"],
            deadline: deadline, createdAt: createdAt, entries: entries
        )
    }

    func testCompletedGoalKeepsOverflow() {
        let plan = GoalPlan(goal: makeGoal(target: 100_000, saved: 120_000), calendar: calendar)
        XCTAssertEqual(plan.status, .completed)
        XCTAssertEqual(plan.progress, 1, accuracy: 0.0001)
        XCTAssertEqual(plan.remaining, 0, accuracy: 0.001)
        XCTAssertEqual(plan.overflow, 20_000, accuracy: 0.001)
        XCTAssertNil(plan.forecastDate)
    }

    func testGoalWithoutDeadline() {
        let plan = GoalPlan(goal: makeGoal(target: 100_000, saved: 25_000), calendar: calendar)
        XCTAssertEqual(plan.status, .noDeadline)
        XCTAssertEqual(plan.progress, 0.25, accuracy: 0.0001)
        XCTAssertEqual(plan.remaining, 75_000, accuracy: 0.001)
        XCTAssertNil(plan.daysLeft)
        XCTAssertNil(plan.perMonth)
        XCTAssertNil(plan.perWeek)
    }

    func testZeroTargetIsNeverCompleted() {
        let goal = makeGoal(target: 0, saved: 500)
        XCTAssertFalse(goal.isCompleted)
        let plan = GoalPlan(goal: goal, calendar: calendar)
        XCTAssertEqual(plan.progress, 0, accuracy: 0.0001)
        XCTAssertEqual(plan.remaining, 0, accuracy: 0.001)
    }

    func testOnTrackAndBehindAreComparedWithTheStraightLine() throws {
        let start = try day(2027, 1, 1)
        let deadline = try day(2027, 1, 31)
        let now = try day(2027, 1, 16)

        let ahead = makeGoal(saved: 50_000, deadline: deadline, createdAt: start)
        XCTAssertEqual(GoalPlan(goal: ahead, now: now, calendar: calendar).status, .onTrack)

        let behind = makeGoal(saved: 20_000, deadline: deadline, createdAt: start)
        XCTAssertEqual(GoalPlan(goal: behind, now: now, calendar: calendar).status, .behind)
    }

    func testNewGoalIsOnTrackOnTheFirstDay() throws {
        let now = try day(2027, 1, 1)
        let goal = makeGoal(saved: 0, deadline: try day(2027, 7, 1), createdAt: now)
        XCTAssertEqual(GoalPlan(goal: goal, now: now, calendar: calendar).status, .onTrack)
    }

    func testPastDeadlineIsOverdue() throws {
        let now = try day(2027, 3, 1)
        let goal = makeGoal(saved: 10_000, deadline: try day(2027, 2, 1), createdAt: try day(2027, 1, 1))
        let plan = GoalPlan(goal: goal, now: now, calendar: calendar)
        XCTAssertEqual(plan.status, .overdue)
        XCTAssertEqual(plan.daysLeft, 0)
        XCTAssertNil(plan.perMonth)
    }

    func testDeadlineToday() throws {
        let now = try day(2027, 3, 1)
        let goal = makeGoal(saved: 10_000, deadline: now, createdAt: try day(2027, 1, 1))
        let plan = GoalPlan(goal: goal, now: now, calendar: calendar)
        XCTAssertNotEqual(plan.status, .overdue)
        XCTAssertEqual(plan.daysLeft, 0)
    }

    func testAmountsToSetAside() throws {
        let now = try day(2027, 1, 1)
        let deadline = try offset(70, from: now)
        let plan = GoalPlan(goal: makeGoal(saved: 30_000, deadline: deadline, createdAt: now), now: now, calendar: calendar)
        XCTAssertEqual(plan.daysLeft, 70)
        XCTAssertEqual(try XCTUnwrap(plan.perWeek), 7_000, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(plan.perMonth), 70_000 / (70 / 30.4375), accuracy: 0.01)
    }

    func testShortDeadlineAsksForEverythingAtOnce() throws {
        let now = try day(2027, 1, 1)
        let plan = GoalPlan(goal: makeGoal(saved: 0, deadline: try offset(3, from: now), createdAt: now), now: now, calendar: calendar)
        XCTAssertEqual(try XCTUnwrap(plan.perWeek), 100_000, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(plan.perMonth), 100_000, accuracy: 0.01)
    }

    func testForecastFollowsTheRecentPace() throws {
        let now = try day(2027, 3, 1)
        let entries = [
            GoalEntry(date: try offset(-20, from: now), amount: 15_000),
            GoalEntry(date: try offset(-5, from: now), amount: 15_000)
        ]
        let goal = makeGoal(target: 100_000, saved: 90_000, createdAt: try offset(-30, from: now), entries: entries)
        let plan = GoalPlan(goal: goal, now: now, calendar: calendar)
        // 30 000 за 30 дней — 1 000 в день, до цели ещё 10 000
        let expected = try offset(10, from: calendar.startOfDay(for: now))
        XCTAssertEqual(plan.forecastDate, expected)
    }

    func testPaceIsNotCountedForLessThanTwoWeeks() throws {
        let now = try day(2027, 3, 1)
        let goal = makeGoal(
            target: 64_000, saved: 14_000, createdAt: try offset(-2, from: now),
            entries: [GoalEntry(date: try offset(-1, from: now), amount: 14_000)]
        )
        // Темп считается за 14 дней: 1 000 в день, до цели ещё 50 000
        let plan = GoalPlan(goal: goal, now: now, calendar: calendar)
        XCTAssertEqual(plan.forecastDate, try offset(50, from: calendar.startOfDay(for: now)))
    }

    func testNoForecastWithoutPositivePace() throws {
        let now = try day(2027, 3, 1)
        XCTAssertNil(GoalPlan(goal: makeGoal(saved: 10_000, createdAt: try offset(-30, from: now)), now: now, calendar: calendar).forecastDate)

        let spentBack = [
            GoalEntry(date: try offset(-10, from: now), amount: 10_000),
            GoalEntry(date: try offset(-3, from: now), amount: -10_000)
        ]
        let goal = makeGoal(saved: 0, createdAt: try offset(-30, from: now), entries: spentBack)
        XCTAssertNil(GoalPlan(goal: goal, now: now, calendar: calendar).forecastDate)
    }

    func testForecastBeyondTenYearsIsDropped() throws {
        let now = try day(2027, 3, 1)
        let goal = makeGoal(
            target: 1_000_000_000, saved: 10, createdAt: try offset(-1, from: now),
            entries: [GoalEntry(date: try offset(-1, from: now), amount: 10)]
        )
        XCTAssertNil(GoalPlan(goal: goal, now: now, calendar: calendar).forecastDate)
    }

    func testSummaryAndReservedAmounts() {
        let cardID = UUID()
        let active = Goal(cardId: cardID, title: "A", targetAmount: 100, currentAmount: 40, colorHex: "#C6F432", gradientColors: ["#C6F432"])
        let done = Goal(cardId: cardID, title: "B", targetAmount: 50, currentAmount: 50, colorHex: "#C6F432", gradientColors: ["#C6F432"])
        let other = Goal(cardId: UUID(), title: "C", targetAmount: 200, currentAmount: 60, colorHex: "#C6F432", gradientColors: ["#C6F432"])

        let summary = SavingsSummary(goals: [active, done, other])
        XCTAssertEqual(summary.totalSaved, 150, accuracy: 0.001)
        XCTAssertEqual(summary.activeSaved, 100, accuracy: 0.001)
        XCTAssertEqual(summary.activeTarget, 300, accuracy: 0.001)
        XCTAssertEqual(summary.activeCount, 2)
        XCTAssertEqual(summary.completedCount, 1)
        XCTAssertEqual(summary.progress, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(SavingsSummary.reserved(on: cardID, in: [active, done, other]), 90, accuracy: 0.001)
        XCTAssertEqual(SavingsSummary(goals: []).progress, 0, accuracy: 0.0001)
    }

    func testActiveGoalsAreSortedByDeadlineThenNewest() throws {
        let now = try day(2027, 1, 1)
        func goal(_ title: String, deadline: Date?, created: Date) -> Goal {
            Goal(title: title, targetAmount: 100, colorHex: "#C6F432", gradientColors: ["#C6F432"], deadline: deadline, createdAt: created)
        }
        let late = goal("late", deadline: try offset(90, from: now), created: now)
        let soon = goal("soon", deadline: try offset(10, from: now), created: now)
        let oldOpen = goal("oldOpen", deadline: nil, created: try offset(-20, from: now))
        let newOpen = goal("newOpen", deadline: nil, created: try offset(-1, from: now))
        let finished = Goal(title: "done", targetAmount: 10, currentAmount: 10, colorHex: "#C6F432", gradientColors: ["#C6F432"])

        let sorted = SavingsSummary.sortedActive([oldOpen, late, finished, newOpen, soon])
        XCTAssertEqual(sorted.map { $0.title }, ["soon", "late", "newOpen", "oldOpen"])
    }

    func testCompletedGoalsShowRecentFirst() throws {
        let now = try day(2027, 1, 1)
        func done(_ title: String, at date: Date?) -> Goal {
            Goal(title: title, targetAmount: 10, currentAmount: 10, colorHex: "#C6F432", gradientColors: ["#C6F432"], completedAt: date)
        }
        let list = SavingsSummary.completed([done("old", at: try offset(-30, from: now)), done("new", at: now), done("unknown", at: nil)])
        XCTAssertEqual(list.map { $0.title }, ["new", "old", "unknown"])
    }

    func testQuickAmountsAreRoundedShares() {
        XCTAssertEqual(GoalQuickAmounts.rounded(137_500), 140_000, accuracy: 0.001)
        XCTAssertEqual(GoalQuickAmounts.rounded(4_800), 4_800, accuracy: 0.001)
        XCTAssertEqual(GoalQuickAmounts.rounded(0), 0, accuracy: 0.001)
        XCTAssertEqual(GoalQuickAmounts.rounded(-5), 0, accuracy: 0.001)

        XCTAssertEqual(GoalQuickAmounts.deposit(target: 1_000_000, remaining: 1_000_000), [100_000, 250_000, 500_000])
        // Доли больше остатка не предлагаются
        XCTAssertEqual(GoalQuickAmounts.deposit(target: 1_000_000, remaining: 300_000), [100_000, 250_000])
        XCTAssertEqual(GoalQuickAmounts.withdraw(current: 200_000), [50_000, 100_000])
        XCTAssertTrue(GoalQuickAmounts.withdraw(current: 0).isEmpty)
    }

    func testAmountTextConversion() {
        XCTAssertEqual(GoalQuickAmounts.plain(5_000), "5000")
        XCTAssertEqual(GoalQuickAmounts.plain(12.5), "12.50")
        XCTAssertEqual(GoalQuickAmounts.parse("12,5"), 12.5)
        XCTAssertEqual(GoalQuickAmounts.parse(" 7000 "), 7_000)
        XCTAssertEqual(GoalQuickAmounts.parse("-5"), -5)
        XCTAssertNil(GoalQuickAmounts.parse("abc"))
        XCTAssertNil(GoalQuickAmounts.parse(""))
        XCTAssertNil(GoalQuickAmounts.parse("nan"))
        XCTAssertNil(GoalQuickAmounts.parse("inf"))
    }

    func testSymbolsAndIdeasAreComplete() {
        let titles = GoalSymbol.all.map { GoalSymbol.title($0) }
        XCTAssertEqual(Set(titles).count, titles.count)
        XCTAssertTrue(GoalSymbol.all.contains(GoalSymbol.fallback))

        XCTAssertEqual(Set(GoalIdea.all.map { $0.id }).count, GoalIdea.all.count)
        for idea in GoalIdea.all {
            XCTAssertFalse(idea.title.isEmpty)
            XCTAssertEqual(idea.colors.count, 2)
            XCTAssertTrue(GoalSymbol.all.contains(idea.symbol))
        }
    }

    func testOldGoalWithoutNewFieldsStillDecodes() throws {
        let json = """
        {"id":"5A3F1C00-0000-4000-8000-0000000000AA","title":"Trip","targetAmount":1000,"currentAmount":250,\
        "colorHex":"#C6F432","gradientColors":["#C6F432","#B2E01E"]}
        """
        let goal = try JSONDecoder().decode(Goal.self, from: Data(json.utf8))
        XCTAssertEqual(goal.title, "Trip")
        XCTAssertNil(goal.cardId)
        XCTAssertNil(goal.deadline)
        XCTAssertNil(goal.symbol)
        XCTAssertNil(goal.createdAt)
        XCTAssertNil(goal.completedAt)
        XCTAssertTrue(goal.entries.isEmpty)
    }

    func testGoalSurvivesEncodingRoundTrip() throws {
        let goal = Goal(
            cardId: UUID(), title: "Phone", targetAmount: 500_000, currentAmount: 120_000,
            colorHex: "#8E5CF7", gradientColors: ["#8E5CF7", "#4B2BB8"],
            deadline: Date(timeIntervalSince1970: 1_800_000_000), symbol: "iphone",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            entries: [GoalEntry(date: Date(timeIntervalSince1970: 1_750_000_000), amount: 120_000, note: "Salary")]
        )
        let decoded = try JSONDecoder().decode(Goal.self, from: try JSONEncoder().encode(goal))
        XCTAssertEqual(decoded, goal)
    }
}

/// Пополнение, снятие и правка копилок в сервисе
@MainActor
final class SavingsServiceTests: XCTestCase {
    private var service: FinanceService { FinanceService.shared }

    // Вызов super.setUp() здесь не нужен (он пустой) и не компилируется в Swift 6 для MainActor-классов
    override func setUp() async throws {
        service.resetAllData()
    }

    override func tearDown() async throws {
        service.resetAllData()
    }

    private func makeGoal(target: Double = 1_000, saved: Double = 0, cardId: UUID? = nil) -> Goal {
        Goal(cardId: cardId, title: "Trip", targetAmount: target, currentAmount: saved, colorHex: "#C6F432", gradientColors: ["#C6F432", "#B2E01E"])
    }

    private func stored(_ id: UUID) throws -> Goal {
        try XCTUnwrap(service.goals.first { $0.id == id })
    }

    func testNewGoalGetsCreationDate() throws {
        let goal = makeGoal()
        service.addGoal(goal)
        XCTAssertNotNil(try stored(goal.id).createdAt)
        XCTAssertNil(try stored(goal.id).completedAt)
    }

    func testGoalCreatedAlreadyFullIsCompleted() throws {
        let goal = makeGoal(target: 500, saved: 500)
        service.addGoal(goal)
        XCTAssertNotNil(try stored(goal.id).completedAt)
    }

    func testDepositAddsMoneyAndJournalEntry() throws {
        let goal = makeGoal()
        service.addGoal(goal)
        XCTAssertEqual(service.deposit(goalID: goal.id, amount: 250, note: "  Salary  "), .done)

        let saved = try stored(goal.id)
        XCTAssertEqual(saved.currentAmount, 250, accuracy: 0.001)
        XCTAssertEqual(saved.entries.count, 1)
        XCTAssertEqual(saved.entries.first?.amount, 250)
        XCTAssertEqual(saved.entries.first?.note, "Salary")
    }

    func testBlankNoteIsDropped() throws {
        let goal = makeGoal()
        service.addGoal(goal)
        service.deposit(goalID: goal.id, amount: 10, note: "   ")
        XCTAssertNil(try stored(goal.id).entries.first?.note)
    }

    func testWrongAmountsAreRejected() throws {
        let goal = makeGoal()
        service.addGoal(goal)
        XCTAssertEqual(service.deposit(goalID: goal.id, amount: 0), .rejected)
        XCTAssertEqual(service.deposit(goalID: goal.id, amount: -5), .rejected)
        XCTAssertEqual(service.deposit(goalID: goal.id, amount: .nan), .rejected)
        XCTAssertEqual(service.deposit(goalID: goal.id, amount: .infinity), .rejected)
        XCTAssertEqual(service.deposit(goalID: UUID(), amount: 10), .rejected)
        XCTAssertEqual(try stored(goal.id).currentAmount, 0, accuracy: 0.001)
        XCTAssertTrue(try stored(goal.id).entries.isEmpty)
    }

    func testReachingTheTargetIsReportedOnce() throws {
        let goal = makeGoal(target: 1_000, saved: 900)
        service.addGoal(goal)
        XCTAssertEqual(service.deposit(goalID: goal.id, amount: 100), .reachedTarget)
        XCTAssertNotNil(try stored(goal.id).completedAt)
        XCTAssertEqual(service.deposit(goalID: goal.id, amount: 50), .done)
        XCTAssertEqual(try stored(goal.id).currentAmount, 1_050, accuracy: 0.001)
    }

    func testWithdrawReducesTheGoalAndReopensIt() throws {
        let goal = makeGoal(target: 1_000, saved: 1_000)
        service.addGoal(goal)
        XCTAssertNotNil(try stored(goal.id).completedAt)

        XCTAssertEqual(service.withdraw(goalID: goal.id, amount: 300), .done)
        let saved = try stored(goal.id)
        XCTAssertEqual(saved.currentAmount, 700, accuracy: 0.001)
        XCTAssertNil(saved.completedAt)
        XCTAssertEqual(saved.entries.last?.amount, -300)
    }

    func testCannotWithdrawMoreThanSaved() throws {
        let goal = makeGoal(saved: 200)
        service.addGoal(goal)
        XCTAssertEqual(service.withdraw(goalID: goal.id, amount: 200.01), .rejected)
        XCTAssertEqual(service.withdraw(goalID: goal.id, amount: 0), .rejected)
        XCTAssertEqual(try stored(goal.id).currentAmount, 200, accuracy: 0.001)
        XCTAssertEqual(service.withdraw(goalID: goal.id, amount: 200), .done)
        XCTAssertEqual(try stored(goal.id).currentAmount, 0, accuracy: 0.001)
    }

    func testRemovingAnEntryRestoresTheAmount() throws {
        let goal = makeGoal(target: 1_000, saved: 100)
        service.addGoal(goal)
        service.deposit(goalID: goal.id, amount: 900)
        XCTAssertNotNil(try stored(goal.id).completedAt)

        let entry = try XCTUnwrap(try stored(goal.id).entries.first)
        service.removeGoalEntry(goalID: goal.id, entryID: entry.id)
        let saved = try stored(goal.id)
        XCTAssertEqual(saved.currentAmount, 100, accuracy: 0.001)
        XCTAssertTrue(saved.entries.isEmpty)
        XCTAssertNil(saved.completedAt)
    }

    func testUpdateKeepsMoneyAndJournal() throws {
        let goal = makeGoal(target: 1_000, saved: 300)
        service.addGoal(goal)
        service.deposit(goalID: goal.id, amount: 100)

        var edited = try stored(goal.id)
        edited.title = "Bigger trip"
        edited.targetAmount = 5_000
        edited.symbol = "airplane"
        edited.deadline = Date(timeIntervalSince1970: 1_900_000_000)
        edited.currentAmount = 999_999
        edited.entries = []
        service.updateGoal(edited)

        let saved = try stored(goal.id)
        XCTAssertEqual(saved.title, "Bigger trip")
        XCTAssertEqual(saved.targetAmount, 5_000, accuracy: 0.001)
        XCTAssertEqual(saved.symbol, "airplane")
        XCTAssertNotNil(saved.deadline)
        XCTAssertEqual(saved.currentAmount, 400, accuracy: 0.001)
        XCTAssertEqual(saved.entries.count, 1)
    }

    func testLoweringTheTargetCompletesTheGoal() throws {
        let goal = makeGoal(target: 1_000, saved: 400)
        service.addGoal(goal)
        var edited = try stored(goal.id)
        edited.targetAmount = 300
        service.updateGoal(edited)
        XCTAssertNotNil(try stored(goal.id).completedAt)

        edited.targetAmount = 2_000
        service.updateGoal(edited)
        XCTAssertNil(try stored(goal.id).completedAt)
    }

    func testFreeBalanceSubtractsGoalsOfTheCard() {
        let card = Card(last4: "1111", holderName: "TEST USER", balance: 1_000, colorHex: "#2A2B30", gradientColors: ["#2A2B30", "#1C1D21"])
        service.addCard(card, number: "")
        service.addGoal(makeGoal(saved: 300, cardId: card.id))
        service.addGoal(makeGoal(saved: 200, cardId: card.id))
        service.addGoal(makeGoal(saved: 999, cardId: nil))
        XCTAssertEqual(service.freeBalance(of: card), 500, accuracy: 0.001)

        service.addGoal(makeGoal(target: 5_000, saved: 4_000, cardId: card.id))
        XCTAssertEqual(service.freeBalance(of: card), 0, accuracy: 0.001)
    }

    func testOldDepositMethodStillWorks() throws {
        let goal = makeGoal()
        service.addGoal(goal)
        service.addFundsToGoal(id: goal.id, amount: 125)
        XCTAssertEqual(try stored(goal.id).currentAmount, 125, accuracy: 0.001)
    }

    func testGoalWithJournalSurvivesReload() throws {
        let goal = makeGoal()
        service.addGoal(goal)
        service.deposit(goalID: goal.id, amount: 150, note: "First")
        var edited = try stored(goal.id)
        edited.symbol = "gift.fill"
        service.updateGoal(edited)

        let reloaded = FinanceService()
        let saved = try XCTUnwrap(reloaded.goals.first { $0.id == goal.id })
        XCTAssertEqual(saved.currentAmount, 150, accuracy: 0.001)
        XCTAssertEqual(saved.entries.first?.note, "First")
        XCTAssertEqual(saved.symbol, "gift.fill")
        XCTAssertNotNil(saved.createdAt)
    }

    func testAssistantAnswersAboutGoalsInThreeLanguages() {
        service.addGoal(Goal(title: "Vacation", targetAmount: 100_000, currentAmount: 25_000, colorHex: "#C6F432", gradientColors: ["#C6F432"]))
        for question in ["как мои копилки?", "how are my goals?", "ինչպե՞ս են իմ նպատակները"] {
            let reply = LocalFinanceAssistant.answer(question, financeService: service)
            XCTAssertNotEqual(reply, LocalFinanceAssistant.helpText, question)
            XCTAssertTrue(reply.contains("Vacation"), "\(question) → \(reply)")
        }
    }

    func testAssistantExplainsWhenThereAreNoGoals() {
        let reply = LocalFinanceAssistant.answer("как мои копилки?", financeService: service)
        XCTAssertNotEqual(reply, LocalFinanceAssistant.helpText)
        XCTAssertFalse(reply.isEmpty)
    }
}
