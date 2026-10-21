import SwiftUI

/// Перечисление временных интервалов для точного фильтра дат и трат
public enum TimePeriodFilter: String, CaseIterable, Identifiable {
    case today = "Сегодня"
    case week = "Неделя"
    case month = "Месяц"
    case allTime = "Всё время"

    public var id: String { rawValue }

    /// Входит ли дата в период: сегодня, последние 7 или 30 дней, всё время
    func contains(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .today:
            return calendar.isDateInToday(date)
        case .week:
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return date >= start
        case .month:
            let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return date >= start
        case .allTime:
            return true
        }
    }
}

/// Тип операции нужен как идентификатор для показа листа «Новая операция»
extension TransactionType: Identifiable {
    public var id: String { rawValue }
}

/// Главный экран: баланс, быстрые действия, траты за период, категории, совет и последние операции.
@MainActor
struct DashboardView: View {
    let financeService: FinanceService
    @State private var addSheetType: TransactionType? = nil
    @State private var isShowingSettingsSheet = false
    @State private var isShowingAIAdvisorSheet = false
    @State private var isShowingFullChartSheet = false
    @State private var isShowingAllTransactions = false
    @State private var selectedPeriod: TimePeriodFilter = .month

    // Распознавание СМС из буфера обмена
    @State private var detectedBatchTransactions: [ParsedSMSTransaction] = []
    @State private var lastCheckedClipboardString = ""
    @State private var clipboardMessage: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerView
                balanceSection
                quickActions
                smsSection
                periodPicker
                spendingSection
                DashboardCategoriesSection(financeService: financeService, selectedPeriod: selectedPeriod)
                    .padding(.top, 36)
                advisorCard
                recentTransactionsSection
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .monoScreen()
        .onAppear {
            checkClipboardForSMS()
        }
        .sheet(item: $addSheetType) { type in
            AddTransactionView(financeService: financeService, initialType: type)
        }
        .sheet(isPresented: $isShowingSettingsSheet) {
            SettingsView(financeService: financeService)
        }
        .sheet(isPresented: $isShowingAIAdvisorSheet) {
            AIFinancialAdvisorSheet(financeService: financeService)
        }
        .sheet(isPresented: $isShowingFullChartSheet) {
            FullExpenseChartView(financeService: financeService)
        }
        .sheet(isPresented: $isShowingAllTransactions) {
            TransactionsView(financeService: financeService)
        }
    }

    // MARK: - Шапка
    private var headerView: some View {
        HStack {
            Text(Date.now, format: .dateTime.day().month(.wide))
                .font(.system(size: 15))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            MonoCircleButton(systemName: "slider.horizontal.3", label: "Настройки") {
                HapticManager.shared.impact(.light)
                isShowingSettingsSheet = true
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Баланс
    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: "total_balance".localized)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(CurrencyManager.shared.currentCurrency.symbol)
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(Theme.textTertiary)
                Text(CurrencyManager.shared.formatNumber(financeService.totalBalance))
                    .font(.system(size: 56, weight: .light))
                    .tracking(-2)
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }

            if let trend = spendingTrendText {
                trend
                    .font(.system(size: 14))
            }
        }
        .padding(.top, 28)
    }

    /// Динамика трат: последние 30 дней к предыдущим 30
    private var spendingTrendText: Text? {
        let calendar = Calendar.current
        let now = Date()
        guard let start = calendar.date(byAdding: .day, value: -30, to: now),
              let previousStart = calendar.date(byAdding: .day, value: -60, to: now) else {
            return nil
        }
        let expenses = financeService.transactions.filter { $0.type == .expense }
        let current = expenses.filter { $0.date >= start }.reduce(0.0) { $0 + $1.amount }
        let previous = expenses.filter { $0.date >= previousStart && $0.date < start }.reduce(0.0) { $0 + $1.amount }
        guard previous > 0 else { return nil }

        let percent = Int(((current - previous) / previous * 100).rounded())
        if percent < 0 {
            return Text("−\(abs(percent))% трат к предыдущим 30 дням").foregroundColor(Theme.accent)
        } else if percent > 0 {
            return Text("+\(percent)% трат к предыдущим 30 дням").foregroundColor(Theme.textSecondary)
        }
        return Text("Траты на уровне предыдущих 30 дней").foregroundColor(Theme.textSecondary)
    }

    // MARK: - Быстрые действия
    private var quickActions: some View {
        HStack(spacing: 12) {
            quickAction(title: "Расход", icon: "arrow.up.right") {
                addSheetType = .expense
            }
            quickAction(title: "Доход", icon: "arrow.down.left") {
                addSheetType = .income
            }
            quickAction(title: "Из СМС", icon: "message") {
                scanClipboard()
            }
        }
        .padding(.top, 28)
    }

    private func quickAction(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.impact(.light)
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.system(size: 13))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 76)
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.line, lineWidth: 1))
        }
    }

    // MARK: - Распознанные СМС
    @ViewBuilder
    private var smsSection: some View {
        if !detectedBatchTransactions.isEmpty {
            smsBanner
                .padding(.top, 20)
        } else if let clipboardMessage {
            Text(clipboardMessage)
                .font(.system(size: 13))
                .foregroundColor(Theme.textTertiary)
                .padding(.top, 16)
        }
    }

    private var smsBanner: some View {
        let count = detectedBatchTransactions.count
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(count > 1 ? "Найдено СМС в буфере: \(count)" : "Найдена СМС в буфере")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)
                Text(smsSummary)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                HapticManager.shared.impact(.light)
                withAnimation {
                    detectedBatchTransactions = []
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Скрыть")

            Button {
                addDetectedTransaction()
            } label: {
                Text(count > 1 ? "Записать все" : "Записать")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
    }

    private var smsSummary: String {
        if detectedBatchTransactions.count > 1 {
            let total = detectedBatchTransactions.reduce(0.0) { $0 + $1.amount }
            return "Всего на сумму: \(CurrencyManager.shared.format(total))"
        }
        guard let parsed = detectedBatchTransactions.first else { return "" }
        let sign = parsed.type == .income ? "+" : "−"
        return "\(parsed.title) · \(sign)\(CurrencyManager.shared.format(parsed.amount))"
    }

    // MARK: - Период и траты
    private var periodPicker: some View {
        MonoSegmentedControl(
            options: TimePeriodFilter.allCases,
            title: { $0.rawValue },
            selection: $selectedPeriod
        )
        .padding(.top, 28)
    }

    private var filteredSpendingAmount: Double {
        financeService.transactions
            .filter { $0.type == .expense && selectedPeriod.contains($0.date) }
            .reduce(0.0) { $0 + $1.amount }
    }

    private var spendingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel(text: "Траты (\(selectedPeriod.rawValue.lowercased()))")
            Text(CurrencyManager.shared.format(filteredSpendingAmount))
                .font(.system(size: 32))
                .tracking(-1)
                .monospacedDigit()
                .foregroundColor(.white)

            DashboardSpendingChart(financeService: financeService, selectedPeriod: selectedPeriod) {
                HapticManager.shared.impact(.medium)
                isShowingFullChartSheet = true
            }
            .padding(.top, 12)
        }
        .padding(.top, 32)
    }

    // MARK: - Совет
    private var advisorCard: some View {
        Button {
            HapticManager.shared.impact(.light)
            isShowingAIAdvisorSheet = true
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18))
                    .foregroundColor(Theme.accent)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(Theme.line, lineWidth: 1))

                VStack(alignment: .leading, spacing: 6) {
                    MonoLabel(text: "Совет")
                    Text(adviceText)
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .foregroundColor(Color(hex: "#E5E5EA"))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .monoSurface()
        }
        .buttonStyle(.plain)
        .padding(.top, 32)
    }

    private var adviceText: String {
        AIService.shared.generateInsights(financeService: financeService).first?.message ?? ""
    }

    // MARK: - Последние операции
    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoSectionHeader(
                title: "Последние операции",
                trailing: "Все",
                onTrailingTap: { isShowingAllTransactions = true }
            )

            if financeService.reviewCount > 0 {
                Button {
                    HapticManager.shared.impact(.light)
                    isShowingAllTransactions = true
                } label: {
                    Text("Проверить категории: \(financeService.reviewCount)")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.accent)
                        .frame(minHeight: 44, alignment: .leading)
                }
            }

            if financeService.transactions.isEmpty {
                Text("Операций пока нет. Добавьте первую кнопкой «+» или из СМС.")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textTertiary)
                    .padding(.vertical, 12)
            } else {
                ForEach(financeService.transactions.prefix(5)) { transaction in
                    transactionRow(transaction)
                }
            }
        }
        .padding(.top, 32)
    }

    private func transactionRow(_ transaction: Transaction) -> some View {
        let isIncome = transaction.type == .income
        let sign = isIncome ? "+" : "−"
        let day = transaction.date.formatted(.dateTime.day().month(.abbreviated))
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                MonoInitialBadge(title: transaction.title)

                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("\(transaction.category.name) · \(day)")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text("\(sign)\(CurrencyManager.shared.format(transaction.amount))")
                    .font(.system(size: 16))
                    .monospacedDigit()
                    .foregroundColor(isIncome ? Theme.accent : .white)
            }
            .frame(minHeight: 64)
            MonoDivider()
        }
    }

    // MARK: - Буфер обмена

    /// Явная проверка буфера по кнопке «Из СМС»
    private func scanClipboard() {
        lastCheckedClipboardString = ""
        checkClipboardForSMS()
        if detectedBatchTransactions.isEmpty {
            clipboardMessage = "В буфере нет банковских СМС"
            Task {
                try? await Task.sleep(for: .seconds(3))
                clipboardMessage = nil
            }
        }
    }

    private func checkClipboardForSMS() {
        guard let clipboardString = UIPasteboard.general.string,
              !clipboardString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              clipboardString != lastCheckedClipboardString else { return }

        lastCheckedClipboardString = clipboardString

        let batch = SMSParser.parseBatch(text: clipboardString)
        if !batch.isEmpty {
            withAnimation {
                detectedBatchTransactions = batch
            }
        }
    }

    private func addDetectedTransaction() {
        // Карта, баланс, дубли и категория обрабатываются автоматически
        let summary = AutomationService.shared.ingestAll(detectedBatchTransactions)

        HapticManager.shared.trigger(.success)
        UIPasteboard.general.string = ""

        withAnimation {
            detectedBatchTransactions = []
        }

        clipboardMessage = String(summary.text.prefix(1)).uppercased() + String(summary.text.dropFirst())
        Task {
            try? await Task.sleep(for: .seconds(4))
            clipboardMessage = nil
        }
    }
}
