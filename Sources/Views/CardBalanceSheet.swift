import SwiftUI

/// Что делаем с балансом вручную
enum CardBalanceMode: String, Identifiable {
    case topUp
    case reduce

    var id: String { rawValue }
}

/// Чей баланс правим (карта или наличные) и в какую сторону: по этому значению показывается лист
struct CardBalanceRequest: Identifiable {
    let target: BalanceAccount
    let mode: CardBalanceMode

    var id: String { "\(target.storageKey)-\(mode.rawValue)" }
}

/// Ручная правка баланса карты или наличных: сколько добавить или убавить. Это поправка, а не операция: в доходы, расходы и
/// отчёты она не попадает, а новый баланс становится точкой отсчёта для операций (как при правке баланса в редакторе карты).
@MainActor
struct CardBalanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    let target: BalanceAccount
    let mode: CardBalanceMode

    @State private var amountText = ""
    @State private var showsError = false
    @FocusState private var isAmountFocused: Bool

    /// Название счёта и его баланс сейчас; nil, если карты уже нет
    private var subject: (title: String, balance: Double)? {
        switch target {
        case .cash:
            return (String(localized: "Наличные"), financeService.cashBalance)
        case .card(let id):
            guard let card = financeService.cards.first(where: { $0.id == id }) else { return nil }
            return (card.pickerTitle, card.balance)
        }
    }

    private var parsedAmount: Double? {
        guard let value = GoalQuickAmounts.parse(amountText), value > 0 else { return nil }
        return value
    }

    var body: some View {
        Group {
            if let subject {
                form(title: subject.title, balance: subject.balance)
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .monoScreen()
    }

    /// Сумма в базовой валюте, в которой хранятся балансы и в которой вводится поправка: «120 000 ֏»
    private func money(_ value: Double) -> String {
        GoalQuickAmounts.grouped(value) + " " + CurrencyManager.shared.baseCurrency.symbol
    }

    // MARK: - Ввод суммы
    private func form(title: String, balance: Double) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 4) {
                    Text(mode == .topUp ? String(localized: "Пополнение баланса") : String(localized: "Уменьшение баланса"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                    Text(title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(String(localized: "Сейчас: \(money(balance))"))
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.top, 24)

                ZStack(alignment: .trailing) {
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(Theme.number(44, weight: .bold))
                        .foregroundColor(.white)
                        .focused($isAmountFocused)
                        .padding(.horizontal, 44)
                    Text(CurrencyManager.shared.baseCurrency.symbol)
                        .font(Theme.number(26, weight: .bold))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.trailing, 8)
                }

                // «Всё»: убавить ровно столько, сколько есть, то есть довести баланс до нуля
                if mode == .reduce, balance > 0 {
                    allChip(balance: balance)
                }

                outcomeLine(balance: balance)

                PrimaryButton(title: mode == .topUp ? String(localized: "Пополнить") : String(localized: "Убавить")) {
                    submit()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: amountText) { _, _ in
            showsError = false
        }
        .task {
            // Клавиатура поднимается после появления листа: иначе фокус в поле нередко теряется
            guard !ScreenshotMode.isTour else { return }
            try? await Task.sleep(for: .milliseconds(350))
            isAmountFocused = true
        }
    }

    private func allChip(balance: Double) -> some View {
        Button {
            HapticManager.shared.selection()
            amountText = GoalQuickAmounts.plain(balance)
        } label: {
            Text(String(localized: "Всё") + " · " + money(balance))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Theme.surfaceRaised)
                .clipShape(Capsule())
        }
        .buttonStyle(.pressable)
    }

    /// Что получится после правки, либо что не так с суммой
    @ViewBuilder
    private func outcomeLine(balance: Double) -> some View {
        if showsError {
            Text(String(localized: "Введите сумму больше нуля"))
                .font(.system(size: 13))
                .foregroundColor(Color.red)
                .multilineTextAlignment(.center)
        } else if let amount = parsedAmount {
            let after = balance + (mode == .topUp ? amount : -amount)
            Text(String(localized: "Станет: \(money(after))"))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func submit() {
        guard let amount = parsedAmount else {
            fail()
            return
        }
        let delta = mode == .topUp ? amount : -amount
        let isDone: Bool
        switch target {
        case .cash:
            isDone = financeService.adjustCashBalance(by: delta)
        case .card(let id):
            isDone = financeService.adjustCardBalance(id: id, by: delta)
        }
        guard isDone else {
            fail()
            return
        }
        HapticManager.shared.trigger(.success)
        dismiss()
    }

    private func fail() {
        showsError = true
        HapticManager.shared.trigger(.error)
    }
}
