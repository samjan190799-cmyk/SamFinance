import Foundation

/// Тип транзакции: доход или расход
public enum TransactionType: String, Codable, Sendable, CaseIterable {
    case income = "income"
    case expense = "expense"
}

/// Категория транзакции
public struct Category: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let icon: String // Имя системной иконки SF Symbols
    public let colorHex: String // Hex-код цвета для отображения
    public let type: TransactionType
    
    public init(id: UUID = UUID(), name: String, icon: String, colorHex: String, type: TransactionType) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.type = type
    }
    
    /// Предопределенный список категорий по умолчанию.
    /// Идентификаторы фиксированы: категория сохраняется целиком внутри каждой транзакции,
    /// и случайные UUID при каждом запуске превращали одну и ту же категорию в разные.
    /// Менять существующие номера нельзя, новые категории добавляются в конец с новым номером.
    public static let defaultCategories: [Category] = [
        Category(id: stableID(1), name: "Зарплата", icon: "briefcase.fill", colorHex: "#34C759", type: .income),
        Category(id: stableID(2), name: "Фриланс", icon: "laptopcomputer", colorHex: "#007AFF", type: .income),
        Category(id: stableID(3), name: "Инвестиции", icon: "chart.line.uptrend.xyaxis", colorHex: "#AF52DE", type: .income),
        Category(id: stableID(4), name: "Продукты", icon: "cart.fill", colorHex: "#FF9500", type: .expense),
        Category(id: stableID(5), name: "Транспорт", icon: "car.fill", colorHex: "#5AC8FA", type: .expense),
        Category(id: stableID(6), name: "Рестораны", icon: "fork.knife", colorHex: "#FF2D55", type: .expense),
        Category(id: stableID(7), name: "Жилье", icon: "house.fill", colorHex: "#5E5CE6", type: .expense),
        Category(id: stableID(8), name: "Развлечения", icon: "gamecontroller.fill", colorHex: "#FFCC00", type: .expense),
        Category(id: stableID(9), name: "Здоровье", icon: "heart.text.square.fill", colorHex: "#FF3B30", type: .expense),
        Category(id: stableID(10), name: "Долги", icon: "banknote.fill", colorHex: "#A2845E", type: .expense),
        Category(id: stableID(11), name: "Прочее", icon: "ellipsis.circle.fill", colorHex: "#8E8E93", type: .expense),
        Category(id: stableID(12), name: "Переводы", icon: "arrow.left.arrow.right", colorHex: "#5AC8FA", type: .expense),
        Category(id: stableID(13), name: "Переводы", icon: "arrow.left.arrow.right", colorHex: "#5AC8FA", type: .income)
    ]

    /// Постоянный идентификатор встроенной категории по её номеру
    private static func stableID(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "5A3F1C00-0000-4000-8000-%012ld", number))!
    }
}

