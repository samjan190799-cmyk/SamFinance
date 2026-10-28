import SwiftUI

/// О чём спрашивает окно оплаты
struct DebtPaymentRequest: Identifiable {
    enum Mode {
        /// Обычная оплата: платёж по кредиту или платёж, у которого сумма каждый раз другая
        case payment
        /// Взнос в счёт долга: остаток уменьшается, срок не меняется
        case part
    }

    let debt: Debt
    let mode: Mode

    var id: String {
        "\(debt.id.uuidString).\(mode == .payment ? "payment" : "part")"
    }
}

/// Выбор карты для записи оплаты. Подписи и пояснения зависят от того, уходят деньги с карты или приходят на неё.
struct PaymentCardSection: View {
    let cards: [Card]
    /// Деньги приходят на карту (должник вернул долг), а не уходят с неё
    let isIncome: Bool
    @Binding var cardID: UUID?

    private var title: String {
        isIncome ? String(localized: "Зачислить на карту") : String(localized: "Списать с карты")
    }

    private var footer: String {
        guard cardID != nil else {
            return String(localized: "Оплата отметится только в долгах: операции и баланс карт не изменятся.")
        }
        return isIncome
            ? String(localized: "Доход запишется в операции, а баланс карты увеличится.")
            : String(localized: "Расход запишется в операции, а баланс карты уменьшится.")
    }

    var body: some View {
        Section {
            Picker(title, selection: $cardID) {
                Text("Не записывать").tag(UUID?.none)
                ForEach(cards) { card in
                    Text(card.pickerTitle).tag(Optional(card.id))
                }
            }
        } footer: {
            Text(footer)
        }
    }
}

/// Небольшое окно с суммой: сколько вышло по платежу, сколько внесли в этом месяце по кредиту или какую часть долга вернули.
/// Если в приложении есть карты, здесь же выбирается карта, на которую записывается оплата.
struct DebtPaymentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    let request: DebtPaymentRequest
    @State private var amountString: String
    @State private var cardID: UUID?

    init(financeService: FinanceService, request: DebtPaymentRequest) {
        self.financeService = financeService
        self.request = request
        _amountString = State(initialValue: Self.suggestion(for: request))
        // Карта записи подставляется, если она ещё есть в приложении
        let preferred = request.debt.cardId.flatMap { id in financeService.cards.contains { $0.id == id } ? id : nil }
        _cardID = State(initialValue: preferred)
    }

    /// Платёж по кредиту и сумма платежа подставляются, часть долга вводится с нуля
    static func suggestion(for request: DebtPaymentRequest) -> String {
        guard request.mode == .payment else { return "" }
        let debt = request.debt
        return GoalQuickAmounts.plain(debt.hasPaymentPlan ? (debt.monthlyPayment ?? debt.amount) : debt.amount)
    }

    private var debt: Debt { request.debt }

    private var value: Double? {
        guard let value = GoalQuickAmounts.parse(amountString), value > 0 else { return nil }
        return value
    }

    private var fieldTitle: String {
        debt.type == .bill ? String(localized: "Сколько вышло") : String(localized: "Сколько внесли")
    }

    private var screenTitle: String {
        request.mode == .part ? String(localized: "Частичная оплата") : String(localized: "Оплата")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(verbatim: "\(fieldTitle) (\(CurrencyManager.shared.baseCurrency.symbol))")
                        Spacer()
                        TextField("0", text: $amountString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text(debt.name)
                } footer: {
                    Text(footer)
                }

                if !financeService.cards.isEmpty {
                    PaymentCardSection(cards: financeService.cards, isIncome: debt.paymentType == .income, cardID: $cardID)
                }
            }
            .monoForm()
            .navigationTitle(screenTitle)
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
                    .disabled(value == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var footer: String {
        let money = CurrencyManager.shared
        if request.mode == .part {
            let left = max(0, debt.amount - (value ?? 0))
            return String(localized: "Остаток после взноса: \(money.format(left))")
        }
        if debt.hasPaymentPlan {
            if (debt.interestRate ?? 0) > 0 {
                return String(localized: "Часть платежа пойдёт на проценты, остаток долга уменьшится на разницу. Срок перейдёт на следующий месяц.")
            }
            return String(localized: "Остаток долга уменьшится на эту сумму, срок перейдёт на следующий месяц.")
        }
        return String(localized: "Запомним эту сумму: в следующий раз ждём столько же. Срок перейдёт на следующий период.")
    }

    private func save() {
        guard let value else { return }
        let source: PaymentSource = cardID.map { .card($0) } ?? .notRecorded
        switch request.mode {
        case .payment:
            financeService.payDebt(id: debt.id, amount: value, source: source)
        case .part:
            financeService.repayDebt(id: debt.id, amount: value, source: source)
        }
        HapticManager.shared.trigger(.success)
        dismiss()
    }
}
