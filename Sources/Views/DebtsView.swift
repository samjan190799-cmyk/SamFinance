import SwiftUI

/// Экран долгов: две суммы сверху, вкладки «Мне должны», «Я должен» и «Платежи» и список с отметкой об оплате.
/// Кредиты лежат на вкладке «Я должен», коммуналка, интернет и подписки — на вкладке «Платежи».
/// Строку можно смахнуть вправо, чтобы отметить оплату, и влево, чтобы удалить; нажатие открывает правку.
struct DebtsView: View {
    let financeService: FinanceService
    @State private var selectedTab: DebtTab = ScreenshotMode.scene == .debts ? .owedToMe : .iOwe
    @State private var isShowingAddSheet = false
    @State private var editingDebt: Debt? = nil

    private var visibleDebts: [Debt] {
        let debts = financeService.debts.filter { selectedTab.contains($0) }
        guard selectedTab == .bills else { return debts }
        // Платежи по порядку сроков: ближайший сверху, оплаченные разовые в конце
        return debts.sorted { lhs, rhs in
            if lhs.isPaid != rhs.isPaid { return !lhs.isPaid }
            return lhs.dueDate < rhs.dueDate
        }
    }

    /// Сколько должны мне и сколько должен я: погашенные долги не считаются
    private var owedToMe: Double {
        total(of: .owedToMe)
    }

    private var iOwe: Double {
        total(of: .iOwe)
    }

    private func total(of tab: DebtTab) -> Double {
        financeService.debts
            .filter { tab.contains($0) && !$0.isPaid }
            .reduce(0.0) { $0 + $1.amount }
    }

    /// Платежи, которые нужно оплатить в ближайшие 30 дней, вместе с просроченными
    private var billsDueSoon: Double {
        let limit = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        return financeService.debts
            .filter { $0.type == .bill && !$0.isPaid && $0.dueDate <= limit }
            .reduce(0.0) { $0 + $1.amount }
    }

