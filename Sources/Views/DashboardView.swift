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

/// Раздел «Обзор»: лаймовая карточка баланса, траты за неделю, главные категории и последние операции.
@MainActor
struct DashboardView: View {
    let financeService: FinanceService
    /// Переход в раздел «Отчёт» по нажатию на графики
    var onOpenReport: () -> Void = {}

    @State private var addSheetType: TransactionType? = nil
    @State private var isShowingSettingsSheet = false
    @State private var isShowingAllTransactions = false

    // Распознавание СМС из буфера обмена
    @State private var detectedBatchTransactions: [ParsedSMSTransaction] = []
    @State private var lastCheckedClipboardString = ""
    @State private var clipboardMessage: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerView
                balanceCard
                smsSection
                WeekSpendingCard(financeService: financeService, onTap: onOpenReport)
                    .padding(.top, 16)
                TopCategoriesRow(financeService: financeService, onTap: onOpenReport)
                    .padding(.top, 16)
                recentTransactionsSection
            }
            .padding(.horizontal, 20)
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
        .sheet(isPresented: $isShowingAllTransactions) {
            TransactionsView(financeService: financeService)
        }
    }

    // MARK: - Шапка
    private var headerView: some View {
        HStack(spacing: 8) {
            Text("Обзор")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Spacer()
            MonoCircleButton(systemName: "doc.on.clipboard", label: "Распознать СМС из буфера") {
                HapticManager.shared.impact(.light)
                scanClipboard()
            }
            MonoCircleButton(systemName: "plus", label: "Новая операция", filled: true) {
                HapticManager.shared.impact(.light)
                addSheetType = .expense
            }
            MonoCircleButton(systemName: "gearshape", label: "Настройки") {
                HapticManager.shared.impact(.light)
                isShowingSettingsSheet = true
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Карточка баланса
    private var monthIncome: Double {
        financeService.transactions
            .filter { $0.type == .income && TimePeriodFilter.month.contains($0.date) }
            .reduce(0.0) { $0 + $1.amount }
    }

    private var monthExpense: Double {
        financeService.transactions
            .filter { $0.type == .expense && TimePeriodFilter.month.contains($0.date) }
            .reduce(0.0) { $0 + $1.amount }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Баланс")
                Spacer()
                Text(Date.now, format: .dateTime.month(.wide))
            }
            .font(.system(size: 14, weight: .medium))

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(CurrencyManager.shared.formatNumber(financeService.totalBalance))
                    .font(Theme.number(48, weight: .bold))
                    .tracking(-1.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(CurrencyManager.shared.currentCurrency.symbol)
                    .font(Theme.number(24, weight: .bold))
            }
            .padding(.top, 6)

            BalanceSparkline(financeService: financeService)
                .frame(height: 40)
                .padding(.top, 12)

            HStack(spacing: 8) {
                balancePill("+\(CurrencyManager.shared.format(monthIncome))")
                balancePill("−\(CurrencyManager.shared.format(monthExpense))")
                Spacer(minLength: 0)
                Text("за 30 дней")
                    .font(.system(size: 12))
                    .opacity(0.7)
            }
            .padding(.top, 12)
        }
        .foregroundColor(Theme.onAccent)
        .padding(22)
        .background(Theme.accent)
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .padding(.top, 20)
    }

    private func balancePill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.onAccent.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Распознанные СМС
    @ViewBuilder
    private var smsSection: some View {
        if !detectedBatchTransactions.isEmpty {
            smsBanner
                .padding(.top, 16)
        } else if let clipboardMessage {
            Text(clipboardMessage)
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .padding(.top, 14)
        }
    }

    private var smsBanner: some View {
        let count = detectedBatchTransactions.count
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(count > 1 ? "Найдено СМС в буфере: \(count)" : "Найдена СМС в буфере")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                Text(smsSummary)
                    .font(.system(size: 15, weight: .semibold))
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
                    .foregroundColor(Theme.onAccent)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Theme.accent)
                    .clipShape(Capsule())
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .monoSurface(cornerRadius: 22)
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
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.accent)
                        .frame(minHeight: 44, alignment: .leading)
                }
            }

            if financeService.transactions.isEmpty {
                Text("Операций пока нет. Добавьте первую кнопкой «+», из СМС или через ИИ.")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(financeService.transactions.prefix(5)) { transaction in
                    transactionRow(transaction)
                }
            }
        }
        .padding(.top, 28)
    }

    private func transactionRow(_ transaction: Transaction) -> some View {
        let isIncome = transaction.type == .income
        let sign = isIncome ? "+" : "−"
        let time = transaction.date.formatted(.dateTime.day().month(.abbreviated))
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                MonoInitialBadge(title: transaction.title)

                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("\(transaction.category.name) · \(time)")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text("\(sign)\(CurrencyManager.shared.format(transaction.amount))")
                    .font(Theme.number(16))
                    .foregroundColor(isIncome ? Theme.accent : .white)
            }
            .frame(minHeight: 64)
            MonoDivider()
        }
    }

    // MARK: - Буфер обмена

    /// Явная проверка буфера по кнопке в шапке
    private func scanClipboard() {
        lastCheckedClipboardString = ""
        checkClipboardForSMS()
        if detectedBatchTransactions.isEmpty {
            showClipboardMessage("В буфере нет банковских СМС")
        }
    }

    private func showClipboardMessage(_ message: String) {
        clipboardMessage = message
        Task {
            try? await Task.sleep(for: .seconds(4))
            clipboardMessage = nil
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
        showClipboardMessage(String(summary.text.prefix(1)).uppercased() + String(summary.text.dropFirst()))
    }
}
