import SwiftUI
import UIKit

/// Экран долгов: две суммы сверху, вкладки «Мне должны», «Я должен» и «Платежи» и список с отметкой об оплате.
/// Кредиты лежат на вкладке «Я должен», коммуналка, интернет и подписки — на вкладке «Платежи».
/// Строку можно смахнуть вправо, чтобы отметить оплату, и влево, чтобы удалить; нажатие открывает правку.
struct DebtsView: View {
    let financeService: FinanceService
    @State private var selectedTab: DebtTab = ScreenshotMode.scene == .debts ? .owedToMe : .iOwe
    @State private var isShowingAddSheet = false
    @State private var isShowingTypeSettings = false
    @State private var editingDebt: Debt? = nil
    @State private var paymentRequest: DebtPaymentRequest? = nil
    /// Настройки видов записей: по ним строки показывают, придёт ли напоминание
    @State private var typeSettings = DebtTypeSettings.load()

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
        .sheet(item: $paymentRequest) { request in
            DebtPaymentSheet(financeService: financeService, request: request)
        }
        .sheet(isPresented: $isShowingTypeSettings, onDismiss: {
            typeSettings = DebtTypeSettings.load()
        }) {
            NavigationStack {
                DebtTypeSettingsView(financeService: financeService, showsDoneButton: true)
            }
        }
    }

    // MARK: - Шапка
    private var headerView: some View {
        HStack(spacing: 10) {
            Text("debts_title".localized)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Spacer()
            MonoCircleButton(systemName: "slider.horizontal.3", label: String(localized: "Настройки по видам")) {
                HapticManager.shared.impact(.light)
                isShowingTypeSettings = true
            }
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
                DebtRowView(debt: debt, typeSettings: typeSettings, onEdit: {
                    editingDebt = debt
                }, onTogglePaid: {
                    togglePaid(debt)
                })
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
                    if !debt.isPaid && !debt.isRecurringBill {
                        Button {
                            paymentRequest = DebtPaymentRequest(debt: debt, mode: .part)
                        } label: {
                            Label(debt.type == .credit ? String(localized: "Внести досрочно") : String(localized: "Внести часть"), systemImage: "plus.circle")
                        }
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
        let current = debt.effectiveReminder(using: typeSettings)
        return Menu {
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
                    if option == current {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            Label("Напоминание", systemImage: current == .off ? "bell.slash" : "bell")
        }
    }

    /// Платёж с переменной суммой и платёж по кредиту сначала спрашивают сумму, остальное отмечается сразу
    private func togglePaid(_ debt: Debt) {
        if debt.asksAmountBeforePaying {
            paymentRequest = DebtPaymentRequest(debt: debt, mode: .payment)
            return
        }
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
    /// Настройки видов записей: по ним видно, придёт ли напоминание
    var typeSettings = DebtTypeSettings()
    /// Нажатие на строку открывает правку
    var onEdit: () -> Void = {}
    /// Кнопка с кружком: оплата или возврат в активные
    var onTogglePaid: () -> Void = {}

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
                    if let note = debt.note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text("\(debt.isLent ? "+" : "−")\(amountPrefix)\(CurrencyManager.shared.format(debt.amount))")
                    .font(Theme.number(16))
                    .foregroundColor(amountColor)
                    .strikethrough(debt.isPaid)

                Button(action: onTogglePaid) {
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

    /// Сумма платежа с меняющейся суммой приблизительная: настоящая станет известна при оплате
    private var amountPrefix: String {
        debt.isRecurringBill && debt.isVariableAmount == true && !debt.isPaid ? "≈ " : ""
    }

    /// Придёт ли напоминание: вид записи может быть выключен целиком, а у самой записи оно может быть выключено
    private var remindsAboutDebt: Bool {
        typeSettings.setting(for: debt).isEnabled && debt.effectiveReminder(using: typeSettings) != .off
    }

    private func money(_ value: Double) -> String {
        CurrencyManager.shared.format(value)
    }

    private var subtitle: String {
        let date = debt.dueDate.formatted(.dateTime.day().month(.abbreviated))
        if debt.type == .bill {
            return billSubtitle(date: date)
        }
        if debt.isPaid {
            return String(localized: "Погашено · \(date)")
        }
        var parts = [directionText, String(localized: "до \(date)")]
        if isOverdue {
            parts.append(String(localized: "просрочено"))
        }
        if debt.type == .credit {
            parts += creditDetails
        }
        if debt.hasPartialPayments, let original = debt.originalAmount {
            parts.append(String(localized: "из \(money(original))"))
        }
        // Выключенное напоминание видно сразу: иначе можно пропустить срок, думая, что приложение напомнит
        if !remindsAboutDebt {
            parts.append(String(localized: "без напоминания"))
        }
        return parts.joined(separator: " · ")
    }

    /// «платёж 12 000 · ставка 14% · осталось платежей: 18» у кредита с графиком
    private var creditDetails: [String] {
        var parts: [String] = []
        if let payment = debt.monthlyPayment, payment > 0 {
            parts.append(String(localized: "платёж \(money(payment))"))
        }
        if let rate = debt.interestRate, rate > 0 {
            let percent = GoalQuickAmounts.plain(rate) + "%"
            parts.append(String(localized: "ставка \(percent)"))
        }
        if let left = debt.paymentsLeft {
            parts.append(String(localized: "осталось платежей: \(left)"))
        }
        return parts
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
        if debt.isRecurringBill {
            parts.append(debt.effectiveRepeat.title(every: debt.effectiveInterval).lowercased())
        }
        if debt.hasPartialPayments, let original = debt.originalAmount {
            parts.append(String(localized: "из \(money(original))"))
        }
        if debt.isRecurringBill, let paidAt = debt.lastPaidAt {
            parts.append(String(localized: "оплачено \(paidAt.formatted(.dateTime.day().month(.abbreviated)))"))
            if debt.isVariableAmount == true, let paid = debt.lastPaidAmount {
                parts.append(money(paid))
            }
        }
        if !remindsAboutDebt {
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
    /// Настройки видов записей: по ним заполняется новая запись
    private let typeSettings: DebtTypeSettings

    @State private var name: String
    @State private var amountString: String
    @State private var isLent: Bool
    @State private var selectedType: DebtType
    @State private var dueDate: Date
    @State private var reminder: DebtReminder
    @State private var billKind: BillKind
    @State private var repeatRule: ReminderRepeat
    @State private var repeatInterval: Int
    @State private var isVariableAmount: Bool
    @State private var note: String
    @State private var monthlyPaymentString: String
    @State private var interestRateString: String
    @State private var paymentsLeftString: String
    /// Карта, на которую записывается оплата; пусто — только отметка в долгах
    @State private var cardID: UUID?
    /// Условия (напоминание, период, сумма) уже меняли руками: смена вида больше их не перезаписывает
    @State private var termsEdited = false

    /// Форма открывается сразу с типом открытой вкладки: «Мне должны» — долг человека, «Я должен» — кредит,
    /// «Платежи» — платёж с повтором каждый месяц. Новая запись берёт условия из настроек своего вида.
    init(financeService: FinanceService, tab: DebtTab = .iOwe, editing: Debt? = nil, onSave: @escaping (DebtTab) -> Void = { _ in }) {
        self.financeService = financeService
        self.editing = editing
        self.onSave = onSave
        let settings = DebtTypeSettings.load()
        typeSettings = settings

        if let editing {
            _name = State(initialValue: editing.name)
            _amountString = State(initialValue: GoalQuickAmounts.plain(editing.amount))
            _isLent = State(initialValue: editing.isLent)
            _selectedType = State(initialValue: editing.type)
            _dueDate = State(initialValue: editing.dueDate)
            _reminder = State(initialValue: editing.effectiveReminder(using: settings))
            _billKind = State(initialValue: editing.billKind ?? .utilities)
            _repeatRule = State(initialValue: editing.repeatRule ?? .never)
            _repeatInterval = State(initialValue: max(1, editing.repeatInterval ?? 1))
            _isVariableAmount = State(initialValue: editing.isVariableAmount ?? false)
            _note = State(initialValue: editing.note ?? "")
            _monthlyPaymentString = State(initialValue: editing.monthlyPayment.map { GoalQuickAmounts.plain($0) } ?? "")
            _interestRateString = State(initialValue: editing.interestRate.map { GoalQuickAmounts.plain($0) } ?? "")
            _paymentsLeftString = State(initialValue: editing.paymentsLeft.map { String($0) } ?? "")
            _cardID = State(initialValue: Self.knownCard(editing.cardId, in: financeService))
        } else {
            let type: DebtType
            let profile: DebtProfile
            switch tab {
            case .owedToMe:
                type = .person
                profile = .owedToMe
            case .iOwe:
                type = .credit
                profile = .credit
            case .bills:
                type = .bill
                profile = .bill(.utilities)
            }
            let setting = settings[profile]
            _name = State(initialValue: "")
            _amountString = State(initialValue: "")
            _isLent = State(initialValue: tab == .owedToMe)
            _selectedType = State(initialValue: type)
            _dueDate = State(initialValue: Date())
            _reminder = State(initialValue: setting.defaultReminder)
            _billKind = State(initialValue: .utilities)
            _repeatRule = State(initialValue: type == .bill ? setting.repeatRule : .monthly)
            _repeatInterval = State(initialValue: type == .bill ? setting.repeatInterval : 1)
            _isVariableAmount = State(initialValue: type == .bill && setting.isVariableAmount)
            _note = State(initialValue: "")
            _monthlyPaymentString = State(initialValue: "")
            _interestRateString = State(initialValue: "")
            _paymentsLeftString = State(initialValue: "")
            _cardID = State(initialValue: Self.knownCard(setting.cardId, in: financeService))
        }
    }

    /// Карта, которая ещё есть в приложении: удалённая карта из записи или из настроек вида не подставляется
    private static func knownCard(_ id: UUID?, in financeService: FinanceService) -> UUID? {
        guard let id, financeService.cards.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    private var parsedAmount: Double {
        Double(amountString.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var parsedMonthlyPayment: Double? {
        guard let value = GoalQuickAmounts.parse(monthlyPaymentString), value > 0 else { return nil }
        return value
    }

    private var parsedInterestRate: Double? {
        guard let value = GoalQuickAmounts.parse(interestRateString), value > 0 else { return nil }
        return min(value, 1_000)
    }

    private var parsedPaymentsLeft: Int? {
        guard let value = Int(paymentsLeftString.trimmingCharacters(in: .whitespaces)), value >= 0 else { return nil }
        return value
    }

    private var isBill: Bool { selectedType == .bill }
    private var isCredit: Bool { selectedType == .credit }
    /// Платёж повторяется: у него есть период и можно отметить, что сумма меняется
    private var isRecurringBill: Bool { isBill && repeatRule != .never }
    /// Кредит с графиком: срок переходит на следующий месяц, остаток уменьшается
    private var hasPaymentPlan: Bool { isCredit && parsedMonthlyPayment != nil }

    /// Вид, по настройкам которого заполняется новая запись
    private var currentProfile: DebtProfile {
        switch selectedType {
        case .credit: return .credit
        case .person: return isLent ? .owedToMe : .iOwe
        case .bill: return repeatRule == .never ? .oneTimeBill : .bill(billKind)
        }
    }

    private var navigationTitleText: String {
        if editing != nil {
            return isBill ? String(localized: "Изменить платёж") : String(localized: "Изменить долг")
        }
        return isBill ? String(localized: "Новый платёж") : String(localized: "Новый долг")
    }

    /// Смена вида подставляет в новую запись условия этого вида, пока условия не меняли руками.
    /// `includingRepeat` — подставить ещё и период платежа: так бывает при выборе вида платежа, а не при смене «один раз»/«повтор».
    private func applyDefaults(includingRepeat: Bool) {
        guard editing == nil, !termsEdited else { return }
        if includingRepeat, isBill {
            let setting = typeSettings[.bill(billKind)]
            repeatRule = setting.repeatRule
            repeatInterval = setting.repeatInterval
            isVariableAmount = setting.isVariableAmount
        }
        reminder = typeSettings[currentProfile].defaultReminder
        cardID = Self.knownCard(typeSettings[currentProfile].cardId, in: financeService)
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
                            applyDefaults(includingRepeat: true)
                        }
                    } header: {
                        Text("Категория")
                    }
                }

                if isBill {
                    Section {
                        Picker("Вид платежа", selection: $billKind) {
                            ForEach(BillKind.allCases) { kind in
                                Label(kind.title, systemImage: kind.icon).tag(kind)
                            }
                        }
                        .onChange(of: billKind) { _, _ in
                            applyDefaults(includingRepeat: true)
                        }

                        TextField("Название (необязательно)", text: $name)
                            .textInputAutocapitalization(.sentences)

                        amountRow

                        if isRecurringBill {
                            Toggle("Сумма меняется", isOn: edited($isVariableAmount))
                        }
                    } header: {
                        Text("Информация о платеже")
                    } footer: {
                        if isRecurringBill && isVariableAmount {
                            Text("При оплате спросим, сколько вышло, и запомним сумму для следующего раза.")
                        }
                    }
                } else {
                    Section {
                        TextField(isCredit ? String(localized: "Название банка / кредитора") : String(localized: "Имя человека"), text: $name)
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
                        .onChange(of: isLent) { _, _ in
                            applyDefaults(includingRepeat: false)
                        }
                    } header: {
                        Text("Направление")
                    }
                }

                if isCredit {
                    Section {
                        numberRow(String(localized: "Платёж в месяц (\(CurrencyManager.shared.baseCurrency.symbol))"), text: $monthlyPaymentString, keyboard: .decimalPad)
                        numberRow(String(localized: "Ставка, % годовых"), text: $interestRateString, keyboard: .decimalPad)
                        numberRow(String(localized: "Осталось платежей"), text: $paymentsLeftString, keyboard: .numberPad)
                    } header: {
                        Text("График платежей")
                    } footer: {
                        Text("Необязательно. Если указать платёж в месяц, срок будет сам переходить на следующий месяц, а остаток долга уменьшаться с каждым платежом.")
                    }
                }

                Section {
                    DatePicker(dueDateTitle, selection: $dueDate, displayedComponents: .date)
                    if isBill {
                        Picker("Повтор", selection: $repeatRule) {
                            ForEach(ReminderRepeat.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .onChange(of: repeatRule) { _, _ in
                            applyDefaults(includingRepeat: false)
                        }
                        if isRecurringBill {
                            Stepper(value: edited($repeatInterval), in: 1...36) {
                                Text(repeatRule.title(every: repeatInterval))
                            }
                        }
                    }
                    Picker("Напомнить", selection: edited($reminder)) {
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

                if !financeService.cards.isEmpty {
                    PaymentCardSection(cards: financeService.cards, isIncome: selectedType == .person && isLent, cardID: edited($cardID))
                }

                Section {
                    TextField("Заметка (необязательно)", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("Заметка")
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

    /// Привязка, которая запоминает, что условие поменяли руками
    private func edited<Value>(_ binding: Binding<Value>) -> Binding<Value> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                binding.wrappedValue = newValue
                termsEdited = true
            }
        )
    }

    private var dueDateTitle: String {
        if isBill {
            return String(localized: "Срок оплаты")
        }
        return hasPaymentPlan ? String(localized: "Ближайший платёж") : String(localized: "Срок возврата")
    }

    private var amountRow: some View {
        HStack {
            if isCredit {
                Text("Остаток долга (\(CurrencyManager.shared.baseCurrency.symbol))")
            } else {
                Text("Сумма (\(CurrencyManager.shared.baseCurrency.symbol))")
            }
            Spacer()
            TextField("0", text: $amountString)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private func numberRow(_ title: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(verbatim: title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
        }
    }

    /// Что именно придёт: для кредита и платежа — об оплате, для человека — вернуть или получить деньги
    private var reminderFooter: String {
        if isBill {
            if repeatRule == .never {
                return String(localized: "Напомним об оплате заранее, в день срока и после него, пока платёж не оплачен.")
            }
            return String(localized: "Напомним об оплате заранее, в день срока и после него. Когда вы отметите платёж оплаченным, срок сам перейдёт на следующий период.")
        }
        if isCredit {
            return String(localized: "Напомним о платеже заранее, в день срока и после него, пока кредит не отмечен погашенным.")
        }
        if isLent {
            return String(localized: "Напомним, когда вам должны вернуть деньги, и ещё раз, если срок пройдёт.")
        }
        return String(localized: "Напомним вернуть деньги заранее, в день срока и после него, пока долг не отмечен погашенным.")
    }

    private var isSaveDisabled: Bool {
        // У платежа имя необязательно: без него берётся вид платежа («Интернет»)
        let needsName = !isBill
        let nameMissing = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (needsName && nameMissing) || parsedAmount <= 0
    }

    private func saveDebt() {
        guard parsedAmount > 0 else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        // Срок платежа и кредита с графиком считается по дням, от первого срока считаются следующие
        let followsSchedule = isBill || hasPaymentPlan
        let day = Calendar.current.startOfDay(for: dueDate)

        // Первый срок остаётся прежним, пока дату не поменяли: от него считаются следующие сроки
        var firstDue: Date? = nil
        if followsSchedule {
            let unchanged = editing.map { Calendar.current.isDate($0.dueDate, inSameDayAs: day) } ?? false
            firstDue = (unchanged ? editing?.firstDueDate : nil) ?? day
        }

        // У правки остаются поля, которых в форме нет: когда и сколько оплачивали, сколько уже внесено
        var debt = editing ?? Debt(name: cleanName, amount: parsedAmount, dueDate: dueDate, isLent: false)
        debt.name = isBill && cleanName.isEmpty ? billKind.title : cleanName
        debt.amount = parsedAmount
        debt.dueDate = followsSchedule ? day : dueDate
        debt.isLent = selectedType == .person ? isLent : false
        debt.type = selectedType
        debt.reminder = reminder
        debt.billKind = isBill ? billKind : nil
        debt.repeatRule = isBill ? repeatRule : nil
        debt.firstDueDate = firstDue
        debt.note = cleanNote.isEmpty ? nil : cleanNote
        debt.repeatInterval = isRecurringBill && repeatInterval > 1 ? repeatInterval : nil
        debt.isVariableAmount = isRecurringBill && isVariableAmount ? true : nil
        debt.monthlyPayment = isCredit ? parsedMonthlyPayment : nil
        debt.interestRate = isCredit ? parsedInterestRate : nil
        debt.paymentsLeft = isCredit && hasPaymentPlan ? parsedPaymentsLeft : nil
        debt.cardId = Self.knownCard(cardID, in: financeService)

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
