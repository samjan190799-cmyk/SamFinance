import Foundation

/// Как часто списывается подписка
public enum SubscriptionPeriod: String, Codable, Sendable, CaseIterable, Identifiable {
    case weekly
    case monthly
    case yearly

    public var id: String { rawValue }

    /// Короткое название для переключателя: «Неделя», «Месяц», «Год»
    public var title: String {
        switch self {
        case .weekly: return String(localized: "Неделя")
        case .monthly: return String(localized: "Месяц")
        case .yearly: return String(localized: "Год")
        }
    }

    /// Единица календаря для сдвига даты списания
    public var calendarComponent: Calendar.Component {
        switch self {
        case .weekly: return .weekOfYear
        case .monthly: return .month
        case .yearly: return .year
        }
    }

    /// Сколько таких периодов в году: в году считается 52 недели и 12 месяцев
    public var periodsPerYear: Double {
        switch self {
        case .weekly: return 52
        case .monthly: return 12
        case .yearly: return 1
        }
    }

    /// Тот же период как повтор напоминаний: оттуда берутся подписи «Каждый месяц» и «Каждые 3 мес.»
    public var repeatRule: ReminderRepeat {
        switch self {
        case .weekly: return .weekly
        case .monthly: return .monthly
        case .yearly: return .yearly
        }
    }
}

/// Состояние подписки: активная считается в итогах и напоминает, на паузе и в архиве нет
public enum SubscriptionStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case active
    case paused
    case archived

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .active: return String(localized: "Активна")
        case .paused: return String(localized: "На паузе")
        case .archived: return String(localized: "В архиве")
        }
    }
}

/// Вид подписки: от него зависят значок и цвет строки
public enum SubscriptionCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case video
    case music
    case cloud
    case apps
    case games
    case reading
    case learning
    case fitness
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .video: return String(localized: "Видео")
        case .music: return String(localized: "Музыка")
        case .cloud: return String(localized: "Облако")
        case .apps: return String(localized: "Приложения")
        case .games: return String(localized: "Игры")
        case .reading: return String(localized: "Чтение")
        case .learning: return String(localized: "Обучение")
        case .fitness: return String(localized: "Спорт")
        case .other: return String(localized: "Другое")
        }
    }

    /// Значок SF Symbols
    public var icon: String {
        switch self {
        case .video: return "play.rectangle.fill"
        case .music: return "music.note"
        case .cloud: return "icloud.fill"
        case .apps: return "square.grid.2x2.fill"
        case .games: return "gamecontroller.fill"
        case .reading: return "book.fill"
        case .learning: return "graduationcap.fill"
        case .fitness: return "figure.run"
        case .other: return "arrow.triangle.2.circlepath"
        }
    }

    /// Цвет в пастельной палитре «Пульса»
    var palette: PaletteColor {
        switch self {
        case .video: return .coral
        case .music: return .rose
        case .cloud: return .sky
        case .apps: return .lilac
        case .games: return .sun
        case .reading: return .sand
        case .learning: return .peach
        case .fitness: return .mint
        case .other: return .slate
        }
    }
}

public extension AppCurrency {
    /// Сумма в этой валюте с её символом, без пересчёта по курсу: «9.99» долларов — «$9.99», драмы без копеек — «4 500 ֏»
    func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = (self == .usd || self == .eur) ? 2 : 0
        formatter.groupingSeparator = " "
        let number = formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.0f", amount)
        return self == .usd ? "\(symbol)\(number)" : "\(number) \(symbol)"
    }
}