/// Банковская карта пользователя
public struct Card: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var last4: String // Последние 4 цифры номера. Полный номер лежит в Keychain (CardSecretsStore), CVV не хранится
    public var holderName: String
    public var balance: Double
    public var type: String // Назначение карты ("Карта для покупок")
    public var colorHex: String // Основной цвет свечения
    public var gradientColors: [String] // Цвета для градиентного фона
    public var isFrozen: Bool
    public var expiryDate: String // Срок действия (MM/YY)
    public var balanceUpdatedAt: Date? // На какой момент верен баланс: операции старше него баланс не меняют

    // Оформление и подробности карты; у старых карт их нет
    public var bankName: String? // Банк: подпись на карте
    public var network: CardNetwork? // Платёжная система
    public var pattern: CardPattern? // Узор на лицевой стороне
    public var symbol: String? // Значок рядом с назначением (SF Symbol)

    public init(id: UUID = UUID(), last4: String, holderName: String, balance: Double, type: String = "Digital card", colorHex: String, gradientColors: [String], isFrozen: Bool = false, expiryDate: String = "08/29", balanceUpdatedAt: Date? = nil, bankName: String? = nil, network: CardNetwork? = nil, pattern: CardPattern? = nil, symbol: String? = nil) {
        self.id = id
        self.last4 = last4
        self.holderName = holderName
        self.balance = balance
        self.type = type
        self.colorHex = colorHex
        self.gradientColors = gradientColors
        self.isFrozen = isFrozen
        self.expiryDate = expiryDate
        self.balanceUpdatedAt = balanceUpdatedAt
        self.bankName = bankName
        self.network = network
        self.pattern = pattern
        self.symbol = symbol
    }

    /// Последние 4 цифры из номера в любом виде (с пробелами или без)
    public static func lastFourDigits(of number: String) -> String {
        String(number.filter { $0.isNumber }.suffix(4))
    }

    private enum CodingKeys: String, CodingKey {
        case id, last4, holderName, balance, type, colorHex, gradientColors, isFrozen, expiryDate, balanceUpdatedAt
        case bankName, network, pattern, symbol
        case number // Только чтение: старые файлы хранили полный номер прямо в cards.json
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        if let stored = try container.decodeIfPresent(String.self, forKey: .last4) {
            last4 = stored
        } else {
            // Старый формат: полный номер уходит в Keychain при загрузке (FinanceService), здесь берём только конец
            last4 = Card.lastFourDigits(of: try container.decodeIfPresent(String.self, forKey: .number) ?? "")
        }
        holderName = try container.decode(String.self, forKey: .holderName)
        balance = try container.decode(Double.self, forKey: .balance)
        type = try container.decode(String.self, forKey: .type)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        gradientColors = try container.decode([String].self, forKey: .gradientColors)
        isFrozen = try container.decode(Bool.self, forKey: .isFrozen)
        expiryDate = try container.decode(String.self, forKey: .expiryDate)
        balanceUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .balanceUpdatedAt)
        bankName = try container.decodeIfPresent(String.self, forKey: .bankName)
        // Неизвестное значение (например, из более новой версии) не должно ломать чтение всех карт
        network = (try? container.decodeIfPresent(CardNetwork.self, forKey: .network)) ?? nil
        pattern = (try? container.decodeIfPresent(CardPattern.self, forKey: .pattern)) ?? nil
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(last4, forKey: .last4)
        try container.encode(holderName, forKey: .holderName)
        try container.encode(balance, forKey: .balance)
        try container.encode(type, forKey: .type)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(gradientColors, forKey: .gradientColors)
        try container.encode(isFrozen, forKey: .isFrozen)
        try container.encode(expiryDate, forKey: .expiryDate)
        try container.encodeIfPresent(balanceUpdatedAt, forKey: .balanceUpdatedAt)
        try container.encodeIfPresent(bankName, forKey: .bankName)
        try container.encodeIfPresent(network, forKey: .network)
        try container.encodeIfPresent(pattern, forKey: .pattern)
        try container.encodeIfPresent(symbol, forKey: .symbol)
    }
}

/// Тип записи на экране долгов: кредит организации, долг человеку или регулярный платёж (коммуналка, интернет, подписка)
public enum DebtType: String, Codable, Sendable, CaseIterable {
    case credit = "credit"
    case person = "person"
    case bill = "bill"
}

/// Вид регулярного платежа
public enum BillKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case utilities
    case internet
    case phone
    case rent
    case subscription
    case insurance
    case tax
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .utilities: return String(localized: "Коммуналка")
        case .internet: return String(localized: "Интернет")
        case .phone: return String(localized: "Телефон")
        case .rent: return String(localized: "Аренда")
        case .subscription: return String(localized: "Подписки")
        case .insurance: return String(localized: "Страховка")
        case .tax: return String(localized: "Налоги")
        case .other: return String(localized: "Другое")
        }
    }

    /// Значок SF Symbols
    public var icon: String {
        switch self {
        case .utilities: return "house.fill"
        case .internet: return "wifi"
        case .phone: return "phone.fill"
        case .rent: return "key.fill"
        case .subscription: return "play.rectangle.fill"
        case .insurance: return "shield.fill"
        case .tax: return "building.columns.fill"
        case .other: return "doc.text.fill"
        }
    }
}

public extension ReminderRepeat {
    /// Единица календаря для сдвига срока; у разового повтора её нет
    var calendarComponent: Calendar.Component? {
        switch self {
        case .never: return nil
        case .daily: return .day
        case .weekly: return .weekOfYear
        case .monthly: return .month
        case .yearly: return .year
        }
    }

