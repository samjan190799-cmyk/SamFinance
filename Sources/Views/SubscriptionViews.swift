import SwiftUI
import UIKit

/// Строка подписки: значок вида, название, ближайшее списание и сумма в валюте подписки.
/// Нажатие открывает правку; смахивания и меню действий добавляет экран долгов.
struct SubscriptionRowView: View {
    let subscription: AppSubscription
    /// «•••• 1234»: карта списания, если она указана и ещё есть в приложении
    var cardTitle: String? = nil
    var onEdit: () -> Void = {}

    private var isInactive: Bool {
        !subscription.isActive
    }

    /// Цвет вида; у подписок на паузе и в архиве серый
    private var tint: Color {
        isInactive ? Theme.textTertiary : subscription.category.palette.color
    }

    /// Дней до списания, пока подписка активна
    private var daysLeft: Int? {
        subscription.daysUntilNextCharge()
    }

    /// Ближайшее списание или состояние подписки
    private var headline: String {
        guard subscription.isActive else { return subscription.status.title }
        guard let next = subscription.nextChargeDate(), let days = daysLeft else { return subscription.category.title }
        return SubscriptionDateText.charge(days: days, date: next)
    }

    /// Скорое списание выделено цветом: за три дня и меньше
    private var headlineColor: Color {
        if let days = daysLeft, days <= 3 {
            return PaletteColor.peach.color
        }
        return Theme.textTertiary
    }

