@preconcurrency import UserNotifications
import Foundation
import Observation

/// Ключи настроек напоминаний. Их же читают переключатели в настройках через @AppStorage.
enum ReminderKeys {
    static let debts = "reminders_debts"
    static let goalDeadlines = "reminders_goal_deadlines"
    static let goalSaving = "reminders_goal_saving"
    static let cardExpiry = "reminders_card_expiry"
    static let dailyLog = "reminders_daily_log"
    /// Время напоминаний в минутах от полуночи
    static let time = "reminders_time"
    static let dailyLogTime = "reminders_daily_log_time"
    static let snoozes = "reminders_snoozes"
}

/// Как часто напоминать отложить деньги в копилки
enum GoalSavingReminder: String, CaseIterable, Identifiable, Sendable {
    case off
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return String(localized: "Не напоминать")
        case .weekly: return String(localized: "Каждое воскресенье")
        case .monthly: return String(localized: "1-го числа")
        }
    }
}

/// Настройки напоминаний
struct ReminderSettings: Equatable, Sendable {
    var debts = true
    var goalDeadlines = true
    var goalSaving: GoalSavingReminder = .off
    var cardExpiry = true
    var dailyLog = false
    /// 10:00
    var minutes = 600
    /// 21:00
    var dailyLogMinutes = 1260

    static func load(from defaults: UserDefaults = .standard) -> ReminderSettings {
        var settings = ReminderSettings()
        settings.debts = defaults.object(forKey: ReminderKeys.debts) as? Bool ?? settings.debts
        settings.goalDeadlines = defaults.object(forKey: ReminderKeys.goalDeadlines) as? Bool ?? settings.goalDeadlines
        settings.goalSaving = defaults.string(forKey: ReminderKeys.goalSaving).flatMap { GoalSavingReminder(rawValue: $0) } ?? settings.goalSaving
        settings.cardExpiry = defaults.object(forKey: ReminderKeys.cardExpiry) as? Bool ?? settings.cardExpiry
        settings.dailyLog = defaults.object(forKey: ReminderKeys.dailyLog) as? Bool ?? settings.dailyLog
        settings.minutes = defaults.object(forKey: ReminderKeys.time) as? Int ?? settings.minutes
        settings.dailyLogMinutes = defaults.object(forKey: ReminderKeys.dailyLogTime) as? Int ?? settings.dailyLogMinutes
        return settings
    }
}

/// Идентификаторы напоминаний, их групп и кнопок
enum ReminderID {
    /// С этого начинаются идентификаторы всех напоминаний и их групп: по нему они отличаются от подсказок покупки
    static let prefix = "reminder."
    static let debtCategory = "reminder.debt"
    static let goalCategory = "reminder.goal"
    static let cardCategory = "reminder.card"
    static let dailyCategory = "reminder.daily"
    static let paidAction = "reminder.action.paid"
    static let snoozeAction = "reminder.action.snooze"
    static let targetKey = "reminder_target"
    /// Так назывались напоминания о сроке долга в прежних версиях
    static let legacyDebtPrefix = "debt-due-"
}

/// Куда ведёт напоминание: долг, копилка, карта или обзор
enum ReminderTarget: Equatable, Sendable {
    case debt(UUID)
    case goal(UUID)
    case savings
    case card(UUID)
    case overview

    var raw: String {
        switch self {
        case .debt(let id): return "debt:\(id.uuidString)"
        case .goal(let id): return "goal:\(id.uuidString)"
        case .savings: return "savings"
        case .card(let id): return "card:\(id.uuidString)"
        case .overview: return "overview"
        }
    }

    init?(raw: String) {
        let parts = raw.split(separator: ":", maxSplits: 1).map { String($0) }
        let id = parts.count == 2 ? UUID(uuidString: parts[1]) : nil
        switch (parts.first ?? "", id) {
        case ("debt", let id?): self = .debt(id)
        case ("goal", let id?): self = .goal(id)
        case ("card", let id?): self = .card(id)
        case ("savings", _): self = .savings
        case ("overview", _): self = .overview
        default: return nil
        }
    }

    /// Раздел приложения, который открывается по нажатию на напоминание
    var tab: AppTab {
        switch self {
        case .debt: return .debts
        case .goal, .savings, .card: return .cards
        case .overview: return .overview
        }
    }
}