    /// «Каждый месяц»; если период не один — «Каждые 3 мес.»
    func title(every interval: Int) -> String {
        guard interval > 1 else { return title }
        switch self {
        case .never: return title
        case .daily: return String(localized: "Каждые \(interval) дн.")
        case .weekly: return String(localized: "Каждые \(interval) нед.")
        case .monthly: return String(localized: "Каждые \(interval) мес.")
        case .yearly: return String(localized: "Каждые \(interval) г.")
        }
    }
}

/// Когда заранее напомнить о сроке долга. В день срока и после него, пока долг не погашен, напоминание приходит всегда,
/// если оно не выключено совсем.
public enum DebtReminder: String, Codable, Sendable, CaseIterable, Identifiable {
    case off
    case onDueDay
    case dayBefore
    case threeDaysBefore
    case weekBefore

    public var id: String { rawValue }

    /// У долгов, заведённых до появления выбора, напоминание за день до срока
    public static let standard: DebtReminder = .dayBefore

    /// За сколько дней до срока прислать первое напоминание; nil — напоминания выключены
    public var daysBefore: Int? {
        switch self {
        case .off: return nil
        case .onDueDay: return 0
        case .dayBefore: return 1
        case .threeDaysBefore: return 3
        case .weekBefore: return 7
        }
    }

    public var title: String {
        switch self {
        case .off: return String(localized: "Не напоминать")
        case .onDueDay: return String(localized: "В день срока")
        case .dayBefore: return String(localized: "За день")
        case .threeDaysBefore: return String(localized: "За 3 дня")
        case .weekBefore: return String(localized: "За неделю")
        }
    }
}

