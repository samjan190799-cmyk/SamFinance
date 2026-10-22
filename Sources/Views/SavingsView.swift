import SwiftUI

extension Goal {
    private var baseHex: String { gradientColors.first ?? colorHex }

    /// Цвет копилки на тёмном фоне: полоски, значок, кольцо
    var tint: Color { Theme.visibleTint(hex: baseHex) }

    /// Цвет значка поверх заливки цветом копилки
    var onTint: Color {
        let luminance = Theme.luminance(hex: baseHex)
        return luminance > 0.6 || luminance < 0.3 ? Color.black : Color.white
    }

    var iconName: String { symbol ?? GoalSymbol.fallback }
}

/// Тексты копилок: статусы, суммы, даты и план накопления
@MainActor
enum GoalText {
    static func money(_ value: Double) -> String {
        CurrencyManager.shared.format(value)
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    static func statusTitle(_ status: GoalPlan.Status) -> String {
        switch status {
        case .completed: return String(localized: "Достигнута")
        case .onTrack: return String(localized: "В графике")
        case .behind: return String(localized: "Отстаёт от плана")
        case .overdue: return String(localized: "Срок прошёл")
        case .noDeadline: return String(localized: "Без срока")
        }
    }

    static func statusColor(_ status: GoalPlan.Status) -> Color {
        switch status {
        case .completed, .onTrack: return Theme.accent
        case .behind: return Color.orange
        case .overdue: return Color.red
        case .noDeadline: return Theme.textSecondary
        }
    }

    /// Целое число процентов, округлённое вниз: 99,6 % ещё не 100
    static func percent(_ plan: GoalPlan) -> Int {
        plan.status == .completed ? 100 : Int((plan.progress * 100).rounded(.down))
    }

    /// Подпись в списках: срок, если он ещё впереди, иначе статус
    static func caption(goal: Goal, plan: GoalPlan) -> String {
        if plan.status == .onTrack || plan.status == .behind, let deadline = goal.deadline {
            return String(localized: "до \(date(deadline))")
        }
        return statusTitle(plan.status)
    }

    /// Строки плана: сколько осталось, что откладывать и когда цель будет достигнута
    static func planLines(goal: Goal, plan: GoalPlan) -> [String] {
        var lines: [String] = []
        switch plan.status {
        case .completed:
            if plan.overflow > 0 {
                lines.append(String(localized: "Сверх цели: \(money(plan.overflow))"))
            }
            if let done = goal.completedAt {
                lines.append(String(localized: "Достигнута \(date(done))"))
            }
        case .overdue:
            if let deadline = goal.deadline {
                lines.append(String(localized: "Срок прошёл \(date(deadline)), осталось накопить \(money(plan.remaining))"))
            }
            lines.append(contentsOf: forecast(plan))
        case .onTrack, .behind:
            if let deadline = goal.deadline, let days = plan.daysLeft {
                lines.append(String(localized: "До \(date(deadline)) осталось дней: \(days)"))
            }
            lines.append(String(localized: "Осталось накопить \(money(plan.remaining))"))
            if let days = plan.daysLeft {
                if days > 45, let perMonth = plan.perMonth {
                    lines.append(String(localized: "Откладывайте около \(money(perMonth)) в месяц"))
                } else if days > 7, let perWeek = plan.perWeek {
                    lines.append(String(localized: "Откладывайте около \(money(perWeek)) в неделю"))
                }
            }
            lines.append(contentsOf: forecast(plan))
        case .noDeadline:
            lines.append(String(localized: "Осталось накопить \(money(plan.remaining))"))
            let predicted = forecast(plan)
            lines.append(contentsOf: predicted.isEmpty
                ? [String(localized: "Пополняйте копилку регулярно, и здесь появится прогноз")]
                : predicted)
        }
        return lines
    }

    private static func forecast(_ plan: GoalPlan) -> [String] {
        guard let predicted = plan.forecastDate else { return [] }
        return [String(localized: "При текущем темпе цель будет достигнута к \(date(predicted))")]
    }
}

/// Заполненная часть полоски растёт при показе и при каждом изменении
struct GoalProgressBar: View {
    let progress: Double
    let tint: Color
    var height: CGFloat = 6
    @State private var isFilled = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.hairline)
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * CGFloat(isFilled ? min(max(progress, 0), 1) : 0))
            }
        }
        .frame(height: height)
        .animation(Motion.spring, value: progress)
        .onAppear {
            withAnimation(Motion.spring.delay(0.2)) {
                isFilled = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// Кольцо прогресса: дуга рисуется от верха по часовой стрелке
struct GoalRing: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.hairline, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .onAppear {
            if reduceMotion {
                shown = progress
            } else {
                withAnimation(.easeOut(duration: 0.9)) {
                    shown = progress
                }
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(Motion.spring) {
                shown = newValue
            }
        }
        .accessibilityHidden(true)
    }
}

/// Круглый значок копилки в её цвете
struct GoalIconBadge: View {
    let goal: Goal
    var size: CGFloat = 48

    var body: some View {
        Image(systemName: goal.iconName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundColor(goal.onTint)
            .frame(width: size, height: size)
            .background(goal.tint)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

/// Строка копилки в списках: значок, название, полоска прогресса, сумма и статус
struct GoalCardView: View {
    let goal: Goal

    var body: some View {
        let plan = GoalPlan(goal: goal)
        HStack(spacing: 14) {
            GoalIconBadge(goal: goal)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(goal.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(verbatim: "\(GoalText.percent(plan))%")
                        .font(Theme.number(15))
                        .monospacedDigit()
                        .foregroundColor(Theme.textSecondary)
                }

                GoalProgressBar(progress: plan.progress, tint: goal.tint)

                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: "\(GoalText.money(plan.saved)) / \(GoalText.money(plan.target))")
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text(GoalText.caption(goal: goal, plan: plan))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(GoalText.statusColor(plan.status))
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .monoSurface(cornerRadius: 24)
        .accessibilityElement(children: .combine)
    }
}

/// Все копилки: итог, активные и достигнутые, создание новой
@MainActor
struct SavingsView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    @State private var editorRequest: GoalEditorRequest?

    private var summary: SavingsSummary { SavingsSummary(goals: financeService.goals) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if financeService.goals.isEmpty {
                        emptyState
                    } else {
                        summaryCard
                            .appearAnimation(order: 0)
                        goalsSection(title: String(localized: "Активные"), goals: SavingsSummary.sortedActive(financeService.goals))
                        goalsSection(title: String(localized: "Достигнутые"), goals: SavingsSummary.completed(financeService.goals))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .monoScreen()
            .navigationTitle(String(localized: "Копилки"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Закрыть")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        HapticManager.shared.impact(.light)
                        editorRequest = GoalEditorRequest()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: "Новая копилка"))
                }
            }
            .navigationDestination(for: UUID.self) { id in
                GoalDetailView(financeService: financeService, goalID: id)
            }
            .sheet(item: $editorRequest) { request in
                GoalEditorView(financeService: financeService, request: request)
            }
        }
    }

    // MARK: - Итог
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Отложено всего"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textSecondary)

            Text(GoalText.money(summary.totalSaved))
                .font(Theme.number(40, weight: .bold))
                .tracking(-1)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(value: summary.totalSaved))
                .animation(Motion.digits, value: summary.totalSaved)

            if summary.activeCount > 0 {
                GoalProgressBar(progress: summary.progress, tint: Theme.accent, height: 8)

                Text(String(localized: "По активным: \(GoalText.money(summary.activeSaved)) из \(GoalText.money(summary.activeTarget))"))
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            HStack(spacing: 8) {
                countPill(String(localized: "Активных: \(summary.activeCount)"))
                if summary.completedCount > 0 {
                    countPill(String(localized: "Достигнуто: \(summary.completedCount)"))
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .monoSurface(cornerRadius: 28)
        .padding(.top, 8)
    }

    private func countPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.surfaceRaised)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func goalsSection(title: String, goals: [Goal]) -> some View {
        if !goals.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                MonoSectionHeader(title: title)
                ForEach(Array(goals.enumerated()), id: \.element.id) { index, goal in
                    NavigationLink(value: goal.id) {
                        GoalCardView(goal: goal)
                    }
                    .buttonStyle(.pressable)
                    .appearAnimation(delay: 0.1 + Double(index) * Motion.stagger)
                }
            }
            .padding(.top, 24)
        }
    }

    // MARK: - Пока нет ни одной копилки
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "banknote.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(Theme.onAccent)
                .frame(width: 72, height: 72)
                .background(Theme.accent)
                .clipShape(Circle())
                .padding(.top, 24)
                .padding(.bottom, 8)
                .accessibilityHidden(true)

            Text(String(localized: "Копилок пока нет"))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(String(localized: "Откладывайте деньги под цель: приложение подскажет, сколько класть в неделю или месяц, и покажет, когда цель будет достигнута."))
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            Text(String(localized: "С чего начать"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textTertiary)
                .padding(.top, 14)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(GoalIdea.all) { idea in
                    ideaButton(idea)
                }
            }

            PrimaryButton(title: String(localized: "Создать копилку")) {
                HapticManager.shared.impact(.light)
                editorRequest = GoalEditorRequest()
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .appearAnimation(order: 0)
    }

    private func ideaButton(_ idea: GoalIdea) -> some View {
        Button {
            HapticManager.shared.impact(.light)
            editorRequest = GoalEditorRequest(idea: idea)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: idea.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.accent)
                Text(idea.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 52)
            .monoSurface(cornerRadius: 18)
        }
        .buttonStyle(.pressable)
    }
}

