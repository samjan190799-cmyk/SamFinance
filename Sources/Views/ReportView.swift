import SwiftUI
import Charts

/// Раздел «Отчёт»: траты за период, график с выбором дня, доли категорий и история операций.
@MainActor
struct ReportView: View {
    let financeService: FinanceService
    @State private var selectedPeriod: TimePeriodFilter = .month
    @State private var rawSelectedDate: Date? = nil
    /// Столбики вырастают из нуля при показе экрана
    @State private var isChartGrown = false

    private var chartPoints: [DailyAmount] {
        let days = selectedPeriod == .today ? 1 : (selectedPeriod == .week ? 7 : 30)
        return DailySpending.points(financeService: financeService, days: days)
    }

    private var periodExpenses: [Transaction] {
        financeService.transactions.filter { $0.type == .expense && selectedPeriod.contains($0.date) }
    }

    private var periodIncome: Double {
        financeService.transactions
            .filter { $0.type == .income && selectedPeriod.contains($0.date) }
            .reduce(0.0) { $0 + $1.amount }
    }

    private var selectedPoint: DailyAmount? {
        guard let rawSelectedDate else { return nil }
        let calendar = Calendar.current
        return chartPoints.first { calendar.isDate($0.date, inSameDayAs: rawSelectedDate) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Отчёт")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(minHeight: 44)
                    .padding(.top, 8)
                    .appearAnimation(order: 0)

                MonoSegmentedControl(
                    options: TimePeriodFilter.allCases,
                    title: { $0.rawValue },
                    selection: $selectedPeriod
                )
                .padding(.top, 16)
                .appearAnimation(order: 1)

                totals
                    .padding(.top, 16)
                    .appearAnimation(order: 2)

                chartCard
                    .padding(.top, 16)
                    .appearAnimation(order: 3)

                DashboardCategoriesSection(financeService: financeService, selectedPeriod: selectedPeriod)
                    .padding(.top, 28)
                    .appearAnimation(order: 4)

                history
                    .padding(.top, 28)
                    .appearAnimation(order: 5)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .monoScreen()
    }

    // MARK: - Итоги периода
    private var totals: some View {
        let spent = periodExpenses.reduce(0.0) { $0 + $1.amount }
        return HStack(spacing: 10) {
            totalTile(title: "Потрачено", value: spent, highlighted: true)
            totalTile(title: "Получено", value: periodIncome, highlighted: false)
        }
    }

    private func totalTile(title: String, value: Double, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .opacity(0.8)
            Text(CurrencyManager.shared.format(value))
                .font(Theme.number(22, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText(value: value))
                .animation(Motion.digits, value: value)
        }
        .foregroundColor(highlighted ? Theme.onAccent : .white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlighted ? Theme.accent : Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - График
    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Траты по дням")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if let selectedPoint {
                    Text("\(selectedPoint.date.formatted(.dateTime.day().month(.abbreviated))): \(CurrencyManager.shared.format(selectedPoint.amount))")
                        .font(Theme.number(13))
                        .foregroundColor(Theme.accent)
                        .contentTransition(.numericText())
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
                }
            }

            chart
                .frame(height: 200)
        }
        .padding(18)
        .monoSurface(cornerRadius: 28)
        .animation(Motion.spring, value: selectedPoint?.date)
    }

    private var chart: some View {
        let data = chartPoints
        let selected = selectedPoint
        return Chart {
            ForEach(data) { item in
                BarMark(
                    x: .value("Дата", item.date, unit: .day),
                    y: .value("Траты", isChartGrown ? item.amount : 0)
                )
                .foregroundStyle(isSelected(item, selected) ? Theme.accent : Theme.line)
                .cornerRadius(4)
            }
        }
        .chartXSelection(value: $rawSelectedDate)
        // Столбики пружинят при показе и при смене периода
        .animation(Motion.spring, value: selectedPeriod)
        .animation(Motion.spring.delay(0.15), value: isChartGrown)
        .onAppear {
            isChartGrown = true
        }
        .sensoryFeedback(.selection, trigger: selectedPoint?.date)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let doubleVal = value.as(Double.self) {
                        Text(compactAmount(doubleVal))
                            .font(.caption2)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Theme.hairline)
            }
        }
    }

    private func isSelected(_ item: DailyAmount, _ selected: DailyAmount?) -> Bool {
        if let selected {
            return Calendar.current.isDate(item.date, inSameDayAs: selected.date)
        }
        return Calendar.current.isDateInToday(item.date)
    }

    // MARK: - История
    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoSectionHeader(title: "Расходы за период")

            let expenses = periodExpenses
            if expenses.isEmpty {
                Text("Нет операций за этот период")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(expenses) { transaction in
                    historyRow(transaction)
                }
            }
        }
    }

    private func historyRow(_ transaction: Transaction) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                MonoInitialBadge(title: transaction.title)

                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("\(transaction.category.name) · \(transaction.date.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text("−\(CurrencyManager.shared.format(transaction.amount))")
                    .font(Theme.number(16))
                    .foregroundColor(.white)
            }
            .frame(minHeight: 64)
            MonoDivider()
        }
    }
}
