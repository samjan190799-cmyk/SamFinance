import Foundation

/// Проверяет предложения ИИ и вносит их в приложение. Сначала `plan`: находит долг, копилку, карту или напоминание
/// по номеру или названию, проверяет суммы и даты и описывает результат одной строкой. Потом `apply` вызывает те же методы,
/// что и обычные экраны. ИИ ничего не меняет сам: применяются только предложения, подтверждённые в чате.
@MainActor
enum AIActionExecutor {

    // MARK: - Короткие номера

    /// Номер, под которым долг, копилка, карта, напоминание или операция показаны ИИ в подсказке: первые 8 знаков идентификатора
    static func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    private enum Match<T> {
        case found(T)
        case notFound
        case ambiguous
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Ищет объект по короткому номеру, затем по точному названию, затем по частичному совпадению (если оно одно)
    private static func match<T>(_ target: String?, in items: [T], id: (T) -> UUID, names: (T) -> [String]) -> Match<T> {
        guard let raw = target?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return .notFound }

        if let range = raw.range(of: "[0-9A-Fa-f]{8}", options: .regularExpression) {
            let short = raw[range].uppercased()
            let byID = items.filter { shortID(id($0)) == short }
            if byID.count == 1 { return .found(byID[0]) }
        }

        let needle = normalized(raw)
        guard !needle.isEmpty else { return .notFound }

        let exact = items.filter { item in names(item).contains { normalized($0) == needle } }
        if exact.count == 1 { return .found(exact[0]) }
        if exact.count > 1 { return .ambiguous }

        let partial = items.filter { item in
            names(item).contains { name in
                let candidate = normalized(name)
                return !candidate.isEmpty && (candidate.contains(needle) || needle.contains(candidate))
            }
        }
        if partial.count == 1 { return .found(partial[0]) }
        return partial.isEmpty ? .notFound : .ambiguous
    }

    // MARK: - Разбор значений

    private static func money(_ amountInBase: Double) -> String {
        CurrencyManager.shared.format(amountInBase)
    }

    private static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private static func shortDateTime(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
    }