/// Одно напоминание: всё, что нужно, чтобы поставить его в iOS
struct ReminderSpec: Equatable, Sendable {
    let id: String
    let title: String
    let body: String
    let category: String
    let target: ReminderTarget
    /// Разовое напоминание
    let fireDate: Date?
    /// Повторяющееся: день недели или месяца и время
    let repeating: DateComponents?
}

/// Решает, какие напоминания нужны по текущим данным. Чистая функция: её проверяют тесты без уведомлений.
@MainActor
enum ReminderPlanner {
    /// iOS хранит не больше 64 отложенных уведомлений на приложение; остальное место оставлено подсказкам покупки
    static let limit = 60

    static func specs(
        debts: [Debt],
        goals: [Goal],
        cards: [Card],
        transactions: [Transaction],
        reviewCount: Int,
        snoozes: [UUID: Date],
        settings: ReminderSettings,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ReminderSpec] {
        var result: [ReminderSpec] = []
        if settings.debts {
            for debt in debts {
                result += debtSpecs(debt, snooze: snoozes[debt.id], settings: settings, now: now, calendar: calendar)
            }
        }
        if settings.goalDeadlines {
            for goal in goals {
                result += goalDeadlineSpecs(goal, settings: settings, now: now, calendar: calendar)
            }
        }
        if let saving = goalSavingSpec(goals, settings: settings, now: now, calendar: calendar) {
            result.append(saving)
        }
        if settings.cardExpiry {
            for card in cards {
                result += cardExpirySpecs(card, settings: settings, now: now, calendar: calendar)
            }
        }
        if settings.dailyLog {
            result += dailyLogSpecs(transactions: transactions, reviewCount: reviewCount, settings: settings, now: now, calendar: calendar)
        }

        // Повторяющиеся впереди, затем ближайшие разовые: в лимит iOS попадают самые срочные
        let ordered = result.sorted { lhs, rhs in
            switch (lhs.fireDate, rhs.fireDate) {
            case let (first?, second?): return first < second
            case (nil, _?): return true
            case (_?, nil): return false
            case (nil, nil): return lhs.id < rhs.id
            }
        }
        return Array(ordered.prefix(limit))
    }

    /// Момент дня в заданное время
    static func moment(_ day: Date, minutes: Int, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
    }

    private static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    // MARK: - Долги

    private struct DebtTexts {
        let soonTitle: String
        let dueTitle: String
        let lateTitle: String
        let soonBody: String
        let dueBody: String
        let lateBody: String

        @MainActor
        init(debt: Debt) {
            let amount = CurrencyManager.shared.format(debt.amount)
            let date = ReminderPlanner.shortDate(debt.dueDate)
            let name = debt.name
            soonBody = String(localized: "\(name) · \(amount) · до \(date)")
            dueBody = "\(name) · \(amount)"

            if debt.type == .credit {
                soonTitle = String(localized: "Скоро платёж по кредиту")
                dueTitle = String(localized: "Сегодня платёж по кредиту")
                lateTitle = String(localized: "Платёж по кредиту просрочен")
                lateBody = String(localized: "\(name) · \(amount), срок был \(date)")
            } else if debt.isLent {
                soonTitle = String(localized: "Скоро вам вернут долг")
                dueTitle = String(localized: "Сегодня вам должны вернуть долг")
                lateTitle = String(localized: "Вам ещё не вернули долг")
                lateBody = String(localized: "\(name) · \(amount), срок был \(date). Напомните о долге")
            } else {
                soonTitle = String(localized: "Скоро вернуть долг")
                dueTitle = String(localized: "Сегодня вернуть долг")
                lateTitle = String(localized: "Срок возврата долга прошёл")
                lateBody = String(localized: "\(name) · \(amount), срок был \(date)")
            }
        }
    }