/// Подписка: регулярный платёж, который списывается сам (кино, музыка, облако). В отличие от платежей на вкладке «Платежи»,
/// её не нужно отмечать оплаченной: приложение само находит ближайшее списание по первой дате и периоду.
public struct AppSubscription: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    /// Сумма одного списания в валюте подписки
    public var amount: Double
    public var currency: AppCurrency
    public var period: SubscriptionPeriod
    /// «Каждые N периодов»: 3 при периоде «месяц» — раз в квартал; пусто и 1 — каждый период
    public var interval: Int?
    /// Дата одного из списаний (чаще первого): от неё считаются все следующие, чтобы подписка «31-го числа» не застревала на 28-м
    public var firstChargeDate: Date
    public var category: SubscriptionCategory
    public var status: SubscriptionStatus
    /// За сколько дней напомнить о списании; у подписки без выбора напоминание за день
    public var reminder: DebtReminder?
    /// Карта, с которой списывается подписка; пусто — не указана
    public var cardId: UUID?
    public var note: String?
    public var createdAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        currency: AppCurrency = .amd,
        period: SubscriptionPeriod = .monthly,
        interval: Int? = nil,
        firstChargeDate: Date = Date(),
        category: SubscriptionCategory = .other,
        status: SubscriptionStatus = .active,
        reminder: DebtReminder? = nil,
        cardId: UUID? = nil,
        note: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.currency = currency
        self.period = period
        self.interval = interval
        self.firstChargeDate = firstChargeDate
        self.category = category
        self.status = status
        self.reminder = reminder
        self.cardId = cardId
        self.note = note
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, amount, currency, period, interval, firstChargeDate, category, status, reminder, cardId, note, createdAt
    }

    /// Файл читается и тогда, когда в нём нет поля или значение из другой версии приложения неизвестно:
    /// одна непонятная запись не должна обнулять весь список подписок
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decode(Double.self, forKey: .amount)
        firstChargeDate = try container.decode(Date.self, forKey: .firstChargeDate)
        currency = (try? container.decodeIfPresent(AppCurrency.self, forKey: .currency)) ?? .amd
        period = (try? container.decodeIfPresent(SubscriptionPeriod.self, forKey: .period)) ?? .monthly
        interval = try? container.decodeIfPresent(Int.self, forKey: .interval)
        category = (try? container.decodeIfPresent(SubscriptionCategory.self, forKey: .category)) ?? .other
        status = (try? container.decodeIfPresent(SubscriptionStatus.self, forKey: .status)) ?? .active
        reminder = try? container.decodeIfPresent(DebtReminder.self, forKey: .reminder)
        cardId = try? container.decodeIfPresent(UUID.self, forKey: .cardId)
        note = try? container.decodeIfPresent(String.self, forKey: .note)
        createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(amount, forKey: .amount)
        try container.encode(currency, forKey: .currency)
        try container.encode(period, forKey: .period)
        try container.encodeIfPresent(interval, forKey: .interval)
        try container.encode(firstChargeDate, forKey: .firstChargeDate)
        try container.encode(category, forKey: .category)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(reminder, forKey: .reminder)
        try container.encodeIfPresent(cardId, forKey: .cardId)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }

    // MARK: - Стоимость

    /// Через сколько периодов наступает следующее списание
    public var effectiveInterval: Int {
        max(1, interval ?? 1)
    }

    public var isActive: Bool {
        status == .active
    }

    /// Напоминание с учётом значения по умолчанию
    public var effectiveReminder: DebtReminder {
        reminder ?? .standard
    }

    /// Сколько подписка стоит за год в своей валюте: 1 000 за месяц — 12 000, 100 за неделю — 5 200, 3 000 раз в квартал — 12 000
    public var costPerYear: Double {
        amount * period.periodsPerYear / Double(effectiveInterval)
    }

    /// Сколько подписка стоит в среднем за месяц в своей валюте: годовая стоимость, поделённая на 12
    public var costPerMonth: Double {
        costPerYear / 12
    }

    // MARK: - Даты списаний

    /// Дата списания с номером `number`: от первой даты, а не от предыдущего списания
    public func chargeDate(number: Int, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: period.calendarComponent, value: number * effectiveInterval, to: firstChargeDate)
    }

    /// Ближайшие списания подряд, начиная с сегодняшнего дня (сегодняшнее списание ещё считается ближайшим).
    /// Состояние подписки не учитывается: смотрите `nextChargeDate`.
    public func upcomingChargeDates(count: Int, now: Date = Date(), calendar: Calendar = .current) -> [Date] {
        guard count > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        let unit = period.calendarComponent
        // Прошедшие списания пропускаются прыжком: от первой даты до сегодняшнего дня могут быть сотни недель
        let elapsed = calendar.dateComponents([unit], from: firstChargeDate, to: today).value(for: unit) ?? 0
        var step = max(0, elapsed / effectiveInterval - 1)
        var result: [Date] = []
        var attempts = 0
        while result.count < count && attempts < 5_000 {
            guard let date = chargeDate(number: step, calendar: calendar) else { break }
            if calendar.startOfDay(for: date) >= today {
                result.append(date)
            }
            step += 1
            attempts += 1
        }
        return result
    }

    /// Ближайшее списание независимо от состояния подписки
    public func nextOccurrence(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        upcomingChargeDates(count: 1, now: now, calendar: calendar).first
    }

    /// Ближайшее списание активной подписки; у подписки на паузе и в архиве списаний нет
    public func nextChargeDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard isActive else { return nil }
        return nextOccurrence(now: now, calendar: calendar)
    }

    /// Через сколько дней ближайшее списание: 0 — сегодня; nil у подписки на паузе и в архиве
    public func daysUntilNextCharge(now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let next = nextChargeDate(now: now, calendar: calendar) else { return nil }
        let today = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: next)).day
    }

    // MARK: - Порядок в списке

    /// Порядок в списке: активные по ближайшему списанию, затем подписки на паузе, затем архив; при равенстве по названию
    public static func sortedForList(_ subscriptions: [AppSubscription], now: Date = Date(), calendar: Calendar = .current) -> [AppSubscription] {
        func rank(_ subscription: AppSubscription) -> Int {
            switch subscription.status {
            case .active: return 0
            case .paused: return 1
            case .archived: return 2
            }
        }
        // Дату считаем один раз на подписку, а не при каждом сравнении
        let keyed = subscriptions.map { (subscription: $0, next: $0.nextChargeDate(now: now, calendar: calendar)) }
        return keyed.sorted { lhs, rhs in
            if rank(lhs.subscription) != rank(rhs.subscription) {
                return rank(lhs.subscription) < rank(rhs.subscription)
            }
            if let first = lhs.next, let second = rhs.next, first != second {
                return first < second
            }
            return lhs.subscription.name.localizedCaseInsensitiveCompare(rhs.subscription.name) == .orderedAscending
        }.map { $0.subscription }
    }
}