    /// «каждый месяц · Видео · •••• 1234 · ≈ 14 400 ֏ в год»
    private var details: String {
        var parts = [subscription.period.repeatRule.title(every: subscription.effectiveInterval).lowercased()]
        parts.append(subscription.category.title)
        if let cardTitle {
            parts.append(cardTitle)
        }
        // Для дорогой подписки с редким списанием полезнее видеть, сколько она стоит за год
        if subscription.period != .yearly || subscription.effectiveInterval > 1 {
            let yearly = subscription.currency.formatAmount(subscription.costPerYear)
            parts.append(String(localized: "≈ \(yearly) в год"))
        }
        if subscription.isActive && subscription.effectiveReminder == .off {
            parts.append(String(localized: "без напоминания"))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    TintedIconBadge(systemName: subscription.category.icon, tint: tint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(subscription.name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(isInactive ? Theme.textTertiary : .white)
                            .lineLimit(2)
                        Text(headline)
                            .font(.system(size: 13))
                            .foregroundColor(subscription.isActive ? headlineColor : Theme.textTertiary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    Text(subscription.currency.formatAmount(subscription.amount))
                        .font(Theme.number(16))
                        .foregroundColor(isInactive ? Theme.textTertiary : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(minHeight: 72)

                // Отступ слева: значок 44 и промежуток 14, чтобы строка стояла ровно под названием
                Text(details)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 58)
                    .padding(.bottom, 12)

                if let note = subscription.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 58)
                        .padding(.bottom, 12)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            MonoDivider()
        }
        .background(Theme.background)
    }
}

/// Модальный экран новой подписки; с `editing` правит существующую
struct SubscriptionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    let editing: AppSubscription?

    @State private var name: String
    @State private var amountString: String
    @State private var currency: AppCurrency
    @State private var category: SubscriptionCategory
    @State private var period: SubscriptionPeriod
    @State private var interval: Int
    @State private var chargeDate: Date
    @State private var reminder: DebtReminder
    /// Карта списания; пусто — не указана
    @State private var cardID: UUID?
    @State private var status: SubscriptionStatus
    @State private var note: String
    /// Какую дату форма показала при открытии: пока её не меняли, первая дата подписки остаётся прежней,
    /// иначе подписка «31-го числа» после правки застряла бы на 28-м
    private let shownChargeDate: Date

    init(financeService: FinanceService, editing: AppSubscription? = nil) {
        self.financeService = financeService
        self.editing = editing

        if let editing {
            // Форма показывает ближайшее списание, а не давнюю первую дату
            let shown = editing.nextOccurrence() ?? editing.firstChargeDate
            shownChargeDate = shown
            _name = State(initialValue: editing.name)
            _amountString = State(initialValue: GoalQuickAmounts.plain(editing.amount))
            _currency = State(initialValue: editing.currency)
            _category = State(initialValue: editing.category)
            _period = State(initialValue: editing.period)
            _interval = State(initialValue: editing.effectiveInterval)
            _chargeDate = State(initialValue: shown)
            _reminder = State(initialValue: editing.effectiveReminder)
            _cardID = State(initialValue: Self.knownCard(editing.cardId, in: financeService))
            _status = State(initialValue: editing.status)
            _note = State(initialValue: editing.note ?? "")
        } else {
            let today = Calendar.current.startOfDay(for: Date())
            shownChargeDate = today
            _name = State(initialValue: "")
            _amountString = State(initialValue: "")
            // Подписки чаще оплачивают в валюте, в которой пользователь смотрит на свои деньги
            _currency = State(initialValue: CurrencyManager.shared.currentCurrency)
            _category = State(initialValue: .video)
            _period = State(initialValue: .monthly)
            _interval = State(initialValue: 1)
            _chargeDate = State(initialValue: today)
            _reminder = State(initialValue: .standard)
            _cardID = State(initialValue: nil)
            _status = State(initialValue: .active)
            _note = State(initialValue: "")
        }
    }

    /// Карта, которая ещё есть в приложении: удалённая карта не подставляется
    private static func knownCard(_ id: UUID?, in financeService: FinanceService) -> UUID? {
        guard let id, financeService.cards.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    private var parsedAmount: Double {
        GoalQuickAmounts.parse(amountString) ?? 0
    }

    private var cleanName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSaveDisabled: Bool {
        cleanName.isEmpty || parsedAmount <= 0
    }

    /// Ближайшее списание по выбранной дате и периоду: если выбрана прошедшая дата, подписка сама найдёт следующую
    private var nextChargeText: String {
        let preview = AppSubscription(
            name: "",
            amount: 1,
            period: period,
            interval: interval > 1 ? interval : nil,
            firstChargeDate: Calendar.current.startOfDay(for: chargeDate)
        )
        guard let next = preview.nextOccurrence() else { return "" }
        let date = DebtDateText.due(next)
        return String(localized: "Следующее списание: \(date)")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название", text: $name)
                        .textInputAutocapitalization(.words)
                    HStack {
                        Text("Сумма")
                        Spacer()
                        TextField("0", text: $amountString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Валюта", selection: $currency) {
                        ForEach(AppCurrency.allCases) { option in
                            Text("\(option.flagIcon) \(option.rawValue) \(option.symbol)").tag(option)
                        }
                    }
                    Picker("Категория", selection: $category) {
                        ForEach(SubscriptionCategory.allCases) { option in
                            Label(option.title, systemImage: option.icon).tag(option)
                        }
                    }
                } header: {
                    Text("Подписка")
                }

                Section {
                    Picker("Период", selection: $period) {
                        ForEach(SubscriptionPeriod.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    Stepper(value: $interval, in: 1...36) {
                        Text(period.repeatRule.title(every: interval))
                    }
                    DatePicker("Ближайшее списание", selection: $chargeDate, displayedComponents: .date)
                } header: {
                    Text("Списание")
                } footer: {
                    Text(nextChargeText)
                }

                Section {
                    Picker("Напомнить", selection: $reminder) {
                        ForEach(DebtReminder.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } header: {
                    Text("Напоминание")
                } footer: {
                    if reminder != .off {
                        Text("Напомним о списании заранее: успеете отказаться, если подписка больше не нужна.")
                    }
                }

                if !financeService.cards.isEmpty {
                    Section {
                        Picker("Карта списания", selection: $cardID) {
                            Text("Не указана").tag(UUID?.none)
                            ForEach(financeService.cards) { card in
                                Text(card.pickerTitle).tag(Optional(card.id))
                            }
                        }
                    } footer: {
                        Text("Карта только подписывает подписку: операции и баланс карты не изменятся.")
                    }
                }

                if editing != nil {
                    Section {
                        Picker("Статус", selection: $status) {
                            ForEach(SubscriptionStatus.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Статус")
                    } footer: {
                        Text("Подписка на паузе или в архиве не входит в итоги и не напоминает о списании.")
                    }
                }

                Section {
                    TextField("Заметка (необязательно)", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("Заметка")
                }
            }
            .monoForm()
            .navigationTitle(editing == nil ? String(localized: "Новая подписка") : String(localized: "Изменить подписку"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        save()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
    }

    private func save() {
        guard !isSaveDisabled else { return }
        let calendar = Calendar.current
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let day = calendar.startOfDay(for: chargeDate)
        // Первая дата остаётся прежней, пока дату не поменяли: от неё считаются все следующие списания
        let unchanged = editing != nil && calendar.isDate(chargeDate, inSameDayAs: shownChargeDate)

        var subscription = editing ?? AppSubscription(name: cleanName, amount: parsedAmount)
        subscription.name = cleanName
        subscription.amount = parsedAmount
        subscription.currency = currency
        subscription.category = category
        subscription.period = period
        subscription.interval = interval > 1 ? interval : nil
        subscription.firstChargeDate = (unchanged ? editing?.firstChargeDate : nil) ?? day
        subscription.reminder = reminder
        subscription.cardId = Self.knownCard(cardID, in: financeService)
        subscription.status = editing == nil ? .active : status
        subscription.note = cleanNote.isEmpty ? nil : cleanNote

        if editing == nil {
            financeService.addSubscription(subscription)
        } else {
            financeService.updateSubscription(subscription)
        }
        if reminder != .off {
            Task {
                // Разрешение нужно для напоминаний о списании
                _ = await PurchasePromptService.shared.requestAuthorization()
            }
        }
        HapticManager.shared.trigger(.success)
        dismiss()
    }
}
