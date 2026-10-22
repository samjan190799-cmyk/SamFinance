import SwiftUI

/// Все операции по дням. Фильтр «Проверить» показывает операции, категорию которых приложение подобрало наугад:
/// выбранная категория запоминается для магазина и в следующий раз подставляется сама.
struct TransactionsView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    @State private var filter: Filter = .all
    @State private var editing: Transaction? = nil

    enum Filter: Hashable {
        case all
        case review
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let items: [Transaction]

        var id: Date { day }
    }

    private var visibleTransactions: [Transaction] {
        financeService.transactions.filter { filter == .all || $0.needsReview == true }
    }

    /// Операции, сгруппированные по дням: новые дни сверху
    private var groups: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visibleTransactions) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            DayGroup(day: day, items: (grouped[day] ?? []).sorted { $0.date > $1.date })
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MonoSegmentedControl(
                        options: [Filter.all, Filter.review],
                        title: { $0 == .all ? "Все" : "Проверить (\(financeService.reviewCount))" },
                        selection: $filter
                    )
                    .padding(.top, 8)

                    content
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .monoScreen()
            .navigationTitle("Все операции")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $editing) { transaction in
                CategoryPickerSheet(transaction: transaction, financeService: financeService)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let dayGroups = groups
        if dayGroups.isEmpty {
            Text(filter == .review ? "Все категории проверены." : "Операций пока нет.")
                .font(.system(size: 14))
                .foregroundColor(Theme.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 56)
        } else {
            ForEach(dayGroups) { group in
                VStack(alignment: .leading, spacing: 0) {
                    MonoLabel(text: dayTitle(group.day))
                        .padding(.top, 28)
                        .padding(.bottom, 4)

                    ForEach(group.items) { transaction in
                        row(transaction)
                    }
                }
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) {
            return "Сегодня"
        }
        if calendar.isDateInYesterday(day) {
            return "Вчера"
        }
        return day.formatted(.dateTime.day().month(.wide))
    }

    private func row(_ transaction: Transaction) -> some View {
        let isIncome = transaction.type == .income
        let sign = isIncome ? "+" : "−"
        let needsReview = transaction.needsReview == true
        return VStack(spacing: 0) {
            Button {
                HapticManager.shared.impact(.light)
                editing = transaction
            } label: {
                HStack(spacing: 14) {
                    MonoInitialBadge(title: transaction.title)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(transaction.title)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(needsReview ? "\(transaction.category.name) · проверить" : transaction.category.name)
                            .font(.system(size: 13))
                            .foregroundColor(needsReview ? Theme.accent : Theme.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text("\(sign)\(CurrencyManager.shared.format(transaction.amount))")
                        .font(.system(size: 16))
                        .monospacedDigit()
                        .foregroundColor(isIncome ? Theme.accent : .white)
                }
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) {
                    HapticManager.shared.trigger(.warning)
                    withAnimation {
                        financeService.deleteTransaction(transaction)
                    }
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
            MonoDivider()
        }
    }
}

/// Выбор категории для операции: подходят только категории её типа
private struct CategoryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let transaction: Transaction
    let financeService: FinanceService

    private var categories: [Category] {
        financeService.categories.filter { $0.type == transaction.type }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(transaction.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Выбранная категория запомнится для этого магазина")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .padding(.vertical, 16)

                    ForEach(categories) { category in
                        categoryRow(category)
                    }
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
            .monoScreen()
            .navigationTitle("Категория")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func categoryRow(_ category: Category) -> some View {
        let isSelected = category.id == transaction.category.id
        return VStack(spacing: 0) {
            Button {
                choose(category)
            } label: {
                HStack {
                    Text(category.name)
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.accent)
                    }
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            MonoDivider()
        }
    }

    private func choose(_ category: Category) {
        financeService.updateCategory(transactionID: transaction.id, category: category)
        AutomationService.shared.learnCategory(merchant: transaction.brandName ?? transaction.title, category: category)
        HapticManager.shared.trigger(.success)
        dismiss()
    }
}
