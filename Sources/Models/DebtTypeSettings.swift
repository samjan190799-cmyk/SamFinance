import Foundation

/// Вид записи на экране долгов. У каждого вида свои настройки: кредиты, долги людям в обе стороны, разовые платежи
/// и каждый вид регулярных платежей (коммуналка, интернет, подписки…).
public enum DebtProfile: Hashable, Sendable, Identifiable {
    case owedToMe
    case iOwe
    case credit
    case oneTimeBill
    case bill(BillKind)

    public var id: String { key }

    /// Ключ для хранения настроек
    public var key: String {
        switch self {
        case .owedToMe: return "owedToMe"
        case .iOwe: return "iOwe"
        case .credit: return "credit"
        case .oneTimeBill: return "oneTime"
        case .bill(let kind): return "bill.\(kind.rawValue)"
        }
    }

    public init?(key: String) {
        if key.hasPrefix("bill.") {
            guard let kind = BillKind(rawValue: String(key.dropFirst("bill.".count))) else { return nil }
            self = .bill(kind)
            return
        }
        switch key {
        case "owedToMe": self = .owedToMe
        case "iOwe": self = .iOwe
        case "credit": self = .credit
        case "oneTime": self = .oneTimeBill
        default: return nil
        }
    }

    /// К какому виду относится запись: платёж с повтором — к своему виду, платёж без повтора — к разовым
    public init(debt: Debt) {
        switch debt.type {
        case .credit: self = .credit
        case .person: self = debt.isLent ? .owedToMe : .iOwe
        case .bill: self = debt.isRecurringBill ? .bill(debt.billKind ?? .other) : .oneTimeBill
        }
    }

    /// Долги и кредиты
    public static let debts: [DebtProfile] = [.owedToMe, .iOwe, .credit]

    /// Платежи: разовый и регулярные по видам
    public static let payments: [DebtProfile] = {
        var result: [DebtProfile] = [.oneTimeBill]
        for kind in BillKind.allCases {
            result.append(.bill(kind))
        }
        return result
    }()

    /// Все виды: долги и кредиты, затем платежи
    public static let all: [DebtProfile] = debts + payments

    public var title: String {
        switch self {
        case .owedToMe: return String(localized: "Мне должны")
        case .iOwe: return String(localized: "Я должен")
        case .credit: return String(localized: "Кредиты")
        case .oneTimeBill: return String(localized: "Разовый платёж")
        case .bill(let kind): return kind.title
        }
    }

    /// Значок SF Symbols
    public var icon: String {
        switch self {
        case .owedToMe: return "arrow.down.left"
        case .iOwe: return "arrow.up.right"
        case .credit: return "banknote.fill"
        case .oneTimeBill: return "1.circle.fill"
        case .bill(let kind): return kind.icon
        }
    }

    /// Регулярный платёж: у такого вида есть повтор и признак «сумма меняется»
    public var isRecurringBill: Bool {
        if case .bill = self { return true }
        return false
    }
}

/// Как напоминать после срока, пока запись не закрыта
public enum LateReminders: String, Codable, Sendable, CaseIterable, Identifiable {
    case off
    case nextDay
    case nextDayAndWeek
    case everyDayForWeek

    public var id: String { rawValue }

    /// Через сколько дней после срока приходит напоминание
    public var offsets: [Int] {
        switch self {
        case .off: return []
        case .nextDay: return [1]
        case .nextDayAndWeek: return [1, 7]
        case .everyDayForWeek: return Array(1...7)
        }
    }

    public var title: String {
        switch self {
        case .off: return String(localized: "Не напоминать")
        case .nextDay: return String(localized: "На следующий день")
        case .nextDayAndWeek: return String(localized: "На следующий день и через неделю")
        case .everyDayForWeek: return String(localized: "Каждый день неделю")
        }
    }
}

