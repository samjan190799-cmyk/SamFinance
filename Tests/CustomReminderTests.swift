import XCTest
@testable import SamFinance

/// Свои напоминания: когда сработают, как попадают в план уведомлений и сохраняются
@MainActor
final class CustomReminderTests: XCTestCase {
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

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 10) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private func now() throws -> Date {
        try date(2026, 10, 26, hour: 8)
    }

    private func makeReminder(_ start: Date, _ rule: ReminderRepeat = .never, note: String? = nil) -> CustomReminder {
        CustomReminder(title: "Оплатить интернет", date: start, repeatRule: rule, note: note)
    }

    // MARK: - Срабатывания

    func testOneTimeReminderFiresOnceAndOnlyInTheFuture() throws {
        let future = makeReminder(try date(2026, 11, 5))
        XCTAssertEqual(ReminderPlanner.occurrences(of: future, now: try now(), calendar: calendar), [try date(2026, 11, 5)])

        let past = makeReminder(try date(2026, 10, 1))
        XCTAssertTrue(ReminderPlanner.occurrences(of: past, now: try now(), calendar: calendar).isEmpty)
    }

    func testDailyReminderLooksTwoWeeksAhead() throws {
        let reminder = makeReminder(try date(2026, 10, 1), .daily)
        let dates = ReminderPlanner.occurrences(of: reminder, now: try now(), calendar: calendar)
        XCTAssertEqual(dates.count, 14)
        XCTAssertEqual(dates.first, try date(2026, 10, 26))
        XCTAssertEqual(dates.last, try date(2026, 11, 8))
    }

    func testWeeklyReminderKeepsItsWeekday() throws {
        // 5 октября 2026 — понедельник
        let reminder = makeReminder(try date(2026, 10, 5), .weekly)
        let dates = ReminderPlanner.occurrences(of: reminder, now: try now(), calendar: calendar)
        XCTAssertEqual(dates.count, 8)
        XCTAssertEqual(dates.first, try date(2026, 10, 26))
        for pair in zip(dates, dates.dropFirst()) {
            XCTAssertEqual(calendar.dateComponents([.day], from: pair.0, to: pair.1).day, 7)
        }
    }

    func testMonthlyReminderFromTheThirtyFirstDoesNotDrift() throws {
        let reminder = makeReminder(try date(2026, 1, 31), .monthly)
        let dates = ReminderPlanner.occurrences(of: reminder, now: try date(2026, 2, 1), calendar: calendar)
        XCTAssertEqual(dates.count, 6)
        XCTAssertEqual(dates[0], try date(2026, 2, 28))
        XCTAssertEqual(dates[1], try date(2026, 3, 31), "после короткого месяца снова 31-е, а не 28-е")
        XCTAssertEqual(dates[2], try date(2026, 4, 30))
    }

    func testYearlyReminderIsPlannedTwoYearsAhead() throws {
        let reminder = makeReminder(try date(2020, 5, 5), .yearly)
        XCTAssertEqual(
            ReminderPlanner.occurrences(of: reminder, now: try now(), calendar: calendar),
            [try date(2027, 5, 5), try date(2028, 5, 5)]
        )
    }

    func testRepeatingReminderDoesNotFireBeforeItsStart() throws {
        let reminder = makeReminder(try date(2026, 12, 1), .weekly)
        let dates = ReminderPlanner.occurrences(of: reminder, now: try now(), calendar: calendar)
        XCTAssertEqual(dates.first, try date(2026, 12, 1))
    }

    // MARK: - План уведомлений

    func testSpecsCarryTheTitleNoteAndTarget() throws {
        let reminder = makeReminder(try date(2026, 11, 5), note: "счёт на почте")
        let specs = ReminderPlanner.customReminderSpecs(reminder, now: try now(), calendar: calendar)
        let spec = try XCTUnwrap(specs.first)
        XCTAssertEqual(specs.count, 1)
        XCTAssertEqual(spec.title, "Оплатить интернет")
        XCTAssertEqual(spec.body, "счёт на почте")
        XCTAssertEqual(spec.category, ReminderID.customCategory)
        XCTAssertEqual(spec.target, .overview)
        XCTAssertEqual(spec.fireDate, try date(2026, 11, 5))
        XCTAssertTrue(spec.id.hasPrefix(ReminderID.prefix), "по префиксу приложение отличает свои напоминания от подсказок покупки")
    }

    func testEveryOccurrenceHasItsOwnIdentifier() throws {
        let specs = ReminderPlanner.customReminderSpecs(makeReminder(try date(2026, 10, 1), .daily), now: try now(), calendar: calendar)
        XCTAssertEqual(Set(specs.map(\.id)).count, specs.count)
    }

    func testBlankTitleAndNoteGetDefaults() throws {
        let reminder = CustomReminder(title: "   ", date: try date(2026, 11, 5))
        let spec = try XCTUnwrap(ReminderPlanner.customReminderSpecs(reminder, now: try now(), calendar: calendar).first)
        XCTAssertFalse(spec.title.isEmpty)
        XCTAssertFalse(spec.body.isEmpty)
    }

    func testPlannerIncludesCustomRemindersAlongsideTheOthers() throws {
        let specs = ReminderPlanner.specs(
            debts: [],
            goals: [],
            cards: [],
            customReminders: [makeReminder(try date(2026, 11, 5)), makeReminder(try date(2026, 11, 3))],
            transactions: [],
            reviewCount: 0,
            snoozes: [:],
            settings: ReminderSettings(),
            now: try now(),
            calendar: calendar
        )
        XCTAssertEqual(specs.compactMap(\.fireDate), [try date(2026, 11, 3), try date(2026, 11, 5)])
    }

    func testCustomRemindersStayInsideTheNotificationLimit() throws {
        let reminders = (0..<10).map { index in
            CustomReminder(title: "Напоминание \(index)", date: calendar.date(byAdding: .day, value: index, to: Date(timeIntervalSince1970: 1_800_000_000)) ?? Date(), repeatRule: .daily)
        }
        let specs = ReminderPlanner.specs(
            debts: [],
            goals: [],
            cards: [],
            customReminders: reminders,
            transactions: [],
            reviewCount: 0,
            snoozes: [:],
            settings: ReminderSettings(),
            now: Date(timeIntervalSince1970: 1_799_000_000),
            calendar: calendar
        )
        XCTAssertEqual(specs.count, ReminderPlanner.limit)
    }

    func testRepeatTitlesAreFilledForEveryOption() {
        for option in ReminderRepeat.allCases {
            XCTAssertFalse(option.title.isEmpty, option.rawValue)
        }
    }

    // MARK: - Хранилище

    func testReminderIsAddedChangedAndDeleted() throws {
        let reminder = makeReminder(try date(2026, 11, 5))
        service.addCustomReminder(reminder)
        XCTAssertEqual(service.customReminders, [reminder])

        var changed = reminder
        changed.title = "Оплатить свет"
        changed.repeatRule = .monthly
        service.updateCustomReminder(changed)
        XCTAssertEqual(service.customReminders.first?.title, "Оплатить свет")
        XCTAssertEqual(service.customReminders.first?.repeatRule, .monthly)
        XCTAssertEqual(service.customReminders.count, 1)

        service.deleteCustomReminder(id: reminder.id)
        XCTAssertTrue(service.customReminders.isEmpty)
    }

    func testRemindersSurviveARestartAndAResetClearsThem() throws {
        let reminder = makeReminder(try date(2026, 11, 5), .weekly, note: "заметка")
        service.addCustomReminder(reminder)

        // Новый экземпляр читает файл так же, как приложение при запуске
        let reloaded = FinanceService()
        XCTAssertEqual(reloaded.customReminders, [reminder])

        service.resetAllData()
        XCTAssertTrue(service.customReminders.isEmpty)
        XCTAssertTrue(FinanceService().customReminders.isEmpty)
    }

    func testUpdatingAMissingReminderChangesNothing() throws {
        service.updateCustomReminder(makeReminder(try date(2026, 11, 5)))
        XCTAssertTrue(service.customReminders.isEmpty)
    }

    func testUpdateDebtKeepsThePaidMarkAndTheIdentity() throws {
        let debt = Debt(name: "Арам", amount: 1_000, dueDate: try date(2026, 11, 5), isLent: true)
        service.addDebt(debt)
        service.setDebtPaid(id: debt.id, isPaid: true)

        var edited = debt
        edited.amount = 2_000
        edited.name = "Арам Б."
        service.updateDebt(edited)

        let stored = try XCTUnwrap(service.debts.first)
        XCTAssertEqual(stored.id, debt.id)
        XCTAssertEqual(stored.amount, 2_000, accuracy: 0.001)
        XCTAssertEqual(stored.name, "Арам Б.")
        XCTAssertTrue(stored.isPaid)
    }
}
