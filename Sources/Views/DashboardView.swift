import SwiftUI
import Charts

/// Главный экран дашборда с карточкой баланса, круговой диаграммой расходов (Swift Charts) и историей операций.
struct DashboardView: View {
    let financeService: FinanceService
    @State private var isShowingAddSheet = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Карточка баланса
                    balanceCard
                        .padding(.horizontal)
                        .padding(.top, 8)
                    
                    // Диаграмма расходов (Swift Charts)
                    expenseChartSection
                        .padding(.horizontal)
                    
                    // Список последних транзакций
                    transactionsSection
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Мои Финансы")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticManager.shared.impact(.light)
                        isShowingAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .sheet(isPresented: $isShowingAddSheet) {
                AddTransactionView(financeService: financeService)
            }
        }
    }
    
    // MARK: - Карточка баланса
    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Текущий баланс")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
            
            Text(formatCurrency(financeService.totalBalance))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            HStack(spacing: 20) {
                // Доходы
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.left.circle.fill")
                            .foregroundColor(.green)
                        Text("Доходы")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    Text(formatCurrency(financeService.totalIncome))
                        .font(.headline)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Расходы
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .foregroundColor(.red)
                        Text("Расходы")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    Text(formatCurrency(financeService.totalExpenses))
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            .padding(.top, 8)
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#5E5CE6"), Color(hex: "#007AFF")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color(hex: "#5E5CE6").opacity(0.25), radius: 15, x: 0, y: 8)
        }
    }
    
    // MARK: - Секция с диаграммой расходов
    private var expenseChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Структура расходов")
                .font(.headline)
                .foregroundColor(.secondary)
            
            let expenseData = financeService.expenseByCategory
            
            if expenseData.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Расходы отсутствуют")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(20)
            } else {
                HStack(spacing: 16) {
                    Chart {
                        ForEach(Array(expenseData.keys)) { category in
                            if let amount = expenseData[category], amount > 0 {
                                SectorMark(
                                    angle: .value("Сумма", amount),
                                    innerRadius: .ratio(0.68),
                                    angularInset: 2.0
                                )
                                .cornerRadius(5)
                                .foregroundStyle(Color(hex: category.colorHex))
                            }
                        }
                    }
                    .frame(width: 120, height: 120)
                    
                    Spacer()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(expenseData.keys.prefix(4))) { category in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: category.colorHex))
                                    .frame(width: 8, height: 8)
                                Text(category.name)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Spacer()
                                if let amount = expenseData[category] {
                                    Text(formatCurrency(amount))
                                        .font(.caption.bold())
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(20)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(20)
            }
        }
    }
    
    // MARK: - Секция истории операций
    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("История операций")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            
            if financeService.transactions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("У вас нет транзакций")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(20)
                .padding(.horizontal)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(financeService.transactions) { transaction in
                        TransactionRow(transaction: transaction)
                            .contextMenu {
                                Button(role: .destructive) {
                                    HapticManager.shared.trigger(.warning)
                                    withAnimation(.spring()) {
                                        financeService.deleteTransaction(transaction)
                                    }
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₽"
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value) ₽"
    }
}

/// Строка транзакции в списке
struct TransactionRow: View {
    let transaction: Transaction
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(hex: transaction.category.colorHex).opacity(0.12))
                    .frame(width: 46, height: 46)
                
                Image(systemName: transaction.category.icon)
                    .font(.body.bold())
                    .foregroundColor(Color(hex: transaction.category.colorHex))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(transaction.category.name)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(transaction.type == .income ? "+\(formatAmount(transaction.amount))" : "-\(formatAmount(transaction.amount))")
                    .font(.headline.bold())
                    .foregroundColor(transaction.type == .income ? .green : .primary)
                
                Text(formatDate(transaction.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
    
    private func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return (formatter.string(from: NSNumber(value: value)) ?? "\(value)") + " ₽"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM"
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter.string(from: date)
    }
}