/// Настройки одного вида записей
public struct DebtTypeSetting: Codable, Equatable, Sendable {
    /// Выключатель вида: когда выключен, напоминаний по записям этого вида нет совсем
    public var isEnabled: Bool
    /// За сколько заранее напомнить; подставляется в новые записи и действует на записи без своего напоминания
    public var reminder: DebtReminder
    /// Своё время напоминаний в минутах от полуночи; пусто — общее время из настроек напоминаний
    public var minutes: Int?
    /// Как напоминать после срока
    public var late: LateReminders

    // Только для регулярных платежей: подставляется в новый платёж этого вида
    public var repeatRule: ReminderRepeat
    public var repeatInterval: Int
    public var isVariableAmount: Bool

    public init(isEnabled: Bool = true, reminder: DebtReminder = .standard, minutes: Int? = nil, late: LateReminders = .nextDayAndWeek, repeatRule: ReminderRepeat = .monthly, repeatInterval: Int = 1, isVariableAmount: Bool = false) {
        self.isEnabled = isEnabled
        self.reminder = reminder
        self.minutes = minutes
        self.late = late
        self.repeatRule = repeatRule
        self.repeatInterval = repeatInterval
        self.isVariableAmount = isVariableAmount
    }

    /// Настройки вида, пока их не меняли: коммуналка — с переменной суммой, страховка и налоги — раз в год
    public static func standard(for profile: DebtProfile) -> DebtTypeSetting {
        var setting = DebtTypeSetting()
        if case .bill(let kind) = profile {
            switch kind {
            case .utilities:
                setting.isVariableAmount = true
            case .insurance, .tax:
                setting.repeatRule = .yearly
            default:
                break
            }
        }
        return setting
    }

    /// Новые поля старых сохранений не ломают чтение: недостающее берётся по умолчанию
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        reminder = try container.decodeIfPresent(DebtReminder.self, forKey: .reminder) ?? .standard
        minutes = try container.decodeIfPresent(Int.self, forKey: .minutes)
        late = try container.decodeIfPresent(LateReminders.self, forKey: .late) ?? .nextDayAndWeek
        repeatRule = try container.decodeIfPresent(ReminderRepeat.self, forKey: .repeatRule) ?? .monthly
        repeatInterval = try container.decodeIfPresent(Int.self, forKey: .repeatInterval) ?? 1
        isVariableAmount = try container.decodeIfPresent(Bool.self, forKey: .isVariableAmount) ?? false
    }

    /// Какое напоминание подставить в новую запись: у выключенного вида — «не напоминать»
    public var defaultReminder: DebtReminder {
        isEnabled ? reminder : .off
    }
}

/// Настройки всех видов записей. Хранятся только изменённые виды, остальные берутся стандартными.
public struct DebtTypeSettings: Codable, Equatable, Sendable {
    public static let storageKey = "debt_type_settings"

    private var changed: [String: DebtTypeSetting]

    public init(changed: [String: DebtTypeSetting] = [:]) {
        self.changed = changed
    }

    public subscript(profile: DebtProfile) -> DebtTypeSetting {
        get { changed[profile.key] ?? .standard(for: profile) }
        set {
            if newValue == .standard(for: profile) {
                changed[profile.key] = nil
            } else {
                changed[profile.key] = newValue
            }
        }
    }

    public func setting(for debt: Debt) -> DebtTypeSetting {
        self[DebtProfile(debt: debt)]
    }

    /// Вид настроен не по умолчанию
    public func isCustomized(_ profile: DebtProfile) -> Bool {
        changed[profile.key] != nil
    }

    public mutating func reset(_ profile: DebtProfile) {
        changed[profile.key] = nil
    }

    /// Время напоминаний записи: своё у вида или общее
    public func minutes(for debt: Debt, general: Int) -> Int {
        setting(for: debt).minutes ?? general
    }

    public static func load(from defaults: UserDefaults = .standard) -> DebtTypeSettings {
        guard let data = defaults.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(DebtTypeSettings.self, from: data) else {
            return DebtTypeSettings()
        }
        return settings
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