/// Блок «Копилки» на обзоре: общая сумма и ближайшие цели; нажатие открывает все копилки
@MainActor
struct SavingsPreviewCard: View {
    let financeService: FinanceService
    let onOpen: () -> Void

    var body: some View {
        let summary = SavingsSummary(goals: financeService.goals)
        let top = Array(SavingsSummary.sortedActive(financeService.goals).prefix(3))
        return VStack(alignment: .leading, spacing: 10) {
            MonoSectionHeader(
                title: String(localized: "Копилки"),
                trailing: financeService.goals.isEmpty ? nil : String(localized: "Все"),
                onTrailingTap: onOpen
            )

            Button {
                HapticManager.shared.impact(.light)
                onOpen()
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    if financeService.goals.isEmpty {
                        emptyContent
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            Text(GoalText.money(summary.totalSaved))
                                .font(Theme.number(28, weight: .bold))
                                .tracking(-0.5)
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .contentTransition(.numericText(value: summary.totalSaved))
                                .animation(Motion.digits, value: summary.totalSaved)
                            Spacer(minLength: 8)
                            Text(String(localized: "Отложено"))
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textSecondary)
                        }

                        ForEach(top) { goal in
                            miniRow(goal)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .monoSurface(cornerRadius: 24)
            }
            .buttonStyle(.pressable)
        }
    }

    private var emptyContent: some View {
        HStack(spacing: 14) {
            Image(systemName: "banknote.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.onAccent)
                .frame(width: 44, height: 44)
                .background(Theme.accent)
                .clipShape(Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Копите на цели"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text(String(localized: "Создайте первую копилку и следите, как растёт накопление."))
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
        }
    }

    private func miniRow(_ goal: Goal) -> some View {
        let plan = GoalPlan(goal: goal)
        return VStack(spacing: 6) {
            HStack {
                Image(systemName: goal.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(goal.tint)
                Text(goal.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: "\(GoalText.percent(plan))%")
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundColor(Theme.textSecondary)
            }
            GoalProgressBar(progress: plan.progress, tint: goal.tint, height: 4)
        }
        .accessibilityElement(children: .combine)
    }
}
