import SwiftUI

/// Экран банковских карт пользователя с привязанными накопительными целями (копилками)
/// и локализацией (Русский, English, Հայերեն). Карты листаются каруселью, под ней — действия и копилки текущей карты.
@MainActor
struct CardsView: View {
    let financeService: FinanceService
    @State private var isShowingAddCardSheet = false
    @State private var selectedCardForDetails: Card? = nil
    @State private var cardBeingEdited: Card? = nil
    @State private var selectedCardForNewGoal: Card? = nil
    @State private var isShowingSavings = false
    /// Карта в центре карусели; nil, пока пользователь не листал (тогда текущая — первая)
    @State private var centeredCardID: UUID? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentCard: Card? {
        financeService.cards.first { $0.id == centeredCardID } ?? financeService.cards.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerView
                    .padding(.horizontal, 20)
                    .appearAnimation(order: 0)

                if financeService.cards.isEmpty {
                    emptyCardsPlaceholder
                        .padding(.horizontal, 20)
                } else {
                    carousel
                        .padding(.top, 20)
                        .appearAnimation(order: 1)

                    if financeService.cards.count > 1 {
                        pageIndicator
                            .padding(.top, 16)
                    }

                    if let card = currentCard {
                        CardWithGoalsSection(
                            card: card,
                            financeService: financeService,
                            onShowDetails: {
                                selectedCardForDetails = card
                            },
                            onEdit: {
                                cardBeingEdited = card
                            },
                            onShowAllGoals: {
                                isShowingSavings = true
                            },
                            onAddGoal: {
                                selectedCardForNewGoal = card
                            }
                        )
                        // Новая карта — новый блок: прежний исчезает сразу, новый выплывает снизу
                        .id(card.id)
                        .transition(.identity)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .appearAnimation(order: 2)
                    }
                }
            }
            .padding(.bottom, 24)
            .animation(Motion.spring, value: currentCard?.id)
        }
        .scrollIndicators(.hidden)
        .monoScreen()
        .sheet(isPresented: $isShowingAddCardSheet) {
            CardEditorView(financeService: financeService)
        }
        .sheet(item: $cardBeingEdited) { card in
            CardEditorView(financeService: financeService, editing: card)
        }
        .sheet(item: $selectedCardForDetails) { card in
            CardDetailsSheet(card: card)
        }
        .sheet(item: $selectedCardForNewGoal) { card in
            GoalEditorView(financeService: financeService, request: GoalEditorRequest(card: card))
        }
        .sheet(isPresented: $isShowingSavings) {
            SavingsView(financeService: financeService)
        }
    }

    // MARK: - Карусель
    /// Соседние карты выглядывают по краям, уменьшены и повёрнуты к центру; листание с доводкой до карты
    private var carousel: some View {
        let tilt = reduceMotion ? 0.0 : 16.0
        return ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(financeService.cards) { card in
                    FlippableCardView(card: card)
                        .containerRelativeFrame(.horizontal)
                        .contextMenu {
                            Button {
                                HapticManager.shared.impact(.light)
                                cardBeingEdited = card
                            } label: {
                                Label(String(localized: "Изменить"), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                HapticManager.shared.trigger(.warning)
                                withAnimation(Motion.spring) {
                                    financeService.deleteCard(id: card.id)
                                }
                            } label: {
                                Label("delete_card".localized, systemImage: "trash")
                            }
                        }
                        .scrollTransition(axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.88)
                                .rotation3DEffect(.degrees(phase.value * -tilt), axis: (x: 0, y: 1, z: 0))
                                .opacity(phase.isIdentity ? 1 : 0.5)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 28, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $centeredCardID)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: centeredCardID)
    }

    /// Точки под каруселью: текущая карта вытягивается в лаймовую капсулу, по нажатию карусель листает к карте
    private var pageIndicator: some View {
        HStack(spacing: 2) {
            ForEach(financeService.cards) { card in
                let isCurrent = card.id == currentCard?.id
                Button {
                    withAnimation(Motion.spring) {
                        centeredCardID = card.id
                    }
                } label: {
                    Capsule()
                        .fill(isCurrent ? Theme.accent : Theme.line)
                        .frame(width: isCurrent ? 22 : 7, height: 7)
                        .frame(minWidth: 20, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(card.type), •••• \(card.last4)")
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Шапка
    private var headerView: some View {
        HStack {
            Text("cards_title".localized)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Spacer()
            MonoCircleButton(systemName: "plus", label: "order_card".localized, filled: true) {
                HapticManager.shared.impact(.light)
                isShowingAddCardSheet = true
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Заглушка, если карт пока нет
    private var emptyCardsPlaceholder: some View {
        VStack(spacing: 12) {
            FloatingCardIcon()
                .padding(.bottom, 12)

            Text("no_cards".localized)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)

            Text("no_cards_desc".localized)
                .font(.system(size: 14))
                .foregroundColor(Theme.textTertiary)
                .multilineTextAlignment(.center)

            Button {
                HapticManager.shared.impact(.light)
                isShowingAddCardSheet = true
            } label: {
                Text("add_card".localized)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.onAccent)
                    .padding(.horizontal, 28)
                    .frame(height: 48)
                    .background(Theme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.pressable)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
        .appearAnimation(order: 1)
    }
}

/// Иконка карты для пустого экрана: плавно покачивается вверх-вниз
private struct FloatingCardIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isUp = false

    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Theme.accent)
            .frame(width: 84, height: 54)
            .overlay(alignment: .bottomLeading) {
                Capsule()
                    .fill(Theme.onAccent.opacity(0.3))
                    .frame(width: 30, height: 5)
                    .padding(12)
            }
            .rotationEffect(.degrees(isUp ? -6 : 4))
            .offset(y: isUp ? -6 : 4)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    isUp = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// Действия и накопительные цели карты, которая сейчас в центре карусели
struct CardWithGoalsSection: View {
    let card: Card
    let financeService: FinanceService
    let onShowDetails: () -> Void
    let onEdit: () -> Void
    let onShowAllGoals: () -> Void
    let onAddGoal: () -> Void

    private var goals: [Goal] {
        financeService.goalsForCard(cardId: card.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionButtons

            reservedLine

            goalsSection
                .padding(.top, 24)
        }
    }

    /// Сколько денег карты лежит в копилках и сколько свободно
    @ViewBuilder
    private var reservedLine: some View {
        if !goals.isEmpty {
            HStack {
                Text(String(localized: "В копилках: \(CurrencyManager.shared.format(SavingsSummary.reserved(on: card.id, in: financeService.goals)))"))
                Spacer(minLength: 8)
                Text(String(localized: "Свободно: \(CurrencyManager.shared.format(financeService.freeBalance(of: card)))"))
            }
            .font(.system(size: 13))
            .monospacedDigit()
            .foregroundColor(Theme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.top, 14)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            outlineButton(title: "card_details".localized) {
                HapticManager.shared.impact(.light)
                onShowDetails()
            }
            outlineButton(title: String(localized: "Изменить")) {
                HapticManager.shared.impact(.light)
                onEdit()
            }
            outlineButton(title: card.isFrozen ? "unfreeze".localized : "freeze".localized) {
                HapticManager.shared.trigger(.success)
                withAnimation(Motion.spring) {
                    financeService.toggleFreezeCard(id: card.id)
                }
            }
        }
    }

    private func outlineButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.surfaceRaised)
                .clipShape(Capsule())
                .contentTransition(.opacity)
        }
        .buttonStyle(.pressable)
    }

    // MARK: - Копилки
    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            MonoSectionHeader(
                title: "\("card_goals_title".localized) (\(goals.count))",
                trailing: "+ \("goal".localized)",
                trailingColor: Theme.accent,
                onTrailingTap: onAddGoal
            )

            if goals.isEmpty {
                Text("no_card_goals".localized)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textTertiary)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(goals.enumerated()), id: \.element.id) { index, goal in
                        CardGoalRowView(goal: goal, financeService: financeService)
                            .appearAnimation(delay: 0.1 + Double(index) * Motion.stagger)
                    }
                }
                .padding(.top, 4)
            }

            if !financeService.goals.isEmpty {
                Button {
                    HapticManager.shared.impact(.light)
                    onShowAllGoals()
                } label: {
                    Text(String(localized: "Все копилки"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(.top, 4)
            }
        }
    }
}

/// Строка копилки под картой: название, накоплено, прогресс и статус. Нажатие открывает копилку, «Пополнить» сразу вносит сумму.
struct CardGoalRowView: View {
    let goal: Goal
    let financeService: FinanceService
    @State private var isShowingDetail = false
    @State private var moneyMode: GoalMoveMode?

    var body: some View {
        let plan = GoalPlan(goal: goal)
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    HapticManager.shared.impact(.light)
                    isShowingDetail = true
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: goal.iconName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(goal.tint)
                            Text(goal.title)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Text(verbatim: "\(CurrencyManager.shared.format(goal.currentAmount)) / \(CurrencyManager.shared.format(goal.targetAmount))")
                                .font(.system(size: 14))
                                .monospacedDigit()
                                .contentTransition(.numericText(value: goal.currentAmount))
                                .foregroundColor(Theme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }

                        GoalProgressBar(progress: plan.progress, tint: goal.tint, height: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack {
                    Text(GoalText.caption(goal: goal, plan: plan))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(GoalText.statusColor(plan.status))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        HapticManager.shared.impact(.light)
                        moneyMode = .deposit
                    } label: {
                        Text("deposit".localized)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.accent)
                            .frame(minHeight: 32)
                    }
                }
            }
            .padding(.vertical, 16)

            MonoDivider()
        }
        .sheet(item: $moneyMode) { mode in
            GoalMoneySheet(financeService: financeService, goalID: goal.id, mode: mode)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isShowingDetail) {
            GoalDetailSheet(financeService: financeService, goalID: goal.id)
        }
    }
}