/// Итоги по подписке: сколько уходит в месяц и в год. Считаются только активные подписки.
public struct SubscriptionTotals: Equatable, Sendable {
    /// Среднее за месяц
    public let perMonth: Double
    /// За год
    public let perYear: Double
    /// Сколько активных подписок вошло в итог
    public let count: Int

    /// `convert` переводит сумму из валюты подписки в валюту итога
    public init(_ subscriptions: [AppSubscription], convert: (Double, AppCurrency) -> Double) {
        var month = 0.0
        var year = 0.0
        var counted = 0
        for subscription in subscriptions where subscription.isActive {
            month += convert(subscription.costPerMonth, subscription.currency)
            year += convert(subscription.costPerYear, subscription.currency)
            counted += 1
        }
        perMonth = month
        perYear = year
        count = counted
    }
}

/// Дата списания в строке подписки
enum SubscriptionDateText {
    /// «Списание сегодня», «Списание завтра», «Списание через 3 дн.», дальше дата: «Списание 5 дек.»
    static func charge(days: Int, date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        switch days {
        case ...0: return String(localized: "Списание сегодня")
        case 1: return String(localized: "Списание завтра")
        case 2...6: return String(localized: "Списание через \(days) дн.")
        default:
            let text = DebtDateText.due(date, now: now, calendar: calendar)
            return String(localized: "Списание \(text)")
        }
    }
}