    /// Заранее (по выбору у долга), в день срока, на следующий день и через неделю, пока долг не погашен
    static func debtSpecs(_ debt: Debt, snooze: Date?, settings: ReminderSettings, now: Date, calendar: Calendar) -> [ReminderSpec] {
        guard !debt.isPaid, let daysBefore = debt.effectiveReminder.daysBefore else { return [] }
        let dueDay = calendar.startOfDay(for: debt.dueDate)
        let texts = DebtTexts(debt: debt)
        var result: [ReminderSpec] = []

        func add(_ suffix: String, fireDate: Date?, title: String, body: String) {
            guard let fireDate, fireDate > now else { return }
            result.append(ReminderSpec(
                id: "\(ReminderID.prefix)debt.\(debt.id.uuidString).\(suffix)",
                title: title,
                body: body,
                category: ReminderID.debtCategory,
                target: .debt(debt.id),
                fireDate: fireDate,
                repeating: nil
            ))
        }

        func day(_ offset: Int) -> Date? {
            calendar.date(byAdding: .day, value: offset, to: dueDay).flatMap { moment($0, minutes: settings.minutes, calendar: calendar) }
        }

        if daysBefore > 0 {
            add("before", fireDate: day(-daysBefore), title: texts.soonTitle, body: texts.soonBody)
        }
        add("due", fireDate: day(0), title: texts.dueTitle, body: texts.dueBody)
        add("late1", fireDate: day(1), title: texts.lateTitle, body: texts.lateBody)
        add("late7", fireDate: day(7), title: texts.lateTitle, body: texts.lateBody)

        // «Напомнить завтра» из уведомления
        if let snooze {
            let isLate = calendar.startOfDay(for: snooze) > dueDay
            add("snooze", fireDate: snooze, title: isLate ? texts.lateTitle : texts.dueTitle, body: isLate ? texts.lateBody : texts.dueBody)
        }
        return result
    }

    // MARK: - Копилки

    /// За неделю, за день и в день срока незавершённой копилки
    static func goalDeadlineSpecs(_ goal: Goal, settings: ReminderSettings, now: Date, calendar: Calendar) -> [ReminderSpec] {
        guard !goal.isCompleted, let deadline = goal.deadline else { return [] }
        let deadlineDay = calendar.startOfDay(for: deadline)
        let plan = GoalPlan(goal: goal, now: now, calendar: calendar)
        let money = CurrencyManager.shared
        let body = String(localized: "Накоплено \(money.format(plan.saved)) из \(money.format(plan.target)), осталось \(money.format(plan.remaining))")

        let steps: [(suffix: String, offset: Int, title: String)] = [
            ("week", -7, String(localized: "До срока копилки «\(goal.title)» неделя")),
            ("tomorrow", -1, String(localized: "Завтра срок копилки «\(goal.title)»")),
            ("today", 0, String(localized: "Сегодня срок копилки «\(goal.title)»"))
        ]
        return steps.compactMap { step in
            guard let day = calendar.date(byAdding: .day, value: step.offset, to: deadlineDay),
                  let fireDate = moment(day, minutes: settings.minutes, calendar: calendar),
                  fireDate > now else { return nil }
            return ReminderSpec(
                id: "\(ReminderID.prefix)goal.\(goal.id.uuidString).\(step.suffix)",
                title: step.title,
                body: body,
                category: ReminderID.goalCategory,
                target: .goal(goal.id),
                fireDate: fireDate,
                repeating: nil
            )
        }
    }

    /// Каждое воскресенье или 1-го числа: сколько отложить в незавершённые копилки, чтобы успеть к сроку
    static func goalSavingSpec(_ goals: [Goal], settings: ReminderSettings, now: Date, calendar: Calendar) -> ReminderSpec? {
        guard settings.goalSaving != .off else { return nil }
        let active = SavingsSummary.sortedActive(goals)
        guard !active.isEmpty else { return nil }

        let isWeekly = settings.goalSaving == .weekly
        var parts = active.prefix(3).map { goal -> String in
            let plan = GoalPlan(goal: goal, now: now, calendar: calendar)
            if let amount = isWeekly ? plan.perWeek : plan.perMonth, amount > 0 {
                return "\(goal.title) — \(CurrencyManager.shared.format(GoalQuickAmounts.rounded(amount)))"
            }
            return goal.title
        }
        if active.count > 3 {
            parts.append("…")
        }
        let list = parts.joined(separator: ", ")

        var components = DateComponents()
        components.hour = settings.minutes / 60
        components.minute = settings.minutes % 60
        if isWeekly {
            components.weekday = 1 // воскресенье в григорианском календаре
        } else {
            components.day = 1
        }

        return ReminderSpec(
            id: "\(ReminderID.prefix)goal-saving",
            title: String(localized: "Пора отложить в копилки"),
            body: isWeekly ? String(localized: "На этой неделе: \(list)") : String(localized: "В этом месяце: \(list)"),
            category: ReminderID.goalCategory,
            target: .savings,
            fireDate: nil,
            repeating: components
        )
    }

    // MARK: - Карты