/// Цвета карты: заливка по теме, тёмный текст на светлой карте и белый на тёмной
struct CardPalette {
    let fillColors: [Color]
    let isLight: Bool
    let pattern: CardPattern

    init(card: Card) {
        let colors = card.gradientColors.map { Color(hex: $0) }
        fillColors = colors.isEmpty ? [Theme.surface] : colors
        isLight = Theme.isLight(hex: card.gradientColors.first ?? card.colorHex)
        pattern = card.pattern ?? CardPattern.none
    }

    var primary: Color { isLight ? .black : .white }
    var secondary: Color { isLight ? Color(hex: "#5A5A5E") : Theme.textSecondary }
}

extension View {
    /// Форма и заливка карты: общая для лицевой и оборотной стороны
    func cardFace(_ palette: CardPalette) -> some View {
        self
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
            .frame(height: 196)
            .foregroundColor(palette.primary)
            .background {
                ZStack {
                    LinearGradient(colors: palette.fillColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    CardPatternView(pattern: palette.pattern, color: palette.primary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Theme.line, lineWidth: palette.isLight ? 0 : 1))
    }
}

/// Визуальное представление банковской карты: плоская заливка, последние 4 цифры и баланс
struct CardItemView: View {
    let card: Card

    private var palette: CardPalette { CardPalette(card: card) }

    private var secondaryColor: Color { palette.secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            Spacer(minLength: 12)
            balanceBlock
            Spacer(minLength: 12)
            bottomRow
        }
        .cardFace(palette)
        .opacity(card.isFrozen ? 0.5 : 1.0)
    }

    private var topRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let symbol = card.symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(card.type)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                }
                if let bank = card.bankName, !bank.isEmpty {
                    Text(bank)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(secondaryColor)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if card.isFrozen {
                Image(systemName: "snowflake")
                    .font(.system(size: 14))
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
            Text("•••• \(card.last4)")
                .font(.system(size: 15))
                .tracking(1.5)
                .monospacedDigit()
        }
    }