/// Долг (взаиморасчеты с контактами или кредиты банкам)
public struct Debt: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String // Имя человека или банка
    public var amount: Double
    public var dueDate: Date
    public var isLent: Bool // true - мне должны (Lent), false - я должен (Borrowed)
    public var isPaid: Bool // Статус погашения
    public var type: DebtType
    public var reminder: DebtReminder? // Когда напомнить заранее; у старых долгов поля нет

    // Только для платежей (type == .bill); у долгов и кредитов поля пусты
    public var billKind: BillKind? // Коммуналка, интернет, подписка…
    public var repeatRule: ReminderRepeat? // Как часто платить; пусто или «один раз» — платёж разовый
    public var firstDueDate: Date? // Первый срок: от него считаются следующие, чтобы 31-е число не «уезжало» на 28-е
    public var lastPaidAt: Date? // Когда платёж оплачивали в последний раз

    // Дополнительные условия; у записей, заведённых раньше, их нет
    public var note: String? // Заметка: номер договора, лицевой счёт, ссылка для оплаты
    public var repeatInterval: Int? // «Каждые N периодов»: 3 при повторе «каждый месяц» — раз в квартал; пусто и 1 — каждый период
    public var isVariableAmount: Bool? // Сумма каждый раз другая (коммуналка): при оплате спрашиваем, сколько вышло
    public var lastPaidAmount: Double? // Сколько внесли в последний раз
    public var originalAmount: Double? // Сумма до первого взноса: от неё считается, сколько уже выплачено

    // Только для кредитов с графиком платежей
    public var monthlyPayment: Double? // Ежемесячный платёж
    public var interestRate: Double? // Годовая ставка в процентах
    public var paymentsLeft: Int? // Сколько платежей осталось

    public init(id: UUID = UUID(), name: String, amount: Double, dueDate: Date = Date(), isLent: Bool, isPaid: Bool = false, type: DebtType = .person, reminder: DebtReminder? = nil, billKind: BillKind? = nil, repeatRule: ReminderRepeat? = nil, firstDueDate: Date? = nil, lastPaidAt: Date? = nil, note: String? = nil, repeatInterval: Int? = nil, isVariableAmount: Bool? = nil, lastPaidAmount: Double? = nil, originalAmount: Double? = nil, monthlyPayment: Double? = nil, interestRate: Double? = nil, paymentsLeft: Int? = nil) {
        self.id = id
        self.name = name
        self.amount = amount
        self.dueDate = dueDate
        self.isLent = isLent
        self.isPaid = isPaid
        self.type = type
        self.reminder = reminder
        self.billKind = billKind
        self.repeatRule = repeatRule
        self.firstDueDate = firstDueDate
        self.lastPaidAt = lastPaidAt
        self.note = note
        self.repeatInterval = repeatInterval
        self.isVariableAmount = isVariableAmount
        self.lastPaidAmount = lastPaidAmount
        self.originalAmount = originalAmount
        self.monthlyPayment = monthlyPayment
        self.interestRate = interestRate
        self.paymentsLeft = paymentsLeft
    }

    /// Платёж повторяется: после оплаты срок переносится на следующий период, а не закрывается
    public var isRecurringBill: Bool {
        type == .bill && (repeatRule ?? .never) != .never
    }

    /// Кредит с графиком: ежемесячный платёж, от которого уменьшается остаток
    public var hasPaymentPlan: Bool {
        type == .credit && (monthlyPayment ?? 0) > 0
    }

    /// После оплаты срок переносится на следующий период, а запись остаётся активной
    public var isRecurring: Bool {
        isRecurringBill || hasPaymentPlan
    }

    /// Как часто наступает срок: у кредита с графиком раз в месяц, у платежа по его повтору, у остальных записей никогда
    public var effectiveRepeat: ReminderRepeat {
        if hasPaymentPlan { return .monthly }
        return type == .bill ? (repeatRule ?? .never) : .never
    }

    /// Через сколько периодов наступает следующий срок: 3 при повторе «каждый месяц» — раз в квартал
    public var effectiveInterval: Int {
        hasPaymentPlan ? 1 : max(1, repeatInterval ?? 1)
    }

    /// Следующий срок повторяющегося платежа или кредита с графиком: первый период после текущего срока, который не раньше
    /// сегодняшнего дня. Считается от первого срока, а не от предыдущего, чтобы платёж «31-го числа» не застревал на 28-м.
    /// У разового платежа и у долгов следующего срока нет.
    public func nextDueDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard isRecurring, let unit = effectiveRepeat.calendarComponent else { return nil }
        let anchor = firstDueDate ?? dueDate
        let today = calendar.startOfDay(for: now)
        for step in 1..<5_000 {
            guard let candidate = calendar.date(byAdding: unit, value: step * effectiveInterval, to: anchor) else { return nil }
            if candidate > dueDate && candidate >= today {
                return candidate
            }
        }
        return nil
    }

    /// Напоминание с учётом значения по умолчанию
    public var effectiveReminder: DebtReminder {
        reminder ?? .standard
    }

    /// Напоминание с учётом настроек этого вида записей: своё у записи важнее, иначе берётся значение вида
    public func effectiveReminder(using settings: DebtTypeSettings) -> DebtReminder {
        reminder ?? settings.setting(for: self).reminder
    }

    /// Перед оплатой нужно спросить сумму: у платежа она каждый раз другая, а платёж по кредиту можно внести другим
    public var asksAmountBeforePaying: Bool {
        !isPaid && ((isRecurringBill && isVariableAmount == true) || hasPaymentPlan)
    }

    /// Внесено частями: остаток меньше суммы до первого взноса
    public var hasPartialPayments: Bool {
        guard let original = originalAmount else { return false }
        return original > amount + Debt.cent
    }

    /// Меньше этого остатка не бывает: так гасятся хвосты вроде 0,004 после пересчёта процентов
    static let cent = 0.005

    // MARK: - Оплата

    /// Учитывает оплату. Без суммы вносится всё, что положено: остаток долга, ежемесячный платёж кредита, сумма платежа.
    /// - кредит с графиком: остаток уменьшается на платёж за вычетом процентов, срок переходит на следующий месяц;
    /// - повторяющийся платёж: срок переходит на следующий период, а запись остаётся активной;
    /// - остальное: взнос уменьшает остаток, а когда остатка нет, запись закрывается.
    /// Сумма не больше нуля ничего не меняет.
    public mutating func applyPayment(_ payment: Double? = nil, now: Date = Date(), calendar: Calendar = .current) {
        if let payment, !(payment > 0) { return }
        lastPaidAt = now

        if hasPaymentPlan {
            applyPlanPayment(payment ?? monthlyPayment ?? amount, now: now, calendar: calendar)
        } else if isRecurringBill {
            let paid = payment ?? amount
            lastPaidAmount = paid
            if isVariableAmount == true, payment != nil {
                amount = paid // в следующий раз ждём столько же, сколько вышло сейчас
            }
            advanceDueDate(now: now, calendar: calendar)
        } else {
            applyRepayment(payment ?? amount)
        }
    }

    /// Взнос в счёт долга без смены срока: остаток уменьшается, а при полном погашении запись закрывается
    public mutating func applyRepayment(_ payment: Double) {
        guard payment > 0 else { return }
        let applied = min(payment, amount)
        lastPaidAmount = applied
        if amount - applied > Debt.cent {
            if originalAmount == nil {
                originalAmount = amount
            }
            amount -= applied
        } else {
            isPaid = true
        }
    }

    private mutating func applyPlanPayment(_ payment: Double, now: Date, calendar: Calendar) {
        let interest = amount * max(0, interestRate ?? 0) / 100 / 12
        let principal = min(max(payment - interest, 0), amount)
        lastPaidAmount = payment
        if let left = paymentsLeft {
            paymentsLeft = max(0, left - 1)
        }
        if amount - principal <= Debt.cent || paymentsLeft == 0 {
            isPaid = true
            return
        }
        if originalAmount == nil {
            originalAmount = amount
        }
        amount -= principal
        advanceDueDate(now: now, calendar: calendar)
    }

    private mutating func advanceDueDate(now: Date, calendar: Calendar) {
        guard let next = nextDueDate(now: now, calendar: calendar) else {
            isPaid = true
            return
        }
        if firstDueDate == nil {
            firstDueDate = dueDate
        }
        dueDate = next
    }
}

