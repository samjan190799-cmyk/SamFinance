import SwiftUI
import Charts

/// Тонкий линейный график трат за период. По нажатию открывает подробный график.
@MainActor
struct DashboardSpendingChart: View {
    let financeService: FinanceService
    let selectedPeriod: TimePeriodFilter
    let onTap: () -> Void

    struct Point: Identifiable {
        let date: Date
        let amount: Double

        var id: Date { date }
    }

    private var points: [Point] {
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
            .map { Point(date: $0.key, amount: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private var hasData: Bool {
        points.contains { $0.amount > 0 }
    }

    var body: some View {
        Button(action: onTap) {
            if hasData {
                chart
            } else {
                emptyPlaceholder
            }
        }
        .buttonStyle(.plain)
    }

    private var chart: some View {
        let data = points
        return Chart {
            ForEach(data) { point in
                LineMark(
                    x: .value("Дата", point.date, unit: .day),
                    y: .value("Траты", point.amount)
                )
                .foregroundStyle(Color.white)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .interpolationMethod(.catmullRom)
            }

            if let last = data.last {
                PointMark(
                    x: .value("Дата", last.date, unit: .day),
                    y: .value("Траты", last.amount)
                )
                .foregroundStyle(Color.white)
                .symbolSize(48)
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(height: 110)
    }

    private var emptyPlaceholder: some View {
        Text("no_chart_data".localized)
            .font(.system(size: 14))
            .foregroundColor(Theme.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
    }
}

/// Доли категорий в тратах за период: тонкое кольцо в оттенках серого и список под ним.
@MainActor
struct DashboardCategoriesSection: View {
    let financeService: FinanceService
    let selectedPeriod: TimePeriodFilter

    struct CategorySlice: Identifiable {
        let id: String
        let name: String
        let amount: Double
        let share: Double
        let color: Color
    }

    /// Четыре крупные категории и «Прочее» из остальных
    private var slices: [CategorySlice] {
        var totals: [String: Double] = [:]
        for transaction in financeService.transactions where transaction.type == .expense && selectedPeriod.contains(transaction.date) {
            totals[transaction.category.name, default: 0.0] += transaction.amount
        }

        let sorted = totals.sorted { $0.value > $1.value }
        let total = sorted.reduce(0.0) { $0 + $1.value }
        guard total > 0 else { return [] }

        var result: [CategorySlice] = []
        for (index, item) in sorted.prefix(4).enumerated() {
            result.append(CategorySlice(id: item.key, name: item.key, amount: item.value, share: item.value / total, color: Theme.shades[index]))
        }

        let rest = sorted.dropFirst(4).reduce(0.0) { $0 + $1.value }
        if rest > 0 {
            result.append(CategorySlice(id: "other", name: "Прочее", amount: rest, share: rest / total, color: Theme.shades[4]))
        }
        return result
    }

    var body: some View {
        let items = slices
        return VStack(alignment: .leading, spacing: 0) {
            MonoSectionHeader(title: "Категории")

            if items.isEmpty {
                Text("no_chart_data".localized)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textTertiary)
                    .padding(.vertical, 16)
            } else {
                ring(items)
                rows(items)
            }
        }
    }

    private func ring(_ items: [CategorySlice]) -> some View {
        Chart(items) { slice in
            SectorMark(
                angle: .value("Сумма", slice.amount),
                innerRadius: .ratio(0.82),
                angularInset: 2
            )
            .cornerRadius(3)
            .foregroundStyle(slice.color)
        }
        .chartLegend(.hidden)
        .frame(width: 140, height: 140)
        .overlay {
            centerLabel(for: items.first)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func centerLabel(for slice: CategorySlice?) -> some View {
        if let slice {
            VStack(spacing: 2) {
                Text("\(Int((slice.share * 100).rounded()))%")
                    .font(.system(size: 26, weight: .light))
                    .foregroundColor(.white)
                Text(slice.name)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
        }
    }

    private func rows(_ items: [CategorySlice]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { slice in
                row(slice)
            }
        }
    }

    private func row(_ slice: CategorySlice) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(slice.color)
                    .frame(width: 8, height: 8)

                Text(slice.name)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(Int((slice.share * 100).rounded()))%")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textTertiary)

                Text(CurrencyManager.shared.format(slice.amount))
                    .font(.system(size: 15))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .frame(minWidth: 96, alignment: .trailing)
            }
            .frame(minHeight: 48)
            MonoDivider()
        }
    }
}