    private var balanceBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("total_balance".localized)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(secondaryColor)
            Text(CurrencyManager.shared.format(card.balance))
                .font(Theme.number(34, weight: .bold))
                .tracking(-1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText(value: card.balance))
                .animation(Motion.digits, value: card.balance)
        }
    }

    private var bottomRow: some View {
        HStack(alignment: .center) {
            Text(card.holderName.uppercased())
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(card.expiryDate)
            if let network = card.network {
                CardNetworkMark(network: network, color: palette.primary)
                    .padding(.leading, 6)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .tracking(0.8)
        .foregroundColor(secondaryColor)
    }
}

/// Карта в карусели: по нажатию переворачивается на оборот и обратно.
/// Сначала лицевая сторона доворачивается до ребра, затем из-за ребра выходит оборот, поэтому зеркального текста не видно.
struct FlippableCardView: View {
    let card: Card
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFlipped = false
    @State private var frontAngle = 0.0
    @State private var backAngle = -90.0

    var body: some View {
        ZStack {
            CardItemView(card: card)
                .rotation3DEffect(.degrees(frontAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .opacity(reduceMotion && isFlipped ? 0 : 1)
            CardBackView(card: card)
                .rotation3DEffect(.degrees(backAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .opacity(reduceMotion && !isFlipped ? 0 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .onTapGesture {
            flip()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isFlipped ? String(localized: "Показать лицевую сторону") : String(localized: "Показать оборот карты"))
    }

    private func flip() {
        HapticManager.shared.impact(.light)
        isFlipped.toggle()
        if reduceMotion {
            // Без поворота: стороны просто сменяют друг друга
            frontAngle = isFlipped ? 90 : 0
            backAngle = isFlipped ? 0 : -90
            return
        }
        let half = 0.18
        if isFlipped {
            withAnimation(.easeIn(duration: half)) { frontAngle = 90 }
            withAnimation(.easeOut(duration: half).delay(half)) { backAngle = 0 }
        } else {
            withAnimation(.easeIn(duration: half)) { backAngle = -90 }
            withAnimation(.easeOut(duration: half).delay(half)) { frontAngle = 0 }
        }
    }
}

/// Оборот карты: магнитная полоса, маска номера, держатель и срок
struct CardBackView: View {
    let card: Card

    var body: some View {
        let palette = CardPalette(card: card)
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(palette.primary.opacity(0.85))
                .frame(height: 34)
                .padding(.horizontal, -22)
                .padding(.top, 4)

            Spacer(minLength: 12)

            Text("•••• •••• •••• \(card.last4)")
                .font(Theme.number(20, weight: .semibold))
                .tracking(2)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 12)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("card_holder".localized)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(palette.secondary)
                    Text(card.holderName.uppercased())
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("expiry_date".localized)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(palette.secondary)
                    Text(card.expiryDate)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                }
            }
        }
        .cardFace(palette)
        .opacity(card.isFrozen ? 0.5 : 1.0)
    }
}

/// Модальный экран просмотра реквизитов карты. Полный номер читается из Keychain, CVV приложение не хранит.
struct CardDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let card: Card
    @State private var isCopied = false
    @State private var fullNumber: String?

    /// Номер из Keychain группами по 4 цифры. Если его нет (например, карта перенесена с другого устройства), показывает прочерк.
    private var displayedNumber: String {
        guard let fullNumber, !fullNumber.isEmpty else { return "—" }
        return stride(from: 0, to: fullNumber.count, by: 4)
            .map { String(fullNumber.dropFirst($0).prefix(4)) }
            .joined(separator: " ")
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("card_details".localized)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .padding(.top, 24)

            VStack(spacing: 0) {
                detailRow(title: "card_purpose".localized, value: card.type)
                detailRow(title: "card_holder".localized, value: card.holderName)
                detailRow(title: "full_card_number".localized, value: displayedNumber)
                detailRow(title: "expiry_date".localized, value: card.expiryDate)
                detailRow(title: String(localized: "Статус"), value: card.isFrozen ? "freeze".localized : String(localized: "Активна"), showsDivider: false)
            }
            .padding(.horizontal, 16)
            .monoSurface()

            copyButton

            Spacer()
        }
        .padding(.horizontal, 24)
        .presentationDetents([.medium])
        .monoScreen()
        .onAppear {
            fullNumber = CardSecretsStore.number(for: card.id)
        }
    }

    private var copyButton: some View {
        Button {
            if let fullNumber {
                // Номер остаётся только на этом устройстве (без Universal Clipboard) и стирается из буфера через минуту
                UIPasteboard.general.setItems(
                    [[UIPasteboard.typeAutomatic: fullNumber]],
                    options: [
                        .localOnly: true,
                        .expirationDate: Date().addingTimeInterval(60)
                    ]
                )
            }
            HapticManager.shared.trigger(.success)
            withAnimation {
                isCopied = true
            }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation {
                    isCopied = false
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                Text(isCopied ? "copied".localized : "copy_number".localized)
                    .contentTransition(.opacity)
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.accent)
            .clipShape(Capsule())
        }
        .buttonStyle(.pressable)
        .disabled(fullNumber == nil)
    }

    private func detailRow(title: String, value: String, showsDivider: Bool = true) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.textTertiary)
                Spacer(minLength: 12)
                Text(value)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(minHeight: 48)
            if showsDivider {
                MonoDivider()
            }
        }
    }
}