/// Две вкладки экрана долгов: что должны мне и что должен я. Кредиты всегда на стороне «Я должен».
public enum DebtSide: String, CaseIterable, Identifiable, Hashable, Sendable {
    case owedToMe
    case iOwe

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .owedToMe: return String(localized: "Мне должны")
        case .iOwe: return String(localized: "Я должен")
        }
    }

    /// Сторона, на которой лежит долг
    public init(debt: Debt) {
        self = debt.isLent ? .owedToMe : .iOwe
    }

    /// Платежи (коммуналка, интернет) лежат на своей вкладке и в «Я должен» не попадают
    public func contains(_ debt: Debt) -> Bool {
        debt.type != .bill && DebtSide(debt: debt) == self
    }
}

/// Все вкладки экрана долгов: «Мне должны», «Я должен» и «Платежи»
public enum DebtTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case owedToMe
    case iOwe
    case bills

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .owedToMe: return DebtSide.owedToMe.title
        case .iOwe: return DebtSide.iOwe.title
        case .bills: return String(localized: "Платежи")
        }
    }

    /// Вкладка, на которой лежит запись
    public init(debt: Debt) {
        if debt.type == .bill {
            self = .bills
        } else {
            self = debt.isLent ? .owedToMe : .iOwe
        }
    }

    public func contains(_ debt: Debt) -> Bool {
        DebtTab(debt: debt) == self
    }
}

/// Как часто повторяется своё напоминание
public enum ReminderRepeat: String, Codable, Sendable, CaseIterable, Identifiable {
    case never
    case daily
    case weekly
    case monthly
    case yearly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .never: return String(localized: "Один раз")
        case .daily: return String(localized: "Каждый день")
        case .weekly: return String(localized: "Каждую неделю")
        case .monthly: return String(localized: "Каждый месяц")
        case .yearly: return String(localized: "Каждый год")
        }
    }
}

/// Своё напоминание: «оплатить интернет 5 ноября в 10:00». Создаётся вручную или по просьбе в ИИ-чате.
public struct CustomReminder: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    /// Первое срабатывание: дата и время
    public var date: Date
    public var repeatRule: ReminderRepeat
    public var note: String?

    public init(id: UUID = UUID(), title: String, date: Date, repeatRule: ReminderRepeat = .never, note: String? = nil) {
        self.id = id
        self.title = title
        self.date = date
        self.repeatRule = repeatRule
        self.note = note
    }
}

/// Движение денег по копилке: пополнение (сумма больше нуля) или снятие (меньше нуля)
public struct GoalEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var date: Date
    public var amount: Double
    public var note: String?

    public init(id: UUID = UUID(), date: Date = Date(), amount: Double, note: String? = nil) {
        self.id = id
        self.date = date
        self.amount = amount
        self.note = note
    }
}

