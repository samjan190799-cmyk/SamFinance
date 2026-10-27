import SwiftUI

/// Экран долгов: две суммы сверху, вкладки «Мне должны» и «Я должен» и список с отметкой о погашении.
/// Кредиты лежат на вкладке «Я должен». Строку можно смахнуть вправо, чтобы отметить погашение, и влево, чтобы удалить.
struct DebtsView: View {
    let financeService: FinanceService
    @State private var selectedSide: DebtSide = ScreenshotMode.scene == .debts ? .owedToMe : .iOwe
    @State private var isShowingAddSheet = false

    private var visibleDebts: [Debt] {
        financeService.debts.filter { selectedSide.contains($0) }
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
        // List, а не ScrollView: строкам нужны системные жесты смахивания
        List {
            Group {
                headerView
                    .appearAnimation(order: 0)
                summaryView
                    .appearAnimation(order: 1)
                segmentView
                    .appearAnimation(order: 2)
            }
            .monoListRow()

            debtsList
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .animation(Motion.spring, value: selectedSide)
        .monoScreen()
        .sheet(isPresented: $isShowingAddSheet) {
            // Новый долг открывается на своей вкладке, чтобы он не «пропал» после сохранения
            AddDebtView(financeService: financeService, side: selectedSide) { side in
                selectedSide = side
            }
        }
    }

    // MARK: - Шапка
    private var headerView: some View {
        HStack {
            Text("debts_title".localized)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Spacer()
            MonoCircleButton(systemName: "plus", label: "add_debt".localized, filled: true) {
                HapticManager.shared.impact(.light)
                isShowingAddSheet = true
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Итоги
    private var summaryView: some View {
        HStack(spacing: 10) {
            summaryTile(title: DebtSide.owedToMe.title, amount: owedToMe, highlighted: selectedSide == .owedToMe)
            summaryTile(title: DebtSide.iOwe.title, amount: iOwe, highlighted: selectedSide == .iOwe)
        }
        .padding(.top, 20)
    }

    private func summaryTile(title: String, amount: Double, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .opacity(0.8)
            Text(CurrencyManager.shared.format(amount))
                .font(Theme.number(24, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText(value: amount))
                .animation(Motion.digits, value: amount)
        }
        .foregroundColor(highlighted ? Theme.onAccent : .white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlighted ? Theme.accent : Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - Переключатель
    private var segmentView: some View {
        MonoSegmentedControl(
            options: DebtSide.allCases,
            title: { $0.title },
            selection: $selectedSide
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
                Text(selectedSide == .owedToMe ? String(localized: "Вам пока никто не должен.") : String(localized: "У вас нет долгов и кредитов."))
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 56)
            .transition(.opacity)
            .monoListRow()
        } else {
            ForEach(Array(debts.enumerated()), id: \.element.id) { index, debt in
                DebtRowView(debt: debt, financeService: financeService)
                    .appearAnimation(delay: 0.12 + Double(index) * Motion.stagger)
                    .monoListRow()
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            togglePaid(debt)
                        } label: {
                            Label(debt.isPaid ? String(localized: "Вернуть") : String(localized: "Погашен"), systemImage: debt.isPaid ? "arrow.uturn.backward" : "checkmark")
                        }
                        .tint(debt.isPaid ? Theme.surfaceRaised : Theme.accentStrong)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            delete(debt)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        if !debt.isPaid {
                            reminderMenu(debt)
                        }
                        Button(role: .destructive) {
                            delete(debt)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }

    /// Когда заранее напомнить о сроке: выбор прямо из меню строки
    private func reminderMenu(_ debt: Debt) -> some View {
        Menu {
            ForEach(DebtReminder.allCases) { option in
                Button {
                    HapticManager.shared.selection()
                    financeService.setDebtReminder(id: debt.id, reminder: option)
                    if option != .off {
                        Task {
                            _ = await PurchasePromptService.shared.requestAuthorization()
                        }
                    }
                } label: {
                    if option == debt.effectiveReminder {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            Label("Напоминание", systemImage: debt.effectiveReminder == .off ? "bell.slash" : "bell")
        }
    }

    private func togglePaid(_ debt: Debt) {
        HapticManager.shared.trigger(.success)
        withAnimation(Motion.spring) {
            financeService.togglePayDebt(id: debt.id)
        }
    }

    private func delete(_ debt: Debt) {
        HapticManager.shared.trigger(.warning)
        withAnimation(Motion.spring) {
            financeService.deleteDebt(id: debt.id)
        }
    }
}

/// Строка долга: кружок с первой буквой, имя, срок и сумма со знаком
struct DebtRowView: View {
    let debt: Debt
    let financeService: FinanceService

    private var directionText: String {
        if debt.type == .credit {
            return String(localized: "Кредит")
        }
        return debt.isLent ? String(localized: "Мне должны") : String(localized: "Я должен")
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
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text("\(debt.isLent ? "+" : "−")\(CurrencyManager.shared.format(debt.amount))")
                    .font(Theme.number(16))
                    .foregroundColor(amountColor)
                    .strikethrough(debt.isPaid)

                Button {
                    HapticManager.shared.trigger(.success)
                    withAnimation(Motion.spring) {
                        financeService.togglePayDebt(id: debt.id)
                    }
                } label: {
                    Image(systemName: debt.isPaid ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(debt.isPaid ? Theme.accent : Theme.textTertiary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                }
                // Кнопка только в своей рамке: в List без этого нажатие на всю строку отмечало бы погашение
                .buttonStyle(.borderless)
                .accessibilityLabel(debt.isPaid ? String(localized: "Вернуть в активные") : String(localized: "Отметить погашенным"))
            }
            .frame(minHeight: 72)
            .contentShape(Rectangle())
            MonoDivider()
        }
        .background(Theme.background)
    }

    private var subtitle: String {
        let date = debt.dueDate.formatted(.dateTime.day().month(.abbreviated))
        if debt.isPaid {
            return String(localized: "Погашено · \(date)")
        }
        let line = String(localized: "\(directionText) · до \(date)")
        // Выключенное напоминание видно сразу: иначе можно пропустить срок, думая, что приложение напомнит
        if debt.effectiveReminder == .off {
            return line + " · " + String(localized: "без напоминания")
        }
        return line
    }
}

/// Модальный экран создания нового долга
struct AddDebtView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    /// Сообщает, на какой вкладке оказался сохранённый долг
    let onSave: (DebtSide) -> Void

    @State private var name: String = ""
    @State private var amountString: String = ""
    @State private var isLent: Bool
    @State private var selectedType: DebtType
    @State private var dueDate: Date = Date()
    @State private var reminder: DebtReminder = .standard

    /// Форма открывается сразу с направлением открытой вкладки: «Мне должны» — долг человека, «Я должен» — кредит
    init(financeService: FinanceService, side: DebtSide = .iOwe, onSave: @escaping (DebtSide) -> Void = { _ in }) {
        self.financeService = financeService
        self.onSave = onSave
        _isLent = State(initialValue: side == .owedToMe)
        _selectedType = State(initialValue: side == .owedToMe ? .person : .credit)
    }

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
                    TextField(selectedType == .credit ? String(localized: "Название банка / кредитора") : String(localized: "Имя человека"), text: $name)
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
                    Picker("Напомнить", selection: $reminder) {
                        ForEach(DebtReminder.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } header: {
                    Text("Сроки")
                } footer: {
                    if reminder != .off {
                        Text(reminderFooter)
                    }
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

    /// Что именно придёт: для кредита — о платеже, для человека — вернуть или получить деньги
    private var reminderFooter: String {
        if selectedType == .credit {
            return String(localized: "Напомним о платеже заранее, в день срока и после него, пока кредит не отмечен погашенным.")
        }
        if isLent {
            return String(localized: "Напомним, когда вам должны вернуть деньги, и ещё раз, если срок пройдёт.")
        }
        return String(localized: "Напомним вернуть деньги заранее, в день срока и после него, пока долг не отмечен погашенным.")
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
            type: selectedType,
            reminder: reminder
        )
        financeService.addDebt(debt)
        onSave(DebtSide(debt: debt))
        if reminder != .off {
            Task {
                // Разрешение нужно для напоминаний о сроке долга
                _ = await PurchasePromptService.shared.requestAuthorization()
            }
        }
        HapticManager.shared.trigger(.success)
        dismiss()
    }
}
