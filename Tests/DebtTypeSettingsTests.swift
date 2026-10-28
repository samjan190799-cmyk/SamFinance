import XCTest
@testable import SamFinance

/// Настройки по видам записей: виды, хранение и то, как по ним строятся напоминания
@MainActor
final class DebtTypeSettingsTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private var savedData: Data?

    // Вызов super.setUp() здесь не нужен (он пустой) и не компилируется в Swift 6 для MainActor-классов
    override func setUp() async throws {
        savedData = UserDefaults.standard.data(forKey: DebtTypeSettings.storageKey)
        UserDefaults.standard.removeObject(forKey: DebtTypeSettings.storageKey)
    }

    override func tearDown() async throws {
        if let savedData {
            UserDefaults.standard.set(savedData, forKey: DebtTypeSettings.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: DebtTypeSettings.storageKey)
        }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private func now() throws -> Date {
        try date(2026, 10, 26, hour: 8)
    }

    private func credit(plan: Bool = false) throws -> Debt {
        Debt(name: "IDBank", amount: 120_000, dueDate: try date(2026, 11, 5), isLent: false, type: .credit, monthlyPayment: plan ? 10_000 : nil)
    }

    private func person(isLent: Bool = false) throws -> Debt {
        Debt(name: "Арам", amount: 20_000, dueDate: try date(2026, 11, 5), isLent: isLent)
    }

    private func makeBill(rule: ReminderRepeat? = .monthly, kind: BillKind = .internet) throws -> Debt {
        Debt(name: "Ucom", amount: 4_500, dueDate: try date(2026, 11, 5), isLent: false, type: .bill, billKind: kind, repeatRule: rule)
    }

    private func specs(_ debt: Debt, _ settings: ReminderSettings = ReminderSettings()) throws -> [ReminderSpec] {
        ReminderPlanner.debtSpecs(debt, snooze: nil, settings: settings, now: try now(), calendar: calendar)
    }

    // MARK: - Виды

    func testEveryKindOfRecordHasItsOwnProfile() {
        XCTAssertEqual(DebtProfile.all.count, 3 + 1 + BillKind.allCases.count)
        XCTAssertEqual(Set(DebtProfile.all.map(\.key)).count, DebtProfile.all.count, "ключи не повторяются")
        XCTAssertEqual(Set(DebtProfile.all.map(\.title)).count, DebtProfile.all.count, "названия не повторяются")
        for profile in DebtProfile.all {
            XCTAssertFalse(profile.title.isEmpty, profile.key)
            XCTAssertFalse(profile.icon.isEmpty, profile.key)
            XCTAssertEqual(DebtProfile(key: profile.key), profile, profile.key)
        }
        XCTAssertNil(DebtProfile(key: "bill.nothing"))
        XCTAssertNil(DebtProfile(key: "unknown"))
    }

    func testRecordsFallIntoTheirProfile() throws {
        XCTAssertEqual(DebtProfile(debt: try credit()), .credit)
        XCTAssertEqual(DebtProfile(debt: try person(isLent: true)), .owedToMe)
        XCTAssertEqual(DebtProfile(debt: try person(isLent: false)), .iOwe)
        XCTAssertEqual(DebtProfile(debt: try makeBill(kind: .utilities)), .bill(.utilities))
        XCTAssertEqual(DebtProfile(debt: try makeBill(rule: .never)), .oneTimeBill)
        XCTAssertEqual(DebtProfile(debt: try makeBill(rule: nil)), .oneTimeBill)
        XCTAssertTrue(DebtProfile.bill(.rent).isRecurringBill)
        XCTAssertFalse(DebtProfile.oneTimeBill.isRecurringBill)
    }

    // MARK: - Хранение

    func testStandardSettingsDifferByKind() {
        XCTAssertTrue(DebtTypeSetting.standard(for: .bill(.utilities)).isVariableAmount, "коммуналка каждый раз другая")
        XCTAssertFalse(DebtTypeSetting.standard(for: .bill(.internet)).isVariableAmount)
        XCTAssertEqual(DebtTypeSetting.standard(for: .bill(.insurance)).repeatRule, .yearly)
        XCTAssertEqual(DebtTypeSetting.standard(for: .bill(.tax)).repeatRule, .yearly)
        XCTAssertEqual(DebtTypeSetting.standard(for: .bill(.subscription)).repeatRule, .monthly)
        for profile in DebtProfile.all {
            let setting = DebtTypeSetting.standard(for: profile)
            XCTAssertTrue(setting.isEnabled, profile.key)
            XCTAssertEqual(setting.reminder, .standard, profile.key)
            XCTAssertEqual(setting.late, .nextDayAndWeek, profile.key)
            XCTAssertNil(setting.minutes, profile.key)
        }
    }

    func testOnlyChangedKindsAreRemembered() {
        var settings = DebtTypeSettings()
        XCTAssertFalse(settings.isCustomized(.credit))

        settings[.credit].minutes = 540
        XCTAssertTrue(settings.isCustomized(.credit))
        XCTAssertFalse(settings.isCustomized(.iOwe))
        XCTAssertEqual(settings[.credit].minutes, 540)

        settings[.credit] = .standard(for: .credit)
        XCTAssertFalse(settings.isCustomized(.credit), "вернули стандартное — запись о виде исчезает")
        XCTAssertEqual(settings, DebtTypeSettings())

        settings[.bill(.rent)].isEnabled = false
        settings.reset(.bill(.rent))
        XCTAssertEqual(settings, DebtTypeSettings())
    }

    func testSettingsSurviveSavingAndLoading() {
        var settings = DebtTypeSettings()
        settings[.credit] = DebtTypeSetting(isEnabled: true, reminder: .weekBefore, minutes: 570, late: .everyDayForWeek)
        settings[.bill(.subscription)] = DebtTypeSetting(isEnabled: false, repeatRule: .yearly, repeatInterval: 2, isVariableAmount: true)
        settings.save()

        let loaded = DebtTypeSettings.load()
        XCTAssertEqual(loaded, settings)
        XCTAssertEqual(loaded[.credit].minutes, 570)
        XCTAssertEqual(loaded[.bill(.subscription)].repeatInterval, 2)
        XCTAssertFalse(loaded[.bill(.subscription)].isEnabled)
    }

    func testBrokenOrMissingSavedDataGivesStandardSettings() throws {
        let suite = "DebtTypeSettingsTests.broken"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(DebtTypeSettings.load(from: defaults), DebtTypeSettings())
        defaults.set(Data("не json".utf8), forKey: DebtTypeSettings.storageKey)
        XCTAssertEqual(DebtTypeSettings.load(from: defaults), DebtTypeSettings())
    }

    func testOldSavedSettingsWithoutNewFieldsStillRead() throws {
        let empty = try JSONDecoder().decode(DebtTypeSetting.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, DebtTypeSetting())

        let json = #"{"changed":{"credit":{"minutes":540},"bill.rent":{"isEnabled":false}}}"#
        let settings = try JSONDecoder().decode(DebtTypeSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings[.credit].minutes, 540)
        XCTAssertEqual(settings[.credit].late, .nextDayAndWeek)
        XCTAssertFalse(settings[.bill(.rent)].isEnabled)
        XCTAssertTrue(settings[.bill(.internet)].isEnabled)
    }

    func testReminderSettingsReadTheKindSettings() throws {
        var settings = DebtTypeSettings()
        settings[.iOwe].reminder = .threeDaysBefore
        settings.save()
        XCTAssertEqual(ReminderSettings.load().debtTypes[.iOwe].reminder, .threeDaysBefore)
        XCTAssertEqual(ReminderSettings.load().debtTypes[.owedToMe].reminder, .standard)
    }

    func testLateRemindersListTheirDays() {
        XCTAssertEqual(LateReminders.off.offsets, [])
        XCTAssertEqual(LateReminders.nextDay.offsets, [1])
        XCTAssertEqual(LateReminders.nextDayAndWeek.offsets, [1, 7])
        XCTAssertEqual(LateReminders.everyDayForWeek.offsets, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(Set(LateReminders.allCases.map(\.title)).count, LateReminders.allCases.count)
    }

    func testDefaultReminderOfADisabledKindIsOff() {
        var setting = DebtTypeSetting(reminder: .weekBefore)
        XCTAssertEqual(setting.defaultReminder, .weekBefore)
        setting.isEnabled = false
        XCTAssertEqual(setting.defaultReminder, .off)
    }

    func testRecordOwnReminderBeatsTheKindReminder() throws {
        var settings = DebtTypeSettings()
        settings[.iOwe].reminder = .weekBefore

        var debt = try person(isLent: false)
        XCTAssertEqual(debt.effectiveReminder(using: settings), .weekBefore, "у записи нет своего напоминания — берётся вид")
        debt.reminder = .onDueDay
        XCTAssertEqual(debt.effectiveReminder(using: settings), .onDueDay)
        XCTAssertEqual(debt.effectiveReminder, .onDueDay)
    }

    // MARK: - Напоминания по видам

    func testStandardSettingsKeepTheUsualReminders() throws {
        let result = try specs(try person())
        let ids = result.map(\.id)
        XCTAssertEqual(result.count, 4)
        XCTAssertTrue(ids.contains { $0.hasSuffix(".before") })
        XCTAssertTrue(ids.contains { $0.hasSuffix(".due") })
        XCTAssertTrue(ids.contains { $0.hasSuffix(".late1") })
        XCTAssertTrue(ids.contains { $0.hasSuffix(".late7") })
        XCTAssertEqual(result.compactMap(\.fireDate).min(), try date(2026, 11, 4, hour: 10))
    }

    func testEachKindHasItsOwnTime() throws {
        var settings = ReminderSettings()
        settings.debtTypes[.credit].minutes = 9 * 60 + 30

        for spec in try specs(try credit(), settings) {
            let components = calendar.dateComponents([.hour, .minute], from: try XCTUnwrap(spec.fireDate))
            XCTAssertEqual(components.hour, 9, spec.id)
            XCTAssertEqual(components.minute, 30, spec.id)
        }
        // Остальные виды остались на общем времени
        for spec in try specs(try person(), settings) {
            XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(spec.fireDate)), 10, spec.id)
        }
    }

    func testLateRemindersFollowTheKind() throws {
        var settings = ReminderSettings()
        settings.debtTypes[.credit].late = LateReminders.off
        settings.debtTypes[.iOwe].late = .nextDay
        settings.debtTypes[.owedToMe].late = .everyDayForWeek

        XCTAssertEqual(try specs(try credit(), settings).map(\.id).filter { $0.contains(".late") }, [])
        XCTAssertEqual(try specs(try person(isLent: false), settings).map(\.id).filter { $0.contains(".late") }.count, 1)
        let week = try specs(try person(isLent: true), settings).map(\.id).filter { $0.contains(".late") }
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(Set(week).count, 7, "у каждого дня свой номер уведомления")
    }

    func testSwitchedOffKindGivesNoRemindersAtAll() throws {
        var settings = ReminderSettings()
        settings.debtTypes[.bill(.subscription)].isEnabled = false

        XCTAssertTrue(try specs(try makeBill(kind: .subscription), settings).isEmpty)
        XCTAssertFalse(try specs(try makeBill(kind: .internet), settings).isEmpty, "другие виды платежей напоминают как раньше")
        XCTAssertFalse(try specs(try person(), settings).isEmpty)
    }

    func testKindReminderIsUsedWhenTheRecordHasNone() throws {
        var settings = ReminderSettings()
        settings.debtTypes[.iOwe].reminder = .weekBefore

        var debt = try person(isLent: false)
        XCTAssertNil(debt.reminder)
        XCTAssertEqual(try specs(debt, settings).compactMap(\.fireDate).min(), try date(2026, 10, 29, hour: 10))

        debt.reminder = .dayBefore
        XCTAssertEqual(try specs(debt, settings).compactMap(\.fireDate).min(), try date(2026, 11, 4, hour: 10))

        debt.reminder = DebtReminder.off
        XCTAssertTrue(try specs(debt, settings).isEmpty, "своё «не напоминать» важнее вида")
    }

    func testOneTimeAndRepeatingPaymentsAreSeparateKinds() throws {
        var settings = ReminderSettings()
        settings.debtTypes[.oneTimeBill].late = LateReminders.off
        settings.debtTypes[.bill(.internet)].late = .nextDay

        let oneTime = try specs(try makeBill(rule: .never), settings)
        let repeating = try specs(try makeBill(rule: .monthly), settings)
        XCTAssertEqual(oneTime.count, 2, "заранее и в день срока")
        XCTAssertEqual(repeating.count, 3, "заранее, в день срока и на следующий день")
    }

    func testCreditWithAScheduleIsMarkedPaidWithTheBillButton() throws {
        XCTAssertTrue(try specs(try credit(plan: true)).allSatisfy { $0.category == ReminderID.billCategory })
        XCTAssertTrue(try specs(try credit(plan: false)).allSatisfy { $0.category == ReminderID.debtCategory })
    }

    func testSnoozeUsesTheTimeOfTheKind() throws {
        var settings = ReminderSettings()
        settings.debtTypes[.credit].minutes = 8 * 60
        let debt = try credit()
        XCTAssertEqual(settings.debtTypes.minutes(for: debt, general: settings.minutes), 480)
        XCTAssertEqual(settings.debtTypes.minutes(for: try person(), general: settings.minutes), settings.minutes)
    }
}
