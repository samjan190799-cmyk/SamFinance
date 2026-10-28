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

/// Небольшое окно с суммой: сколько вышло по платежу, сколько внесли в этом месяце по кредиту или какую часть долга вернули
struct DebtPaymentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    let request: DebtPaymentRequest
    @State private var amountString: String

    init(financeService: FinanceService, request: DebtPaymentRequest) {
        self.financeService = financeService
        self.request = request
        _amountString = State(initialValue: Self.suggestion(for: request))
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
        .presentationDetents([.medium])
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
        switch request.mode {
        case .payment:
            financeService.payDebt(id: debt.id, amount: value)
        case .part:
            financeService.repayDebt(id: debt.id, amount: value)
        }
        HapticManager.shared.trigger(.success)
        dismiss()
    }
}