    /// Последний день месяца из срока действия «MM/YY»; nil, если срок не указан или записан иначе
    static func expiryDay(of card: Card, calendar: Calendar) -> Date? {
        let parts = card.expiryDate.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let month = Int(parts[0]), (1...12).contains(month), var year = Int(parts[1]) else { return nil }
        if year < 100 {
            year += 2000
        }
        guard let firstDay = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: firstDay) else { return nil }
        return calendar.date(byAdding: .day, value: -1, to: nextMonth)
    }

    /// За месяц до конца срока действия и в последний день
    static func cardExpirySpecs(_ card: Card, settings: ReminderSettings, now: Date, calendar: Calendar) -> [ReminderSpec] {
        guard let lastDay = expiryDay(of: card, calendar: calendar) else { return [] }
        let steps: [(suffix: String, offset: Int, title: String, body: String)] = [
            (
                "soon", -30,
                String(localized: "Карта •••• \(card.last4) скоро истекает"),
                String(localized: "Срок действия до \(card.expiryDate). Закажите перевыпуск в банке.")
            ),
            (
                "today", 0,
                String(localized: "Сегодня истекает карта •••• \(card.last4)"),
                String(localized: "Когда получите новую карту, поменяйте срок действия в Hashiv.")
            )
        ]
        return steps.compactMap { step in
            guard let day = calendar.date(byAdding: .day, value: step.offset, to: lastDay),
                  let fireDate = moment(day, minutes: settings.minutes, calendar: calendar),
                  fireDate > now else { return nil }
            return ReminderSpec(
                id: "\(ReminderID.prefix)card.\(card.id.uuidString).\(step.suffix)",
                title: step.title,
                body: step.body,
                category: ReminderID.cardCategory,
                target: .card(card.id),
                fireDate: fireDate,
                repeating: nil
            )
        }
    }

    // MARK: - Учёт

    /// Вечером на две недели вперёд; сегодня не напоминает, если операции за день уже есть
    static func dailyLogSpecs(transactions: [Transaction], reviewCount: Int, settings: ReminderSettings, now: Date, calendar: Calendar) -> [ReminderSpec] {
        let today = calendar.startOfDay(for: now)
        let hasEntriesToday = transactions.contains { calendar.isDate($0.date, inSameDayAs: now) }
        var body = String(localized: "Наличные и покупки без СМС — пара касаний.")
        if reviewCount > 0 {
            body += " " + String(localized: "Проверить категории: \(reviewCount)")
        }

        return (0..<14).compactMap { offset in
            if offset == 0 && hasEntriesToday { return nil }
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fireDate = moment(day, minutes: settings.dailyLogMinutes, calendar: calendar),
                  fireDate > now else { return nil }
            let stamp = calendar.dateComponents([.year, .month, .day], from: day)
            return ReminderSpec(
                id: "\(ReminderID.prefix)daily.\(stamp.year ?? 0)-\(stamp.month ?? 0)-\(stamp.day ?? 0)",
                title: String(localized: "Запишите траты за сегодня"),
                body: body,
                category: ReminderID.dailyCategory,
                target: .overview,
                fireDate: fireDate,
                repeating: nil
            )
        }
    }
}

/// Раздел, который нужно открыть по нажатию на напоминание
@Observable
@MainActor
final class AppRouter {
    static let shared = AppRouter()

    var requestedTab: AppTab? = nil

    private init() {}
}

/// Напоминания во всех разделах: сроки долгов и кредитов, сроки копилок и «пора отложить», срок действия карт
/// и вечернее «запишите траты». Список пересоздаётся после каждого сохранения данных и при открытии приложения.
@MainActor
final class ReminderService {
    static let shared = ReminderService()

    private var pendingUpdate: Task<Void, Never>?

    private init() {}

    /// Группы с кнопками: у долга можно сразу отметить погашение или отложить напоминание на завтра
    static func notificationCategories() -> [UNNotificationCategory] {
        let paid = UNNotificationAction(identifier: ReminderID.paidAction, title: String(localized: "Погашен"), options: [.authenticationRequired])
        let snooze = UNNotificationAction(identifier: ReminderID.snoozeAction, title: String(localized: "Напомнить завтра"), options: [.authenticationRequired])
        return [
            UNNotificationCategory(identifier: ReminderID.debtCategory, actions: [paid, snooze], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: ReminderID.goalCategory, actions: [], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: ReminderID.cardCategory, actions: [], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: ReminderID.dailyCategory, actions: [], intentIdentifiers: [], options: [])
        ]
    }

