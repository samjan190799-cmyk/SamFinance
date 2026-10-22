import SwiftUI
import Charts

/// Сумма трат за один день
struct DailyAmount: Identifiable {
    let date: Date
    let amount: Double

    var id: Date { date }
}

/// Траты по дням за последние N дней, включая сегодня
@MainActor
enum DailySpending {
    static func points(financeService: FinanceService, days: Int) -> [DailyAmount] {
        let calendar = Calendar.current
        var amounts: [Date: Double] = [:]

        for offset in 0..<max(days, 1) {
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
            .map { DailyAmount(date: $0.key, amount: $0.value) }
            .sorted { $0.date < $1.date }
    }
}

/// Короткая запись суммы: «148к ֏», «1,2 млн ֏»
@MainActor
func compactAmount(_ amountInBase: Double) -> String {
    let value = CurrencyManager.shared.convertFromBase(amountInBase)
    let symbol = CurrencyManager.shared.currentCurrency.symbol
    if value >= 1_000_000 {
        return String(format: "%.1f млн %@", value / 1_000_000, symbol)
    }
    if value >= 1_000 {
        return "\(Int((value / 1_000).rounded()))к \(symbol)"
    }
    return "\(Int(value.rounded())) \(symbol)"
}

/// Тонкая линия трат по дням на лаймовой карточке баланса: при показе прорисовывается слева направо
@MainActor
struct BalanceSparkline: View {
    let financeService: FinanceService
    @State private var isDrawn = false

    var body: some View {
        let points = DailySpending.points(financeService: financeService, days: 30)
        Chart(points) { point in
            LineMark(
                x: .value("Дата", point.date, unit: .day),
                y: .value("Траты", point.amount)
            )
            .foregroundStyle(Theme.onAccent)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .mask {
            Rectangle()
                .scaleEffect(x: isDrawn ? 1 : 0, anchor: .leading)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9).delay(0.15)) {
                isDrawn = true
            }
        }
        .accessibilityLabel("Траты по дням за 30 дней")
    }
}

/// Столбики трат за последние 7 дней; сегодняшний день лаймовый. При показе столбики вырастают по очереди.
@MainActor
struct WeekSpendingCard: View {
    let financeService: FinanceService
    let onTap: () -> Void
    @State private var isGrown = false

    var body: some View {
        let days = DailySpending.points(financeService: financeService, days: 7)
        let total = days.reduce(0.0) { $0 + $1.amount }
        let maxAmount = max(days.map(\.amount).max() ?? 0, 1)
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Траты за неделю")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text(CurrencyManager.shared.format(total))
                        .font(Theme.number(15))
                        .foregroundColor(.white)
                        .contentTransition(.numericText(value: total))
                        .animation(Motion.digits, value: total)
                }

                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        bar(for: day, maxAmount: maxAmount)
                            .frame(maxWidth: .infinity)
                            .animation(Motion.bouncy.delay(0.2 + Double(index) * 0.05), value: isGrown)
                    }
                }
                .frame(height: 96)
            }
            .padding(18)
            .monoSurface(cornerRadius: 28)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
        .onAppear {
            isGrown = true
        }
        .accessibilityLabel("Траты за неделю: \(CurrencyManager.shared.format(total))")
    }

    private func bar(for day: DailyAmount, maxAmount: Double) -> some View {
        let isToday = Calendar.current.isDateInToday(day.date)
        let height = isGrown ? max(8, CGFloat(day.amount / maxAmount) * 70) : 8
        let weekday = day.date.formatted(.dateTime.weekday(.abbreviated))
        let label = String(weekday.prefix(1)).uppercased() + String(weekday.dropFirst())
        return VStack(spacing: 6) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 10)
                .fill(isToday ? Theme.accent : Theme.line)
                .frame(width: 30, height: height)
            Text(label)
                .font(.system(size: 11, weight: isToday ? .semibold : .regular))
                .foregroundColor(isToday ? .white : Theme.textSecondary)
        }
    }
}

