import SwiftUI
import Charts

/// Экран ИИ-Советника с персональными рекомендациями
@MainActor
struct AIFinancialAdvisorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService

    private var insights: [AIFinancialInsight] {
        AIService.shared.generateInsights(financeService: financeService)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 20))
                            .foregroundColor(Theme.accent)
                            .frame(width: 48, height: 48)
                            .overlay(Circle().stroke(Theme.line, lineWidth: 1))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("SamFinance AI Advisor")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Умный финансовый помощник")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textTertiary)
                        }
                    }

                    MonoLabel(text: "Персональный анализ бюджета")
                        .padding(.top, 4)

                    VStack(spacing: 12) {
                        ForEach(insights) { insight in
                            insightRow(insight)
                        }
                    }
                }
                .padding(24)
            }
            .monoScreen()
            .navigationTitle("ИИ-Советник")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func insightRow(_ insight: AIFinancialInsight) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: insight.iconName)
                .font(.system(size: 18))
                .foregroundColor(color(for: insight.type))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text(insight.message)
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .monoSurface()
    }

    /// Рост и успех подсвечены акцентом, предупреждения белым, остальное приглушено
    private func color(for type: AIFinancialInsight.InsightType) -> Color {
        switch type {
        case .positive: return Theme.accent
        case .warning: return .white
        case .info: return Theme.textSecondary
        }
    }
}

/// Подробный график расходов с выбором дня и историей операций за период
@MainActor
struct FullExpenseChartView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    @State private var selectedPeriod: TimePeriodFilter = .month
    @State private var rawSelectedDate: Date? = nil

    struct SpendingPoint: Identifiable {
        let date: Date
        let amount: Double

        var id: Date { date }
    }

    private var chartPoints: [SpendingPoint] {
        let calendar = Calendar.current
        let daysCount = selectedPeriod == .today ? 1 : (selectedPeriod == .week ? 7 : 30)
        var amounts: [Date: Double] = [:]

        for offset in 0..<daysCount {
            if let day = calendar.date(byAdding: .day, value: -offset, to: Date()) {
                amounts[calendar.startOfDay(for: day)] = 0.0
            }
        }

        for transaction in financeService.transactions where transaction.type == .expense {
            let day = calendar.startOfDay(for: transaction.date)
            if amounts[day] != nil {
                amounts[day, default: 0.0] += transaction.amount
            }
        }

        return amounts
            .map { SpendingPoint(date: $0.key, amount: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private var totalSpendingForPeriod: Double {
        chartPoints.reduce(0.0) { $0 + $1.amount }
    }

    private var selectedPoint: SpendingPoint? {
        guard let rawSelectedDate else { return nil }
        let calendar = Calendar.current
        return chartPoints.first { calendar.isDate($0.date, inSameDayAs: rawSelectedDate) }
    }

    private var transactionsForPeriod: [Transaction] {
        financeService.transactions.filter { $0.type == .expense && selectedPeriod.contains($0.date) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    MonoSegmentedControl(
                        options: TimePeriodFilter.allCases,
                        title: { $0.rawValue },
                        selection: $selectedPeriod
                    )

                    totalHeader

                    if let selectedPoint {
                        selectedPointRow(selectedPoint)
                    }

                    chartBlock
                    historyBlock
                }
                .padding(24)
            }
            .monoScreen()
            .navigationTitle("Детальный график расходов")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var totalHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel(text: "Всего потрачено (\(selectedPeriod.rawValue.lowercased()))")
            Text(CurrencyManager.shared.format(totalSpendingForPeriod))
                .font(.system(size: 34, weight: .light))
                .tracking(-1)
                .monospacedDigit()
                .foregroundColor(.white)
        }
    }

    private func selectedPointRow(_ point: SpendingPoint) -> some View {
        HStack {
            Text(formatDate(point.date))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            Text(CurrencyManager.shared.format(point.amount))
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(Theme.accent)
        }
        .padding(16)
        .monoSurface(cornerRadius: 16)
    }

    // MARK: - График
    private var chartBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoSectionHeader(title: "Динамика расходов")

            chart
                .frame(height: 240)
        }
    }

    private var chart: some View {
        let data = chartPoints
        let selected = selectedPoint
        return Chart {
            ForEach(data) { item in
                LineMark(
                    x: .value("Дата", item.date, unit: .day),
                    y: .value("Траты", item.amount)
                )
                .foregroundStyle(Color.white)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .interpolationMethod(.catmullRom)
            }

            if let selected {
                RuleMark(x: .value("Выбрано", selected.date, unit: .day))
                    .foregroundStyle(Theme.line)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                PointMark(
                    x: .value("Выбрано", selected.date, unit: .day),
                    y: .value("Сумма", selected.amount)
                )
                .symbolSize(80)
                .foregroundStyle(Color.white)
            }
        }
        .chartXSelection(value: $rawSelectedDate)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: selectedPeriod == .month ? 6 : 2)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.twoDigits))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let doubleVal = value.as(Double.self) {
                        Text(formatCompactNumber(doubleVal))
                            .font(.caption2)
                            .foregroundColor(Theme.textTertiary)
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Theme.hairline)
            }
        }
    }

    // MARK: - История
    private var historyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoSectionHeader(title: "История расходов за период")

            let periodExpenses = transactionsForPeriod
            if periodExpenses.isEmpty {
                Text("Нет операций за этот период")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textTertiary)
                    .padding(.vertical, 12)
            } else {
                ForEach(periodExpenses) { transaction in
                    historyRow(transaction)
                }
            }
        }
    }

    private func historyRow(_ transaction: Transaction) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                MonoInitialBadge(title: transaction.title)

                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(formatDate(transaction.date))
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textTertiary)
                }

                Spacer(minLength: 8)

                Text("−\(CurrencyManager.shared.format(transaction.amount))")
                    .font(.system(size: 16))
                    .monospacedDigit()
                    .foregroundColor(.white)
            }
            .frame(minHeight: 64)
            MonoDivider()
        }
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year())
    }

    private func formatCompactNumber(_ number: Double) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", number / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.0fK", number / 1_000)
        } else {
            return "\(Int(number))"
        }
    }
}
