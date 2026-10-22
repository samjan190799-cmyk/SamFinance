import SwiftUI

/// Одна копилка: кольцо прогресса, план накопления, пополнение и снятие, журнал операций
@MainActor
struct GoalDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    let goalID: UUID

    @State private var moneyMode: GoalMoveMode?
    @State private var editorRequest: GoalEditorRequest?

    private var goal: Goal? { financeService.goals.first { $0.id == goalID } }

    var body: some View {
        Group {
            if let goal {
                content(goal)
            } else {
                // Копилку удалили (например, в редакторе): экран закрывается сам
                Color.clear.onAppear { dismiss() }
            }
        }
        .monoScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Изменить")) {
                    if let goal {
                        HapticManager.shared.impact(.light)
                        editorRequest = GoalEditorRequest(editing: goal)
                    }
                }
                .disabled(goal == nil)
            }
        }
        .sheet(item: $moneyMode) { mode in
            GoalMoneySheet(financeService: financeService, goalID: goalID, mode: mode)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $editorRequest) { request in
            GoalEditorView(financeService: financeService, request: request)
        }
    }

    private func content(_ goal: Goal) -> some View {
        let plan = GoalPlan(goal: goal)
        return ScrollView {
            VStack(spacing: 0) {
                header(goal, plan)
                    .appearAnimation(order: 0)
                planCard(goal, plan)
                    .padding(.top, 20)
                    .appearAnimation(order: 1)
                actionButtons(goal)
                    .padding(.top, 16)
                    .appearAnimation(order: 2)
                historySection(goal)
                    .padding(.top, 28)
                    .appearAnimation(order: 3)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Кольцо и суммы
    private func header(_ goal: Goal, _ plan: GoalPlan) -> some View {
        VStack(spacing: 14) {
            GoalRing(progress: plan.progress, tint: goal.tint)
                .frame(width: 208, height: 208)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: goal.iconName)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(goal.tint)
                        Text(verbatim: "\(GoalText.percent(plan))%")
                            .font(Theme.number(40, weight: .bold))
                            .foregroundColor(.white)
                            .contentTransition(.numericText(value: plan.progress))
                            .animation(Motion.digits, value: plan.progress)
                    }
                    .accessibilityHidden(true)
                }
                .padding(.top, 8)

            Text(goal.title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            VStack(spacing: 4) {
                Text(GoalText.money(plan.saved))
                    .font(Theme.number(34, weight: .bold))
                    .tracking(-0.5)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(value: plan.saved))
                    .animation(Motion.digits, value: plan.saved)
                Text(String(localized: "из \(GoalText.money(plan.target))"))
                    .font(.system(size: 15))
                    .foregroundColor(Theme.textSecondary)
            }

            Text(GoalText.statusTitle(plan.status))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(GoalText.statusColor(plan.status))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(GoalText.statusColor(plan.status).opacity(0.15))
                .clipShape(Capsule())

            if let cardLine = cardLine(goal) {
                Text(cardLine)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// На какой карте лежат деньги копилки
    private func cardLine(_ goal: Goal) -> String? {
        guard let cardId = goal.cardId,
              let card = financeService.cards.first(where: { $0.id == cardId }) else { return nil }
        return String(localized: "Карта: \(card.type), •••• \(card.last4)")
    }

    // MARK: - План
    private func planCard(_ goal: Goal, _ plan: GoalPlan) -> some View {
        let lines = GoalText.planLines(goal: goal, plan: plan)
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .monoSurface(cornerRadius: 24)
        .opacity(lines.isEmpty ? 0 : 1)
    }

    private func actionButtons(_ goal: Goal) -> some View {
        HStack(spacing: 10) {
            Button {
                HapticManager.shared.impact(.light)
                moneyMode = .deposit
            } label: {
                Text(String(localized: "Пополнить"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Theme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.pressable)

            Button {
                HapticManager.shared.impact(.light)
                moneyMode = .withdraw
            } label: {
                Text(String(localized: "Снять"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Theme.surfaceRaised)
                    .clipShape(Capsule())
            }
            .buttonStyle(.pressable)
            .disabled(goal.currentAmount <= 0)
            .opacity(goal.currentAmount <= 0 ? 0.4 : 1)
        }
    }

    // MARK: - Журнал
    private func historySection(_ goal: Goal) -> some View {
        let entries = goal.entries.sorted { $0.date > $1.date }
        // Деньги, отложенные до того, как копилка стала вести журнал
        let earlier = goal.currentAmount - goal.entries.reduce(0.0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 4) {
            MonoSectionHeader(title: String(localized: "История"))

            if entries.isEmpty && earlier <= 0.005 {
                Text(String(localized: "Пополнений пока не было. Нажмите «Пополнить», когда отложите первые деньги."))
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textTertiary)
                    .padding(.vertical, 12)
            } else {
                ForEach(entries) { entry in
                    entryRow(entry, goal: goal)
                }
                if earlier > 0.005 {
                    baseRow(earlier)
                }
            }
        }
    }

    private func entryRow(_ entry: GoalEntry, goal: Goal) -> some View {
        let isDeposit = entry.amount > 0
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: isDeposit ? "arrow.down.left" : "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isDeposit ? Theme.accent : Color.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.surfaceRaised)
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.note ?? (isDeposit ? String(localized: "Пополнение") : String(localized: "Снятие")))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }

                Spacer(minLength: 8)

                Text(verbatim: "\(isDeposit ? "+" : "−")\(GoalText.money(abs(entry.amount)))")
                    .font(Theme.number(15))
                    .foregroundColor(isDeposit ? Theme.accent : Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Menu {
                    Button(role: .destructive) {
                        HapticManager.shared.trigger(.warning)
                        withAnimation(Motion.spring) {
                            financeService.removeGoalEntry(goalID: goal.id, entryID: entry.id)
                        }
                    } label: {
                        Label(String(localized: "Отменить операцию"), systemImage: "arrow.uturn.backward")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "Действия"))
            }
            .frame(minHeight: 60)
            MonoDivider()
        }
    }

    private func baseRow(_ amount: Double) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Theme.surfaceRaised)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                Text(String(localized: "Было отложено раньше"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                Spacer(minLength: 8)
                Text(GoalText.money(amount))
                    .font(Theme.number(15))
                    .foregroundColor(Theme.textSecondary)
            }
            .frame(minHeight: 60)
            MonoDivider()
        }
    }
}

/// Копилка в листе: используется там, где нет навигации (например, под картой)
@MainActor
struct GoalDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    let goalID: UUID

    var body: some View {
        NavigationStack {
            GoalDetailView(financeService: financeService, goalID: goalID)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Закрыть")) {
                            dismiss()
                        }
                    }
                }
        }
    }
}