/// Накопительная цель (Копилка): деньги остаются на карте, приложение лишь откладывает их под цель
public struct Goal: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var cardId: UUID? // Карта, на которой лежат деньги; у общей копилки её нет
    public var title: String // Название цели (например, "На подарки")
    public var targetAmount: Double // Целевая сумма
    public var currentAmount: Double // Накоплено на данный момент
    public var colorHex: String // Цвет свечения
    public var gradientColors: [String] // Цвета градиента карточки цели

    // Подробности копилки; у старых копилок их нет
    public var deadline: Date? // К какому дню нужно накопить
    public var symbol: String? // Значок (SF Symbol)
    public var createdAt: Date?
    public var completedAt: Date? // Когда сумма впервые дошла до цели; пусто, если цель не достигнута
    public var entries: [GoalEntry] // Журнал пополнений и снятий

    public init(id: UUID = UUID(), cardId: UUID? = nil, title: String, targetAmount: Double, currentAmount: Double = 0.0, colorHex: String, gradientColors: [String], deadline: Date? = nil, symbol: String? = nil, createdAt: Date? = nil, completedAt: Date? = nil, entries: [GoalEntry] = []) {
        self.id = id
        self.cardId = cardId
        self.title = title
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.colorHex = colorHex
        self.gradientColors = gradientColors
        self.deadline = deadline
        self.symbol = symbol
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey {
        case id, cardId, title, targetAmount, currentAmount, colorHex, gradientColors
        case deadline, symbol, createdAt, completedAt, entries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        cardId = try container.decodeIfPresent(UUID.self, forKey: .cardId)
        title = try container.decode(String.self, forKey: .title)
        targetAmount = try container.decode(Double.self, forKey: .targetAmount)
        currentAmount = try container.decode(Double.self, forKey: .currentAmount)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        gradientColors = try container.decode([String].self, forKey: .gradientColors)
        deadline = try container.decodeIfPresent(Date.self, forKey: .deadline)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        // Файлы прежних версий журнала не знали
        entries = try container.decodeIfPresent([GoalEntry].self, forKey: .entries) ?? []
    }
}

/// Модель финансовой транзакции
public struct Transaction: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var amount: Double
    public var type: TransactionType
    public var category: Category
    public var date: Date
    public var notes: String?
    
    // Брендирование транзакции под новый дизайн
    public var brandName: String? // Например, "Apple"
    public var brandIcon: String? // Системная иконка или логотип (для простоты системная иконка)
    public var brandColorHex: String? // Цвет точки индикатора рядом с логотипом

    // Автоматизация: все поля необязательные, чтобы старые файлы транзакций читались без потерь
    public var cardId: UUID? // Карта, с которой прошла операция
    public var externalKey: String? // Ключ СМС для защиты от дублей
    public var needsReview: Bool? // Категория подобрана наугад: стоит проверить
    public var balanceDelta: Double? // На сколько операция изменила баланс карты (чтобы откатить при удалении)

    public init(id: UUID = UUID(), title: String, amount: Double, type: TransactionType, category: Category, date: Date = Date(), notes: String? = nil, brandName: String? = nil, brandIcon: String? = nil, brandColorHex: String? = nil, cardId: UUID? = nil, externalKey: String? = nil, needsReview: Bool? = nil, balanceDelta: Double? = nil) {
        self.id = id
        self.title = title
        self.amount = amount
        self.type = type
        self.category = category
        self.date = date
        self.notes = notes
        self.brandName = brandName
        self.brandIcon = brandIcon
        self.brandColorHex = brandColorHex
        self.cardId = cardId
        self.externalKey = externalKey
        self.needsReview = needsReview
        self.balanceDelta = balanceDelta
    }
}


extension Category {
    /// Встроенные категории показываются на языке приложения, свои — как назвал их пользователь
    public var displayName: String {
        Category.displayName(for: name)
    }

    public static func displayName(for name: String) -> String {
        builtInNames.contains(name) ? NSLocalizedString(name, comment: "") : name
    }

    private static let builtInNames: Set<String> = Set(defaultCategories.map(\.name))
}