    /// Пересоздаёт напоминания чуть позже: несколько сохранений подряд (например, пакет СМС) дают одно обновление
    func update(from financeService: FinanceService) {
        // Демо-данные для снимков App Store напоминаний не ставят
        guard ScreenshotMode.scene == nil, !ScreenshotMode.isTour else { return }
        pendingUpdate?.cancel()
        pendingUpdate = Task { [weak self, weak financeService] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, let financeService else { return }
            self.rebuild(from: financeService)
        }
    }

    private func rebuild(from financeService: FinanceService) {
        guard financeService.isFullyLoaded else { return }

        let now = Date()
        var snoozes = Self.loadSnoozes()
        let unpaid = Set(financeService.debts.filter { !$0.isPaid }.map(\.id))
        snoozes = snoozes.filter { $0.value > now && unpaid.contains($0.key) }
        Self.saveSnoozes(snoozes)

        let specs = ReminderPlanner.specs(
            debts: financeService.debts,
            goals: financeService.goals,
            cards: financeService.cards,
            transactions: financeService.transactions,
            reviewCount: financeService.reviewCount,
            snoozes: snoozes,
            settings: ReminderSettings.load(),
            now: now
        )
        Self.apply(specs)
    }

    /// Уведомления запрещены в настройках iOS: напоминания поставятся, но не появятся
    nonisolated static func isAuthorizationDenied() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus == .denied)
            }
        }
    }

    // MARK: - Кнопки и нажатия

    func handle(actionIdentifier: String, target rawTarget: String) {
        guard let target = ReminderTarget(raw: rawTarget) else { return }
        let financeService = FinanceService.shared

        switch actionIdentifier {
        case ReminderID.paidAction:
            if case .debt(let id) = target {
                financeService.setDebtPaid(id: id, isPaid: true)
            }
        case ReminderID.snoozeAction:
            if case .debt(let id) = target {
                let calendar = Calendar.current
                let settings = ReminderSettings.load()
                if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())),
                   let fireDate = ReminderPlanner.moment(tomorrow, minutes: settings.minutes, calendar: calendar) {
                    var snoozes = Self.loadSnoozes()
                    snoozes[id] = fireDate
                    Self.saveSnoozes(snoozes)
                    update(from: financeService)
                }
            }
        case UNNotificationDefaultActionIdentifier:
            AppRouter.shared.requestedTab = target.tab
        default:
            break
        }
    }

    // MARK: - Отложенные напоминания

    private static func loadSnoozes() -> [UUID: Date] {
        let raw = UserDefaults.standard.dictionary(forKey: ReminderKeys.snoozes) as? [String: Double] ?? [:]
        var result: [UUID: Date] = [:]
        for (key, value) in raw {
            if let id = UUID(uuidString: key) {
                result[id] = Date(timeIntervalSince1970: value)
            }
        }
        return result
    }

    private static func saveSnoozes(_ snoozes: [UUID: Date]) {
        var raw: [String: Double] = [:]
        for (id, date) in snoozes {
            raw[id.uuidString] = date.timeIntervalSince1970
        }
        UserDefaults.standard.set(raw, forKey: ReminderKeys.snoozes)
    }

    // MARK: - Уведомления iOS

    /// Убирает свои устаревшие напоминания и ставит нужные. Подсказки покупки не трогает.
    nonisolated private static func apply(_ specs: [ReminderSpec]) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { pending in
            let wanted = Set(specs.map(\.id))
            let stale = pending.map(\.identifier).filter { id in
                (id.hasPrefix(ReminderID.prefix) && !wanted.contains(id)) || id.hasPrefix(ReminderID.legacyDebtPrefix)
            }
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: stale)
            for spec in specs {
                center.add(request(for: spec)) { error in
                    if let error {
                        print("⚠️ Не удалось поставить напоминание: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    nonisolated private static func request(for spec: ReminderSpec) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = spec.title
        content.body = spec.body
        content.sound = .default
        content.categoryIdentifier = spec.category
        content.threadIdentifier = spec.category
        content.userInfo = [ReminderID.targetKey: spec.target.raw]

        let trigger: UNCalendarNotificationTrigger
        if let repeating = spec.repeating {
            trigger = UNCalendarNotificationTrigger(dateMatching: repeating, repeats: true)
        } else {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: spec.fireDate ?? Date())
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }
        return UNNotificationRequest(identifier: spec.id, content: content, trigger: trigger)
    }
}