/// Сумма по категории за период
struct CategoryTotal: Identifiable {
    let category: Category
    let amount: Double

    var id: UUID { category.id }
}

/// Главные категории трат за 30 дней: карусель плиток, крайние плитки уменьшаются и гаснут
@MainActor
struct TopCategoriesRow: View {
    let financeService: FinanceService
    let onTap: () -> Void

    private var topCategories: [CategoryTotal] {
        var totals: [UUID: CategoryTotal] = [:]
        for transaction in financeService.transactions where transaction.type == .expense && TimePeriodFilter.month.contains(transaction.date) {
            let current = totals[transaction.category.id]?.amount ?? 0
            totals[transaction.category.id] = CategoryTotal(category: transaction.category, amount: current + transaction.amount)
        }
        return Array(totals.values.sorted { $0.amount > $1.amount }.prefix(6))
    }

    var body: some View {
        let items = topCategories
        if !items.isEmpty {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button(action: onTap) {
                            tile(item, highlighted: index == 0)
                        }
                        .buttonStyle(PressableButtonStyle(scale: 0.95))
                        .scrollTransition(axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.88)
                                .opacity(phase.isIdentity ? 1 : 0.45)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)
        }
    }

    private func tile(_ item: CategoryTotal, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: item.category.icon)
                .font(.system(size: 20))
                .foregroundColor(highlighted ? Theme.accent : .white)
            Spacer(minLength: 12)
            Text(item.category.name)
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
            Text(compactAmount(item.amount))
                .font(Theme.number(17))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(14)
        .frame(width: 124, alignment: .leading)
        .frame(minHeight: 104)
        .monoSurface(cornerRadius: 24)
    }
}

/// Доли категорий в тратах за период: кольцо и список под ним
@MainActor
struct DashboardCategoriesSection: View {
    let financeService: FinanceService
    let selectedPeriod: TimePeriodFilter
    @State private var isRevealed = false

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
            result.append(CategorySlice(id: "other", name: "Остальное", amount: rest, share: rest / total, color: Theme.shades[4]))
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
                    .foregroundColor(Theme.textSecondary)
                    .padding(.vertical, 16)
            } else {
                ring(items)
                rows(items)
            }
        }
        .animation(Motion.spring, value: selectedPeriod)
    }

    private func ring(_ items: [CategorySlice]) -> some View {
        Chart(items) { slice in
            SectorMark(
                angle: .value("Сумма", slice.amount),
                innerRadius: .ratio(0.78),
                angularInset: 2
            )
            .cornerRadius(4)
            .foregroundStyle(slice.color)
        }
        .chartLegend(.hidden)
        .frame(width: 150, height: 150)
        // Кольцо раскручивается и вырастает при показе
        .rotationEffect(.degrees(isRevealed ? 0 : -140))
        .scaleEffect(isRevealed ? 1 : 0.6)
        .opacity(isRevealed ? 1 : 0)
        .overlay {
            centerLabel(for: items.first)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(Motion.spring.delay(0.1)) {
                isRevealed = true
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func centerLabel(for slice: CategorySlice?) -> some View {
        if let slice {
            VStack(spacing: 2) {
                Text("\(Int((slice.share * 100).rounded()))%")
                    .font(Theme.number(26, weight: .bold))
                    .foregroundColor(.white)
                    .contentTransition(.numericText(value: slice.share))
                Text(slice.name)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 22)
        }
    }

    private func rows(_ items: [CategorySlice]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, slice in
                row(slice)
                    .appearAnimation(delay: 0.15 + Double(index) * Motion.stagger)
            }
        }
    }

    private func row(_ slice: CategorySlice) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Circle()
                    .fill(slice.color)
                    .frame(width: 10, height: 10)

                Text(slice.name)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(Int((slice.share * 100).rounded()))%")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)

                Text(CurrencyManager.shared.format(slice.amount))
                    .font(Theme.number(15))
                    .foregroundColor(.white)
                    .frame(minWidth: 96, alignment: .trailing)
            }
            .frame(minHeight: 48)
            MonoDivider()
        }
    }
}
