import Foundation

/// Что ИИ-помощник предлагает изменить в приложении: «добавь долг Арам 20 000 до 5 ноября», «поставь напоминание на пятницу».
/// Это только предложение. Изменения вносятся после того, как пользователь подтвердит их карточкой в чате.
struct AIAction: Sendable, Equatable {
    enum Kind: String, CaseIterable, Sendable {
        case addDebt = "add_debt"
        case changeDebt = "change_debt"
        case markDebtPaid = "mark_debt_paid"
        case markDebtUnpaid = "mark_debt_unpaid"
        case deleteDebt = "delete_debt"
        case addGoal = "add_goal"
        case changeGoal = "change_goal"
        case depositGoal = "deposit_goal"
        case withdrawGoal = "withdraw_goal"
        case deleteGoal = "delete_goal"
        case addReminder = "add_reminder"
        case changeReminder = "change_reminder"
        case deleteReminder = "delete_reminder"
        case freezeCard = "freeze_card"
        case unfreezeCard = "unfreeze_card"
        case deleteTransaction = "delete_transaction"
        case setTransactionCategory = "set_transaction_category"
        case setCurrency = "set_currency"
        case setReminderSetting = "set_reminder_setting"

        /// Удаление нельзя отменить, поэтому такие предложения подсвечиваются красным
        var isDestructive: Bool {
            switch self {
            case .deleteDebt, .deleteGoal, .deleteReminder, .deleteTransaction: return true
            default: return false
            }
        }
    }

    /// Настройки напоминаний, которые ИИ может переключить
    enum ReminderSetting: String, CaseIterable, Sendable {
        case debts
        case goalDeadlines = "goal_deadlines"
        case goalSaving = "goal_saving"
        case cardExpiry = "card_expiry"
        case dailyLog = "daily_log"
        case reminderTime = "reminder_time"
        case dailyLogTime = "daily_log_time"
    }

    var kind: Kind
    /// Что менять: короткий номер из списка в подсказке, последние 4 цифры карты или название
    var target: String?
    /// Название нового или переименованного: имя человека или банка, название копилки, текст напоминания
    var name: String?
    var amount: Double?
    var currency: AppCurrency?
    /// Срок долга, срок копилки или момент напоминания
    var date: Date?
    var direction: DebtSide?
    var debtType: DebtType?
    /// Вид платежа: коммуналка, интернет, подписка…; только для debtType == .bill
    var billKind: BillKind?
    var reminder: DebtReminder?
    var repeatRule: ReminderRepeat?
    var note: String?
    /// Название категории для операции
    var category: String?
    var setting: ReminderSetting?
    /// Значение настройки или валюта: «on», «off», «weekly», «10:00», «USD»
    var value: String?

    init(
        kind: Kind,
        target: String? = nil,
        name: String? = nil,
        amount: Double? = nil,
        currency: AppCurrency? = nil,
        date: Date? = nil,
        direction: DebtSide? = nil,
        debtType: DebtType? = nil,
        billKind: BillKind? = nil,
        reminder: DebtReminder? = nil,
        repeatRule: ReminderRepeat? = nil,
        note: String? = nil,
        category: String? = nil,
        setting: ReminderSetting? = nil,
        value: String? = nil
    ) {
        self.kind = kind
        self.target = target
        self.name = name
        self.amount = amount
        self.currency = currency
        self.date = date
        self.direction = direction
        self.debtType = debtType
        self.billKind = billKind
        self.reminder = reminder
        self.repeatRule = repeatRule
        self.note = note
        self.category = category
        self.setting = setting
        self.value = value
    }
}

/// Проверенное изменение: все названия найдены, суммы и даты в порядке, остаётся только применить
enum AIOperation: Equatable, Sendable {
    case addDebt(Debt)
    case updateDebt(Debt)
    case setDebtPaid(UUID, Bool)
    case deleteDebt(UUID)
    case addGoal(Goal)
    case updateGoal(Goal)
    /// Больше нуля — пополнение, меньше нуля — снятие
    case moveGoal(UUID, Double)
    case deleteGoal(UUID)
    case addReminder(CustomReminder)
    case updateReminder(CustomReminder)
    case deleteReminder(UUID)
    case setCardFrozen(UUID, Bool)
    case deleteTransaction(UUID)
    case setTransactionCategory(UUID, Category)
    case setCurrency(AppCurrency)
    case setReminderSetting(ReminderSettingChange)
}

enum ReminderSettingChange: Equatable, Sendable {
    case debts(Bool)
    case goalDeadlines(Bool)
    case goalSaving(GoalSavingReminder)
    case cardExpiry(Bool)
    case dailyLog(Bool)
    /// Минуты от полуночи
    case time(Int)
    case dailyLogTime(Int)
}

/// Предложение ИИ после проверки: что получится, можно ли это применить и если нельзя, то почему
struct PlannedAction: Identifiable, Equatable, Sendable {
    let id = UUID()
    let action: AIAction
    let operation: AIOperation?
    /// Что произойдёт, одной строкой для карточки в чате
    let summary: String
    let icon: String
    let isDestructive: Bool
    let problem: String?

    var canApply: Bool {
        operation != nil && problem == nil
    }
}

enum AIApplyOutcome: Equatable, Sendable {
    case done
    case failed(String)
}