    private static func cleanName(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Сумма в базовой валюте приложения. Если валюта не названа, это валюта, в которой пользователь видит суммы.
    private static func baseAmount(_ action: AIAction) -> Double? {
        guard let amount = action.amount, amount.isFinite, amount > 0, amount < 1_000_000_000 else { return nil }
        let currency = action.currency ?? CurrencyManager.shared.currentCurrency
        return CurrencyService.shared.convert(amount: amount, from: currency, to: CurrencyManager.shared.baseCurrency)
    }

    private static func parseMinutes(_ value: String?) -> Int? {
        guard let value else { return nil }
        let parts = value.trimmingCharacters(in: .whitespaces).split(separator: ":").map { Int($0) }
        guard parts.count == 2, let hour = parts[0], let minute = parts[1],
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    private static func parseSwitch(_ value: String?) -> Bool? {
        switch value?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "on", "true", "yes", "1", "вкл", "да": return true
        case "off", "false", "no", "0", "выкл", "нет": return false
        default: return nil
        }
    }

    private static func clockText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    // MARK: - Проверка

    static func plan(_ action: AIAction, service: FinanceService = .shared, now: Date = Date(), calendar: Calendar = .current) -> PlannedAction {
        func result(_ operation: AIOperation, _ summary: String, _ icon: String) -> PlannedAction {
            PlannedAction(action: action, operation: operation, summary: summary, icon: icon, isDestructive: action.kind.isDestructive, problem: nil)
        }
        func failure(_ summary: String, _ problem: String, _ icon: String) -> PlannedAction {
            PlannedAction(action: action, operation: nil, summary: summary, icon: icon, isDestructive: action.kind.isDestructive, problem: problem)
        }

        switch action.kind {

        // MARK: Долги
        case .addDebt:
            let icon = "person.badge.plus"
            guard let name = cleanName(action.name) else {
                return failure(String(localized: "Добавить долг"), String(localized: "Не указано, кому или от кого долг"), icon)
            }
            guard let amount = baseAmount(action) else {
                return failure(String(localized: "Добавить долг: \(name)"), String(localized: "Не указана сумма"), icon)
            }
            guard let due = action.date else {
                return failure(String(localized: "Добавить долг: \(name)"), String(localized: "Не указан срок: напишите, до какого числа"), icon)
            }
            let type = action.debtType ?? .person
            let isLent: Bool
            if type == .credit {
                isLent = false
            } else if let direction = action.direction {
                isLent = direction == .owedToMe
            } else {
                return failure(String(localized: "Добавить долг: \(name)"), String(localized: "Не ясно, кто кому должен"), icon)
            }
            let day = calendar.startOfDay(for: due)
            let duplicate = service.debts.contains { debt in
                !debt.isPaid
                    && normalized(debt.name) == normalized(name)
                    && abs(debt.amount - amount) < 0.5
                    && calendar.isDate(debt.dueDate, inSameDayAs: day)
            }
            let summary: String
            if type == .credit {
                summary = String(localized: "Добавить кредит: \(name), \(money(amount)), срок \(shortDate(day))")
            } else if isLent {
                summary = String(localized: "Добавить долг: \(name) должен вам \(money(amount)), срок \(shortDate(day))")
            } else {
                summary = String(localized: "Добавить долг: вы должны \(name) \(money(amount)), срок \(shortDate(day))")
            }
            if duplicate {
                return failure(summary, String(localized: "Такой долг уже есть"), icon)
            }
            let debt = Debt(name: name, amount: amount, dueDate: day, isLent: isLent, type: type, reminder: action.reminder ?? .standard)
            return result(.addDebt(debt), summary, icon)

        case .changeDebt:
            let icon = "pencil"
            switch match(action.target, in: service.debts, id: { $0.id }, names: { [$0.name] }) {
            case .notFound:
                return failure(String(localized: "Изменить долг"), String(localized: "Не нашёл долг «\(action.target ?? "")»"), icon)
            case .ambiguous:
                return failure(String(localized: "Изменить долг"), String(localized: "Подходит несколько вариантов: «\(action.target ?? "")». Уточните"), icon)
            case .found(let debt):
                var updated = debt
                var changes: [String] = []
                if let name = cleanName(action.name), name != debt.name {
                    updated.name = name
                    changes.append(String(localized: "название «\(name)»"))
                }
                if action.amount != nil {
                    guard let amount = baseAmount(action) else {
                        return failure(String(localized: "Изменить долг «\(debt.name)»"), String(localized: "Неверная сумма"), icon)
                    }
                    updated.amount = amount
                    changes.append(String(localized: "сумма \(money(amount))"))
                }
                if let due = action.date {
                    updated.dueDate = calendar.startOfDay(for: due)
                    changes.append(String(localized: "срок \(shortDate(updated.dueDate))"))
                }
                if let reminder = action.reminder {
                    updated.reminder = reminder
                    changes.append(String(localized: "напоминание: \(reminder.title)"))
                }
                guard !changes.isEmpty else {
                    return failure(String(localized: "Изменить долг «\(debt.name)»"), String(localized: "Нечего менять"), icon)
                }
                return result(.updateDebt(updated), String(localized: "Изменить долг «\(debt.name)»: \(changes.joined(separator: ", "))"), icon)
            }

        case .markDebtPaid, .markDebtUnpaid:
            let paid = action.kind == .markDebtPaid
            let icon = paid ? "checkmark.circle" : "arrow.uturn.backward.circle"
            switch match(action.target, in: service.debts, id: { $0.id }, names: { [$0.name] }) {
            case .notFound:
                return failure(String(localized: "Отметить долг"), String(localized: "Не нашёл долг «\(action.target ?? "")»"), icon)
            case .ambiguous:
                return failure(String(localized: "Отметить долг"), String(localized: "Подходит несколько вариантов: «\(action.target ?? "")». Уточните"), icon)
            case .found(let debt):
                let summary = paid
                    ? String(localized: "Отметить долг «\(debt.name)» погашенным")
                    : String(localized: "Вернуть долг «\(debt.name)» в активные")
                if debt.isPaid == paid {
                    return failure(summary, paid ? String(localized: "Долг уже погашен") : String(localized: "Долг и так не погашен"), icon)
                }
                return result(.setDebtPaid(debt.id, paid), summary, icon)
            }

        case .deleteDebt:
            let icon = "trash"
            switch match(action.target, in: service.debts, id: { $0.id }, names: { [$0.name] }) {
            case .notFound:
                return failure(String(localized: "Удалить долг"), String(localized: "Не нашёл долг «\(action.target ?? "")»"), icon)
            case .ambiguous:
                return failure(String(localized: "Удалить долг"), String(localized: "Подходит несколько вариантов: «\(action.target ?? "")». Уточните"), icon)
            case .found(let debt):
                return result(.deleteDebt(debt.id), String(localized: "Удалить долг «\(debt.name)»"), icon)
            }

        // MARK: Копилки
        case .addGoal:
            let icon = "flag.fill"
            guard let name = cleanName(action.name) else {
                return failure(String(localized: "Создать копилку"), String(localized: "Не указано название"), icon)
            }
            guard let target = baseAmount(action) else {
                return failure(String(localized: "Создать копилку «\(name)»"), String(localized: "Не указана цель по сумме"), icon)
            }
            let deadline = action.date.map { calendar.startOfDay(for: $0) }
            let summary = deadline.map { String(localized: "Создать копилку «\(name)» на \(money(target)), срок \(shortDate($0))") }
                ?? String(localized: "Создать копилку «\(name)» на \(money(target))")
            let goal = Goal(
                title: name,
                targetAmount: target,
                colorHex: "#C6F432",
                gradientColors: ["#C6F432", "#B2E01E"],
                deadline: deadline,
                symbol: GoalSymbol.fallback
            )
            return result(.addGoal(goal), summary, icon)

        case .changeGoal:
            let icon = "pencil"
            switch match(action.target, in: service.goals, id: { $0.id }, names: { [$0.title] }) {
            case .notFound:
                return failure(String(localized: "Изменить копилку"), String(localized: "Не нашёл копилку «\(action.target ?? "")»"), icon)
            case .ambiguous:
                return failure(String(localized: "Изменить копилку"), String(localized: "Подходит несколько вариантов: «\(action.target ?? "")». Уточните"), icon)
            case .found(let goal):
                var updated = goal
                var changes: [String] = []
                if let name = cleanName(action.name), name != goal.title {
                    updated.title = name
                    changes.append(String(localized: "название «\(name)»"))
                }
                if action.amount != nil {
                    guard let target = baseAmount(action) else {
                        return failure(String(localized: "Изменить копилку «\(goal.title)»"), String(localized: "Неверная сумма"), icon)
                    }
                    updated.targetAmount = target
                    changes.append(String(localized: "цель \(money(target))"))
                }
                if let date = action.date {
                    updated.deadline = calendar.startOfDay(for: date)
                    changes.append(String(localized: "срок \(shortDate(calendar.startOfDay(for: date)))"))
                }
                guard !changes.isEmpty else {
                    return failure(String(localized: "Изменить копилку «\(goal.title)»"), String(localized: "Нечего менять"), icon)
                }
                return result(.updateGoal(updated), String(localized: "Изменить копилку «\(goal.title)»: \(changes.joined(separator: ", "))"), icon)
            }

        case .depositGoal, .withdrawGoal:
            let deposit = action.kind == .depositGoal
            let icon = deposit ? "arrow.down.circle" : "arrow.up.circle"
            switch match(action.target, in: service.goals, id: { $0.id }, names: { [$0.title] }) {
            case .notFound:
                return failure(String(localized: "Копилка"), String(localized: "Не нашёл копилку «\(action.target ?? "")»"), icon)
            case .ambiguous:
                return failure(String(localized: "Копилка"), String(localized: "Подходит несколько вариантов: «\(action.target ?? "")». Уточните"), icon)
            case .found(let goal):
                guard let amount = baseAmount(action) else {
                    let title = deposit ? String(localized: "Пополнить копилку «\(goal.title)»") : String(localized: "Снять из копилки «\(goal.title)»")
                    return failure(title, String(localized: "Не указана сумма"), icon)
                }
                if deposit {
                    return result(.moveGoal(goal.id, amount), String(localized: "Пополнить копилку «\(goal.title)» на \(money(amount))"), icon)
                }
                let summary = String(localized: "Снять из копилки «\(goal.title)» \(money(amount))")
                if amount > goal.currentAmount + 0.0001 {
                    return failure(summary, String(localized: "В копилке только \(money(goal.currentAmount))"), icon)
                }
                return result(.moveGoal(goal.id, -amount), summary, icon)
            }

        case .deleteGoal:
            let icon = "trash"
            switch match(action.target, in: service.goals, id: { $0.id }, names: { [$0.title] }) {
            case .notFound:
                return failure(String(localized: "Удалить копилку"), String(localized: "Не нашёл копилку «\(action.target ?? "")»"), icon)
            case .ambiguous:
                return failure(String(localized: "Удалить копилку"), String(localized: "Подходит несколько вариантов: «\(action.target ?? "")». Уточните"), icon)
            case .found(let goal):
                return result(.deleteGoal(goal.id), String(localized: "Удалить копилку «\(goal.title)»"), icon)
            }

        // MARK: Свои напоминания
        case .addReminder:
            let icon = "bell.badge"
            guard let title = cleanName(action.name) else {
                return failure(String(localized: "Поставить напоминание"), String(localized: "Не указано, что напомнить"), icon)
            }
            guard let date = action.date else {
                return failure(String(localized: "Поставить напоминание «\(title)»"), String(localized: "Не указана дата и время"), icon)
            }
            let repeatRule = action.repeatRule ?? .never
            let summary: String
            if repeatRule == .never {
                summary = String(localized: "Поставить напоминание «\(title)»: \(shortDateTime(date))")
            } else {
                summary = String(localized: "Поставить напоминание «\(title)»: \(shortDateTime(date)), \(repeatRule.title.lowercased())")
            }
            if repeatRule == .never && date <= now {
                return failure(summary, String(localized: "Это время уже прошло"), icon)
            }
            let reminder = CustomReminder(title: title, date: date, repeatRule: repeatRule, note: cleanName(action.note))
            return result(.addReminder(reminder), summary, icon)

        case .changeReminder:
            let icon = "bell"
            switch match(action.target, in: service.customReminders, id: { $0.id }, names: { [$0.title] }) {
            case .notFound:
                return failure(String(localized: "Изменить напоминание"), String(localized: "Не нашёл напоминание «\(action.target ?? "")»"), icon)
            case .ambiguous:
                return failure(String(localized: "Изменить напоминание"), String(localized: "Подходит несколько вариантов: «\(action.target ?? "")». Уточните"), icon)
            case .found(let reminder):
                var updated = reminder
                var changes: [String] = []
                if let name = cleanName(action.name), name != reminder.title {
                    updated.title = name
                    changes.append(String(localized: "текст «\(name)»"))
                }
                if let date = action.date {
                    updated.date = date
                    changes.append(shortDateTime(date))
                }
                if let repeatRule = action.repeatRule {
                    updated.repeatRule = repeatRule
                    changes.append(repeatRule.title.lowercased())
                }
                if let note = cleanName(action.note) {
                    updated.note = note
                    changes.append(String(localized: "заметка «\(note)»"))
                }
                guard !changes.isEmpty else {
                    return failure(String(localized: "Изменить напоминание «\(reminder.title)»"), String(localized: "Нечего менять"), icon)
                }
                return result(.updateReminder(updated), String(localized: "Изменить напоминание «\(reminder.title)»: \(changes.joined(separator: ", "))"), icon)
            }

        case .deleteReminder:
            let icon = "bell.slash"
            switch match(action.target, in: service.customReminders, id: { $0.id }, names: { [$0.title] }) {
            case .notFound:
                return failure(String(localized: "Удалить напоминание"), String(localized: "Не нашёл напоминание «\(action.target ?? "")»"), icon)
            case .ambiguous:
                return failure(String(localized: "Удалить напоминание"), String(localized: "Подходит несколько вариантов: «\(action.target ?? "")». Уточните"), icon)
            case .found(let reminder):
                return result(.deleteReminder(reminder.id), String(localized: "Удалить напоминание «\(reminder.title)»"), icon)
            }

        // MARK: Карты
        case .freezeCard, .unfreezeCard:
            let freeze = action.kind == .freezeCard
            let icon = freeze ? "snowflake" : "sun.max"
            switch match(action.target, in: service.cards, id: { $0.id }, names: { [$0.last4, $0.type] }) {
            case .notFound:
                return failure(String(localized: "Карта"), String(localized: "Не нашёл карту «\(action.target ?? "")»"), icon)
            case .ambiguous:
                return failure(String(localized: "Карта"), String(localized: "Подходит несколько вариантов: «\(action.target ?? "")». Уточните"), icon)
            case .found(let card):
                let summary = freeze
                    ? String(localized: "Заморозить карту •••• \(card.last4)")
                    : String(localized: "Разморозить карту •••• \(card.last4)")
                if card.isFrozen == freeze {
                    return failure(summary, freeze ? String(localized: "Карта уже заморожена") : String(localized: "Карта не заморожена"), icon)
                }
                return result(.setCardFrozen(card.id, freeze), summary, icon)
            }

        // MARK: Операции
        case .deleteTransaction:
            let icon = "trash"
            switch match(action.target, in: service.transactions, id: { $0.id }, names: { [$0.title] }) {
            case .notFound:
                return failure(String(localized: "Удалить операцию"), String(localized: "Не нашёл операцию «\(action.target ?? "")»"), icon)
            case .ambiguous:
                return failure(String(localized: "Удалить операцию"), String(localized: "Подходит несколько вариантов: «\(action.target ?? "")». Уточните"), icon)
            case .found(let transaction):
                return result(
                    .deleteTransaction(transaction.id),
                    String(localized: "Удалить операцию «\(transaction.title)» на \(money(transaction.amount)) от \(shortDate(transaction.date))"),
                    icon
                )
            }

        case .setTransactionCategory:
            let icon = "tag"
            switch match(action.target, in: service.transactions, id: { $0.id }, names: { [$0.title] }) {
            case .notFound:
                return failure(String(localized: "Сменить категорию"), String(localized: "Не нашёл операцию «\(action.target ?? "")»"), icon)
            case .ambiguous:
                return failure(String(localized: "Сменить категорию"), String(localized: "Подходит несколько вариантов: «\(action.target ?? "")». Уточните"), icon)
            case .found(let transaction):
                guard let name = cleanName(action.category) else {
                    return failure(String(localized: "Сменить категорию операции «\(transaction.title)»"), String(localized: "Не указана категория"), icon)
                }
                let category = service.categories.first { $0.type == transaction.type && normalized($0.name) == normalized(name) }
                guard let category else {
                    return failure(String(localized: "Сменить категорию операции «\(transaction.title)»"), String(localized: "Нет категории «\(name)» для этой операции"), icon)
                }
                return result(
                    .setTransactionCategory(transaction.id, category),
                    String(localized: "Категория операции «\(transaction.title)»: \(category.displayName)"),
                    icon
                )
            }

        // MARK: Настройки
        case .setCurrency:
            let icon = "dollarsign.circle"
            let code = action.value?.trimmingCharacters(in: .whitespaces).uppercased() ?? action.currency?.rawValue ?? ""
            guard let currency = AppCurrency(rawValue: code) else {
                return failure(String(localized: "Сменить валюту"), String(localized: "Неизвестная валюта"), icon)
            }
            return result(.setCurrency(currency), String(localized: "Показывать суммы в валюте: \(currency.rawValue)"), icon)

        case .setReminderSetting:
            let icon = "gearshape"
            guard let setting = action.setting else {
                return failure(String(localized: "Настройка напоминаний"), String(localized: "Неизвестная настройка"), icon)
            }
            return planReminderSetting(setting, value: action.value, action: action, icon: icon)
        }
    }

    private static func planReminderSetting(_ setting: AIAction.ReminderSetting, value: String?, action: AIAction, icon: String) -> PlannedAction {
        func result(_ change: ReminderSettingChange, _ summary: String) -> PlannedAction {
            PlannedAction(action: action, operation: .setReminderSetting(change), summary: summary, icon: icon, isDestructive: false, problem: nil)
        }
        func failure(_ summary: String) -> PlannedAction {
            PlannedAction(action: action, operation: nil, summary: summary, icon: icon, isDestructive: false, problem: String(localized: "Неверное значение настройки"))
        }
        func onOff(_ on: Bool, _ enabled: String, _ disabled: String, _ make: (Bool) -> ReminderSettingChange) -> PlannedAction {
            result(make(on), on ? enabled : disabled)
        }

        switch setting {
        case .debts:
            guard let on = parseSwitch(value) else { return failure(String(localized: "Напоминания о долгах")) }
            return onOff(on, String(localized: "Напоминания о долгах: включить"), String(localized: "Напоминания о долгах: выключить")) { .debts($0) }
        case .goalDeadlines:
            guard let on = parseSwitch(value) else { return failure(String(localized: "Напоминания о сроках копилок")) }
            return onOff(on, String(localized: "Напоминания о сроках копилок: включить"), String(localized: "Напоминания о сроках копилок: выключить")) { .goalDeadlines($0) }
        case .cardExpiry:
            guard let on = parseSwitch(value) else { return failure(String(localized: "Напоминания о сроке карт")) }
            return onOff(on, String(localized: "Напоминания о сроке карт: включить"), String(localized: "Напоминания о сроке карт: выключить")) { .cardExpiry($0) }
        case .dailyLog:
            guard let on = parseSwitch(value) else { return failure(String(localized: "Вечернее напоминание записать траты")) }
            return onOff(on, String(localized: "Вечернее напоминание «запишите траты»: включить"), String(localized: "Вечернее напоминание «запишите траты»: выключить")) { .dailyLog($0) }
        case .goalSaving:
            let option = GoalSavingReminder(rawValue: value?.trimmingCharacters(in: .whitespaces).lowercased() ?? "")
                ?? (parseSwitch(value) == false ? GoalSavingReminder.off : nil)
            guard let option else { return failure(String(localized: "Напоминание «отложить в копилки»")) }
            return result(.goalSaving(option), String(localized: "Напоминание «отложить в копилки»: \(option.title)"))
        case .reminderTime:
            guard let minutes = parseMinutes(value) else { return failure(String(localized: "Время напоминаний")) }
            return result(.time(minutes), String(localized: "Время напоминаний: \(clockText(minutes))"))
        case .dailyLogTime:
            guard let minutes = parseMinutes(value) else { return failure(String(localized: "Время вечернего напоминания")) }
            return result(.dailyLogTime(minutes), String(localized: "Время вечернего напоминания: \(clockText(minutes))"))
        }
    }

    // MARK: - Применение

    @discardableResult
    static func apply(_ plan: PlannedAction, service: FinanceService = .shared) -> AIApplyOutcome {
        guard plan.problem == nil, let operation = plan.operation else {
            return .failed(plan.problem ?? String(localized: "Нечего применять"))
        }

        switch operation {
        case .addDebt(let debt):
            service.addDebt(debt)
        case .updateDebt(let debt):
            service.updateDebt(debt)
        case .setDebtPaid(let id, let paid):
            service.setDebtPaid(id: id, isPaid: paid)
        case .deleteDebt(let id):
            service.deleteDebt(id: id)

        case .addGoal(let goal):
            service.addGoal(goal)
        case .updateGoal(let goal):
            service.updateGoal(goal)
        case .moveGoal(let id, let amount):
            let outcome = amount > 0
                ? service.deposit(goalID: id, amount: amount)
                : service.withdraw(goalID: id, amount: -amount)
            if outcome == .rejected {
                return .failed(String(localized: "Копилка не приняла сумму"))
            }
        case .deleteGoal(let id):
            service.deleteGoal(id: id)

        case .addReminder(let reminder):
            service.addCustomReminder(reminder)
        case .updateReminder(let reminder):
            service.updateCustomReminder(reminder)
        case .deleteReminder(let id):
            service.deleteCustomReminder(id: id)

        case .setCardFrozen(let id, let frozen):
            guard let card = service.cards.first(where: { $0.id == id }) else {
                return .failed(String(localized: "Карта уже удалена"))
            }
            if card.isFrozen != frozen {
                service.toggleFreezeCard(id: id)
            }

        case .deleteTransaction(let id):
            guard let transaction = service.transactions.first(where: { $0.id == id }) else {
                return .failed(String(localized: "Операция уже удалена"))
            }
            service.deleteTransaction(transaction)
        case .setTransactionCategory(let id, let category):
            guard let transaction = service.transactions.first(where: { $0.id == id }) else {
                return .failed(String(localized: "Операция уже удалена"))
            }
            service.updateCategory(transactionID: id, category: category)
            // Выбор запоминается: следующая такая операция получит эту категорию сама
            AutomationService.shared.learnCategory(merchant: transaction.brandName ?? transaction.title, category: category)

        case .setCurrency(let currency):
            CurrencyManager.shared.currentCurrency = currency
        case .setReminderSetting(let change):
            let defaults = UserDefaults.standard
            switch change {
            case .debts(let on): defaults.set(on, forKey: ReminderKeys.debts)
            case .goalDeadlines(let on): defaults.set(on, forKey: ReminderKeys.goalDeadlines)
            case .goalSaving(let option): defaults.set(option.rawValue, forKey: ReminderKeys.goalSaving)
            case .cardExpiry(let on): defaults.set(on, forKey: ReminderKeys.cardExpiry)
            case .dailyLog(let on): defaults.set(on, forKey: ReminderKeys.dailyLog)
            case .time(let minutes): defaults.set(minutes, forKey: ReminderKeys.time)
            case .dailyLogTime(let minutes): defaults.set(minutes, forKey: ReminderKeys.dailyLogTime)
            }
            ReminderService.shared.update(from: service)
        }
        return .done
    }

    /// После этого изменения могут прийти уведомления: приложению нужно разрешение
    static func needsNotifications(_ plan: PlannedAction) -> Bool {
        switch plan.operation {
        case .addDebt(let debt)?: return debt.effectiveReminder != .off
        case .updateDebt(let debt)?: return debt.effectiveReminder != .off
        case .addGoal(let goal)?, .updateGoal(let goal)?: return goal.deadline != nil
        case .addReminder?, .updateReminder?: return true
        case .setReminderSetting?: return true
        default: return false
        }
    }
}
