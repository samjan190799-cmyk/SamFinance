import SwiftUI

/// Экран долгов: две суммы сверху, переключатель «Кредиты / Люди» и список с отметкой о погашении.
struct DebtsView: View {
    let financeService: FinanceService
    @State private var selectedSegment = 0 // 0: Кредиты, 1: Люди
    @State private var isShowingAddSheet = false

    private var visibleDebts: [Debt] {
        financeService.debts.filter { debt in
            selectedSegment == 0 ? debt.type == .credit : debt.type == .person
        }
    }

    /// Сколько должны мне и сколько должен я: погашенные долги не считаются
    private var owedToMe: Double {
        financeService.debts
            .filter { $0.isLent && !$0.isPaid }
            .reduce(0.0) { $0 + $1.amount }
    }

    private var iOwe: Double {
        financeService.debts
            .filter { !$0.isLent && !$0.isPaid }
            .reduce(0.0) { $0 + $1.amount }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerView
                summaryView
                segmentView
                debtsList
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .monoScreen()
        .sheet(isPresented: $isShowingAddSheet) {
            AddDebtView(financeService: financeService)
        }
    }

    // MARK: - Шапка
    private var headerView: some View {
        HStack {
            Text("debts_title".localized)
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.5)
                .foregroundColor(.white)
            Spacer()
            MonoCircleButton(systemName: "plus", label: "add_debt".localized) {
                HapticManager.shared.impact(.light)
                isShowingAddSheet = true
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Итоги
    private var summaryView: some View {
        HStack(alignment: .top, spacing: 0) {
            summaryColumn(title: "Мне должны", amount: owedToMe, color: Theme.accent)

            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 1)

            summaryColumn(title: "Я должен", amount: iOwe, color: .white)
                .padding(.leading, 24)
        }
        .padding(.vertical, 20)
        .overlay(alignment: .top) { MonoDivider() }
        .overlay(alignment: .bottom) { MonoDivider() }
        .padding(.top, 28)
    }

    private func summaryColumn(title: String, amount: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel(text: title)
            Text(CurrencyManager.shared.format(amount))
                .font(.system(size: 26, weight: .light))
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Переключатель
    private var segmentView: some View {
        MonoSegmentedControl(
            options: [0, 1],
            title: { $0 == 0 ? "credits_tab".localized : "people_tab".localized },
            selection: $selectedSegment
        )
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    // MARK: - Список
    @ViewBuilder
    private var debtsList: some View {
        let debts = visibleDebts
        if debts.isEmpty {
            VStack(spacing: 8) {
                Text("Пусто")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                Text(selectedSegment == 0 ? "У вас нет активных кредитов." : "У вас нет активных долгов людям.")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 56)
        } else {
            VStack(spacing: 0) {
                ForEach(debts) { debt in
                    DebtRowView(debt: debt, financeService: financeService)
                        .contextMenu {
                            Button(role: .destructive) {
                                HapticManager.shared.trigger(.warning)
                                withAnimation {
                                    financeService.deleteDebt(id: debt.id)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }
}

/// Строка долга: кружок с первой буквой, имя, срок и сумма со знаком
struct DebtRowView: View {
    let debt: Debt
    let financeService: FinanceService

    private var directionText: String {
        if debt.type == .credit {
            return "Кредит"
        }
        return debt.isLent ? "Мне должны" : "Я должен"
    }

    private var amountColor: Color {
        if debt.isPaid {
            return Theme.textTertiary
        }
        return debt.isLent ? Theme.accent : .white
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                MonoInitialBadge(title: debt.name)

                VStack(alignment: .leading, spacing: 2) {
                    Text(debt.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(debt.isPaid ? Theme.textTertiary : .white)
                        .strikethrough(debt.isPaid)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text("\(debt.isLent ? "+" : "−")\(CurrencyManager.shared.format(debt.amount))")
                    .font(.system(size: 16))
                    .monospacedDigit()
                    .foregroundColor(amountColor)
                    .strikethrough(debt.isPaid)

                Button {
                    HapticManager.shared.trigger(.success)
                    withAnimation {
                        financeService.togglePayDebt(id: debt.id)
                    }
                } label: {
                    Image(systemName: debt.isPaid ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(debt.isPaid ? Theme.accent : Theme.textTertiary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(debt.isPaid ? "Вернуть в активные" : "Отметить погашенным")
            }
            .frame(minHeight: 72)
            MonoDivider()
        }
    }

    private var subtitle: String {
        let date = debt.dueDate.formatted(.dateTime.day().month(.abbreviated))
        if debt.isPaid {
            return "Погашено · \(date)"
        }
        return "\(directionText) · до \(date)"
    }
}

/// Модальный экран создания нового долга
struct AddDebtView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService

    @State private var name: String = ""
    @State private var amountString: String = ""
    @State private var isLent: Bool = false
    @State private var selectedType: DebtType = .credit
    @State private var dueDate: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Категория долга", selection: $selectedType) {
                        Text("Кредит").tag(DebtType.credit)
                        Text("Человек").tag(DebtType.person)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedType) { _, newValue in
                        if newValue == .credit {
                            isLent = false // Кредит - всегда "Я должен"
                        }
                    }
                } header: {
                    Text("Категория")
                }

                Section {
                    TextField(selectedType == .credit ? "Название банка / кредитора" : "Имя человека", text: $name)
                        .textInputAutocapitalization(.words)

                    HStack {
                        Text("Сумма (\(CurrencyManager.shared.baseCurrency.symbol))")
                        Spacer()
                        TextField("0", text: $amountString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Информация о долге")
                }

                if selectedType == .person {
                    Section {
                        Picker("Кто кому должен", selection: $isLent) {
                            Text("Мне должны").tag(true)
                            Text("Я должен").tag(false)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Направление")
                    }
                }

                Section {
                    DatePicker("Срок возврата", selection: $dueDate, displayedComponents: .date)
                } header: {
                    Text("Сроки")
                }
            }
            .monoForm()
            .navigationTitle("Новый долг")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        saveDebt()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
    }

    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        Double(amountString.replacingOccurrences(of: ",", with: ".")) ?? 0 <= 0
    }

    private func saveDebt() {
        guard let amount = Double(amountString.replacingOccurrences(of: ",", with: ".")) else { return }
        let debt = Debt(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            dueDate: dueDate,
            isLent: selectedType == .credit ? false : isLent,
            isPaid: false,
            type: selectedType
        )
        financeService.addDebt(debt)
        HapticManager.shared.trigger(.success)
        dismiss()
    }
}