    private var billsOverdue: Double {
        let today = Calendar.current.startOfDay(for: Date())
        return financeService.debts
            .filter { $0.type == .bill && !$0.isPaid && $0.dueDate < today }
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
        .animation(Motion.spring, value: selectedTab)
        .monoScreen()
        .sheet(isPresented: $isShowingAddSheet) {
            // Новая запись открывается на своей вкладке, чтобы она не «пропала» после сохранения
            AddDebtView(financeService: financeService, tab: selectedTab) { tab in
                selectedTab = tab
            }
        }
        .sheet(item: $editingDebt) { debt in
            AddDebtView(financeService: financeService, editing: debt) { tab in
                selectedTab = tab
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
            if selectedTab == .bills {
                summaryTile(title: String(localized: "К оплате за 30 дней"), amount: billsDueSoon, highlighted: true)
                summaryTile(title: String(localized: "Просрочено"), amount: billsOverdue, highlighted: false)
            } else {
                summaryTile(title: DebtTab.owedToMe.title, amount: owedToMe, highlighted: selectedTab == .owedToMe)
                summaryTile(title: DebtTab.iOwe.title, amount: iOwe, highlighted: selectedTab == .iOwe)
            }
        }
        .padding(.top, 20)
    }

    private func summaryTile(title: String, amount: Double, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .opacity(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
            options: DebtTab.allCases,
            title: { $0.title },
            selection: $selectedTab
        )
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    // MARK: - Список
    private var emptyText: String {
        switch selectedTab {
        case .owedToMe: return String(localized: "Вам пока никто не должен.")
        case .iOwe: return String(localized: "У вас нет долгов и кредитов.")
        case .bills: return String(localized: "Платежей пока нет. Добавьте коммуналку, интернет или подписку кнопкой «+»: приложение напомнит об оплате и само перенесёт срок на следующий месяц.")
        }
    }

    @ViewBuilder
    private var debtsList: some View {
        let debts = visibleDebts
        if debts.isEmpty {
            VStack(spacing: 8) {
                Text("Пусто")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                Text(emptyText)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 56)
            .padding(.horizontal, 12)
            .transition(.opacity)
            .monoListRow()
        } else {
            ForEach(Array(debts.enumerated()), id: \.element.id) { index, debt in
                DebtRowView(debt: debt, financeService: financeService) {
                    editingDebt = debt
                }
                .appearAnimation(delay: 0.12 + Double(index) * Motion.stagger)
                .monoListRow()
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        togglePaid(debt)
                    } label: {
                        Label(payLabel(for: debt), systemImage: debt.isPaid ? "arrow.uturn.backward" : "checkmark")
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
                    Button {
                        editingDebt = debt
                    } label: {
                        Label("Изменить", systemImage: "pencil")
                    }
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

    private func payLabel(for debt: Debt) -> String {
        if debt.isPaid {
            return String(localized: "Вернуть")
        }
        return debt.type == .bill ? String(localized: "Оплачен") : String(localized: "Погашен")
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

/// Строка долга или платежа: значок, имя, срок и сумма со знаком
struct DebtRowView: View {
    let debt: Debt
    let financeService: FinanceService
    /// Нажатие на строку открывает правку
    var onEdit: () -> Void = {}

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

    /// Срок прошёл, а долг или платёж не закрыт
    private var isOverdue: Bool {
        !debt.isPaid && debt.dueDate < Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                badge

                VStack(alignment: .leading, spacing: 2) {
                    Text(debt.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(debt.isPaid ? Theme.textTertiary : .white)
                        .strikethrough(debt.isPaid)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(isOverdue ? Theme.danger : Theme.textTertiary)
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
                .accessibilityLabel(payAccessibilityLabel)
            }
            .frame(minHeight: 72)
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)
            MonoDivider()
        }
        .background(Theme.background)
    }

    /// У платежа значок его вида, у долга первая буква имени
    @ViewBuilder
    private var badge: some View {
        if debt.type == .bill {
            Image(systemName: (debt.billKind ?? .other).icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(debt.isPaid ? Theme.textTertiary : Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            MonoInitialBadge(title: debt.name)
        }
    }

    private var payAccessibilityLabel: String {
        if debt.isPaid {
            return String(localized: "Вернуть в активные")
        }
        return debt.type == .bill ? String(localized: "Оплатить") : String(localized: "Отметить погашенным")
    }

    private var subtitle: String {
        let date = debt.dueDate.formatted(.dateTime.day().month(.abbreviated))
        if debt.type == .bill {
            return billSubtitle(date: date)
        }
        if debt.isPaid {
            return String(localized: "Погашено · \(date)")
        }
        var line = String(localized: "\(directionText) · до \(date)")
        if isOverdue {
            line += " · " + String(localized: "просрочено")
        }
        // Выключенное напоминание видно сразу: иначе можно пропустить срок, думая, что приложение напомнит
        if debt.effectiveReminder == .off {
            return line + " · " + String(localized: "без напоминания")
        }
        return line
    }

    /// «Интернет · до 5 нояб. · каждый месяц · оплачено 5 окт.»
    private func billSubtitle(date: String) -> String {
        let kind = (debt.billKind ?? .other).title
        if debt.isPaid {
            return String(localized: "\(kind) · оплачено \(date)")
        }
        var parts = [kind, String(localized: "до \(date)")]
        if isOverdue {
            parts.append(String(localized: "просрочено"))
        }
        if debt.isRecurringBill, let rule = debt.repeatRule {
            parts.append(rule.title.lowercased())
        }
        if debt.isRecurringBill, let paidAt = debt.lastPaidAt {
            parts.append(String(localized: "оплачено \(paidAt.formatted(.dateTime.day().month(.abbreviated)))"))
        }
        if debt.effectiveReminder == .off {
            parts.append(String(localized: "без напоминания"))
        }
        return parts.joined(separator: " · ")
    }
}

/// Модальный экран нового долга, кредита или платежа; с `editing` правит существующую запись
struct AddDebtView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    let editing: Debt?
    /// Сообщает, на какой вкладке оказалась сохранённая запись
    let onSave: (DebtTab) -> Void

    @State private var name: String
    @State private var amountString: String
    @State private var isLent: Bool
    @State private var selectedType: DebtType
    @State private var dueDate: Date
    @State private var reminder: DebtReminder
    @State private var billKind: BillKind
    @State private var repeatRule: ReminderRepeat

    /// Форма открывается сразу с типом открытой вкладки: «Мне должны» — долг человека, «Я должен» — кредит,
    /// «Платежи» — платёж с повтором каждый месяц
    init(financeService: FinanceService, tab: DebtTab = .iOwe, editing: Debt? = nil, onSave: @escaping (DebtTab) -> Void = { _ in }) {
        self.financeService = financeService
        self.editing = editing
        self.onSave = onSave

        if let editing {
            _name = State(initialValue: editing.name)
            _amountString = State(initialValue: GoalQuickAmounts.plain(editing.amount))
            _isLent = State(initialValue: editing.isLent)
            _selectedType = State(initialValue: editing.type)
            _dueDate = State(initialValue: editing.dueDate)
            _reminder = State(initialValue: editing.effectiveReminder)
            _billKind = State(initialValue: editing.billKind ?? .utilities)
            _repeatRule = State(initialValue: editing.repeatRule ?? .never)
        } else {
            _name = State(initialValue: "")
            _amountString = State(initialValue: "")
            _isLent = State(initialValue: tab == .owedToMe)
            switch tab {
            case .owedToMe: _selectedType = State(initialValue: .person)
            case .iOwe: _selectedType = State(initialValue: .credit)
            case .bills: _selectedType = State(initialValue: .bill)
            }
            _dueDate = State(initialValue: Date())
            _reminder = State(initialValue: .standard)
            _billKind = State(initialValue: .utilities)
            _repeatRule = State(initialValue: .monthly)
        }
    }

    private var parsedAmount: Double {
        Double(amountString.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var navigationTitleText: String {
        if editing != nil {
            return selectedType == .bill ? String(localized: "Изменить платёж") : String(localized: "Изменить долг")
        }
        return selectedType == .bill ? String(localized: "Новый платёж") : String(localized: "Новый долг")
    }

    var body: some View {
        NavigationStack {
            Form {
                // Тип записи выбирается при создании; у готовой записи он не меняется
                if editing == nil {
                    Section {
                        Picker("Категория долга", selection: $selectedType) {
                            Text("Кредит").tag(DebtType.credit)
                            Text("Человек").tag(DebtType.person)
                            Text("Платёж").tag(DebtType.bill)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedType) { _, newValue in
                            if newValue != .person {
                                isLent = false // Кредит и платёж — всегда «Я должен»
                            }
                        }
                    } header: {
                        Text("Категория")
                    }
                }

                if selectedType == .bill {
                    Section {
                        Picker("Вид платежа", selection: $billKind) {
                            ForEach(BillKind.allCases) { kind in
                                Label(kind.title, systemImage: kind.icon).tag(kind)
                            }
                        }

                        TextField("Название (необязательно)", text: $name)
                            .textInputAutocapitalization(.sentences)

                        amountRow
                    } header: {
                        Text("Информация о платеже")
                    }
                } else {
                    Section {
                        TextField(selectedType == .credit ? String(localized: "Название банка / кредитора") : String(localized: "Имя человека"), text: $name)
                            .textInputAutocapitalization(.words)

                        amountRow
                    } header: {
                        Text("Информация о долге")
                    }
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
                    DatePicker(selectedType == .bill ? String(localized: "Срок оплаты") : String(localized: "Срок возврата"), selection: $dueDate, displayedComponents: .date)
                    if selectedType == .bill {
                        Picker("Повтор", selection: $repeatRule) {
                            ForEach(ReminderRepeat.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    }
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
            .navigationTitle(navigationTitleText)
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

    private var amountRow: some View {
        HStack {
            Text("Сумма (\(CurrencyManager.shared.baseCurrency.symbol))")
            Spacer()
            TextField("0", text: $amountString)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    /// Что именно придёт: для кредита и платежа — об оплате, для человека — вернуть или получить деньги
    private var reminderFooter: String {
        if selectedType == .bill {
            if repeatRule == .never {
                return String(localized: "Напомним об оплате заранее, в день срока и после него, пока платёж не оплачен.")
            }
            return String(localized: "Напомним об оплате заранее, в день срока и после него. Когда вы отметите платёж оплаченным, срок сам перейдёт на следующий период.")
        }
        if selectedType == .credit {
            return String(localized: "Напомним о платеже заранее, в день срока и после него, пока кредит не отмечен погашенным.")
        }
        if isLent {
            return String(localized: "Напомним, когда вам должны вернуть деньги, и ещё раз, если срок пройдёт.")
        }
        return String(localized: "Напомним вернуть деньги заранее, в день срока и после него, пока долг не отмечен погашенным.")
    }

    private var isSaveDisabled: Bool {
        // У платежа имя необязательно: без него берётся вид платежа («Интернет»)
        let needsName = selectedType != .bill
        let nameMissing = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (needsName && nameMissing) || parsedAmount <= 0
    }

    private func saveDebt() {
        guard parsedAmount > 0 else { return }
        let isBill = selectedType == .bill
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let day = Calendar.current.startOfDay(for: dueDate)

        // Первый срок платежа остаётся прежним, пока дату не поменяли: от него считаются следующие сроки
        var firstDue: Date? = nil
        if isBill {
            let unchanged = editing.map { Calendar.current.isDate($0.dueDate, inSameDayAs: day) } ?? false
            firstDue = (unchanged ? editing?.firstDueDate : nil) ?? day
        }

        let debt = Debt(
            id: editing?.id ?? UUID(),
            name: isBill && cleanName.isEmpty ? billKind.title : cleanName,
            amount: parsedAmount,
            dueDate: isBill ? day : dueDate,
            isLent: selectedType == .person ? isLent : false,
            isPaid: false,
            type: selectedType,
            reminder: reminder,
            billKind: isBill ? billKind : nil,
            repeatRule: isBill ? repeatRule : nil,
            firstDueDate: firstDue,
            lastPaidAt: editing?.lastPaidAt
        )
        if editing == nil {
            financeService.addDebt(debt)
        } else {
            financeService.updateDebt(debt)
        }
        onSave(DebtTab(debt: debt))
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
