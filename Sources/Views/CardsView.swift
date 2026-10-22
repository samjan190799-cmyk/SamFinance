import SwiftUI

/// Экран банковских карт пользователя с привязанными накопительными целями (копилками)
/// и локализацией (Русский, English, Հայերեն). Карты листаются каруселью, под ней — действия и копилки текущей карты.
@MainActor
struct CardsView: View {
    let financeService: FinanceService
    @State private var isShowingAddCardSheet = false
    @State private var selectedCardForDetails: Card? = nil
    @State private var selectedCardForNewGoal: Card? = nil
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
            AddCardView(financeService: financeService)
        }
        .sheet(item: $selectedCardForDetails) { card in
            CardDetailsSheet(card: card)
        }
        .sheet(item: $selectedCardForNewGoal) { card in
            AddGoalForCardView(card: card, financeService: financeService)
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
    let onAddGoal: () -> Void

    private var goals: [Goal] {
        financeService.goalsForCard(cardId: card.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionButtons

            goalsSection
                .padding(.top, 24)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            outlineButton(title: "card_details".localized) {
                HapticManager.shared.impact(.light)
                onShowDetails()
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
        }
    }
}

/// Строка копилки, привязанной к карте: название, накоплено из цели и тонкая полоска прогресса
struct CardGoalRowView: View {
    let goal: Goal
    let financeService: FinanceService
    @State private var isShowingDepositAlert = false
    @State private var depositAmountString = ""
    /// Полоска прогресса наполняется при показе и после пополнения
    @State private var isFilled = false

    private var progressPercent: Double {
        guard goal.targetAmount > 0 else { return 0.0 }
        return min(max(goal.currentAmount / goal.targetAmount, 0.0), 1.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(goal.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text("\(CurrencyManager.shared.format(goal.currentAmount)) / \(CurrencyManager.shared.format(goal.targetAmount))")
                        .font(.system(size: 14))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: goal.currentAmount))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                progressBar

                HStack {
                    Spacer()
                    Button {
                        HapticManager.shared.impact(.light)
                        isShowingDepositAlert = true
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
        .contextMenu {
            Button(role: .destructive) {
                financeService.deleteGoal(id: goal.id)
            } label: {
                Label("delete_card".localized, systemImage: "trash")
            }
        }
        .alert(goal.title, isPresented: $isShowingDepositAlert) {
            TextField("Сумма (\(CurrencyManager.shared.currentCurrency.symbol))", text: $depositAmountString)
                .keyboardType(.decimalPad)
            Button("cancel".localized, role: .cancel) {
                depositAmountString = ""
            }
            Button("deposit".localized) {
                if let amount = Double(depositAmountString.replacingOccurrences(of: ",", with: ".")) {
                    HapticManager.shared.trigger(.success)
                    withAnimation(Motion.spring) {
                        financeService.addFundsToGoal(id: goal.id, amount: amount)
                    }
                }
                depositAmountString = ""
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.hairline)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: geo.size.width * CGFloat(isFilled ? progressPercent : 0))
            }
        }
        .frame(height: 4)
        .onAppear {
            withAnimation(Motion.spring.delay(0.25)) {
                isFilled = true
            }
        }
    }
}

/// Цвета карты: заливка по теме, тёмный текст на светлой карте и белый на тёмной
struct CardPalette {
    let fillColors: [Color]
    let isLight: Bool

    init(card: Card) {
        let colors = card.gradientColors.map { Color(hex: $0) }
        fillColors = colors.isEmpty ? [Theme.surface] : colors
        isLight = Theme.isLight(hex: card.gradientColors.first ?? card.colorHex)
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
            .background(
                LinearGradient(colors: palette.fillColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
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
        HStack(alignment: .firstTextBaseline) {
            Text(card.type)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
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
        HStack {
            Text(card.holderName.uppercased())
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(card.expiryDate)
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

/// Модальный экран создания новой карты
struct AddCardView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService

    @State private var cardPurpose: String = ""
    @State private var holderName: String = ""
    @State private var balanceString: String = ""
    @State private var cardNumberRaw: String = ""
    @State private var expiryDate: String = ""
    @State private var selectedThemeIndex = 0

    var defaultPurposes: [String] {
        [
            "card_for_gifts".localized,
            "card_for_online".localized,
            "card_for_travel".localized,
            "main_card".localized
        ]
    }

    /// Темы карты «Пульс»: лаймовая, графитовая, чёрная с контуром и светлая
    let themes = [
        (colorHex: "#C6F432", gradient: ["#C6F432", "#B2E01E"]),
        (colorHex: "#2A2B30", gradient: ["#2A2B30", "#1C1D21"]),
        (colorHex: "#000000", gradient: ["#000000", "#000000"]),
        (colorHex: "#F4F4F5", gradient: ["#F4F4F5", "#DCDCE0"])
    ]

    /// Маска формата карточного номера: 0000 0000 0000 0000
    private var formattedCardNumber: String {
        let clean = cardNumberRaw.filter { $0.isNumber }
        var result = ""
        for (index, char) in clean.prefix(16).enumerated() {
            if index > 0 && index % 4 == 0 {
                result.append(" ")
            }
            result.append(char)
        }
        return result
    }

    private var parsedBalance: Double? {
        Double(balanceString.replacingOccurrences(of: ",", with: "."))
    }

    /// Срок действия в виде ММ/ГГ; принимает «0829» и «08/29», иначе nil
    private var normalizedExpiry: String? {
        let digits = expiryDate.filter { $0.isNumber }
        guard digits.count == 4, let month = Int(digits.prefix(2)), (1...12).contains(month) else { return nil }
        return "\(digits.prefix(2))/\(digits.suffix(2))"
    }

    /// Все поля заполнены: ничего не подставляется за пользователя
    private var isFormValid: Bool {
        !cardPurpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !holderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && parsedBalance != nil
            && cardNumberRaw.filter { $0.isNumber }.count >= 13
            && normalizedExpiry != nil
    }

    /// Как будет выглядеть карта: обновляется на лету при вводе и смене темы; пустые поля показаны заглушками
    private var previewCard: Card {
        let theme = themes[selectedThemeIndex]
        let digits = cardNumberRaw.filter { $0.isNumber }
        let trimmedHolder = holderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPurpose = cardPurpose.trimmingCharacters(in: .whitespacesAndNewlines)
        return Card(
            last4: digits.count >= 4 ? Card.lastFourDigits(of: digits) : "0000",
            holderName: trimmedHolder.isEmpty ? "card_holder".localized : trimmedHolder,
            balance: parsedBalance ?? 0,
            type: trimmedPurpose.isEmpty ? "new_card".localized : trimmedPurpose,
            colorHex: theme.colorHex,
            gradientColors: theme.gradient,
            isFrozen: false,
            expiryDate: normalizedExpiry ?? String(localized: "ММ/ГГ")
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CardItemView(card: previewCard)
                        .animation(Motion.spring, value: selectedThemeIndex)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    TextField("card_purpose".localized, text: $cardPurpose)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(defaultPurposes, id: \.self) { purpose in
                                purposeChip(purpose)
                            }
                        }
                    }
                } header: {
                    Text("card_purpose".localized)
                }

                Section {
                    TextField("card_holder".localized, text: $holderName)
                        .textInputAutocapitalization(.characters)

                    HStack {
                        Text(String(localized: "Баланс (\(CurrencyManager.shared.baseCurrency.symbol))"))
                        Spacer()
                        TextField("0", text: $balanceString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("full_card_number".localized)
                        Spacer()
                        TextField("0000 0000 0000 0000", text: $cardNumberRaw)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("expiry_date".localized)
                        Spacer()
                        TextField(String(localized: "ММ/ГГ"), text: $expiryDate)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("card_requisites".localized)
                }

                Section {
                    HStack(spacing: 16) {
                        ForEach(0..<themes.count, id: \.self) { index in
                            themeSwatch(index)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("card_color_theme".localized)
                }
            }
            .monoForm()
            .navigationTitle("new_card".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localized) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save".localized) {
                        saveCard()
                    }
                    .disabled(!isFormValid)
                }
            }
        }
    }

    private func purposeChip(_ purpose: String) -> some View {
        let isSelected = cardPurpose == purpose
        return Text(purpose)
            .font(.system(size: 13))
            .foregroundColor(isSelected ? Theme.onAccent : .white)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(isSelected ? Theme.accent : Color.clear)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: isSelected ? 0 : 1))
            .onTapGesture {
                HapticManager.shared.selection()
                withAnimation(Motion.spring) {
                    cardPurpose = purpose
                }
            }
    }

    private func themeSwatch(_ index: Int) -> some View {
        let theme = themes[index]
        let isSelected = selectedThemeIndex == index
        return Circle()
            .fill(LinearGradient(colors: theme.gradient.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 44, height: 44)
            .overlay(Circle().stroke(isSelected ? Theme.accent : Theme.line, lineWidth: isSelected ? 2 : 1))
            .scaleEffect(isSelected ? 1.12 : 1)
            .padding(3)
            .onTapGesture {
                HapticManager.shared.impact(.light)
                withAnimation(Motion.bouncy) {
                    selectedThemeIndex = index
                }
            }
            .accessibilityLabel("card_color_theme".localized)
    }

    private func saveCard() {
        guard isFormValid, let balance = parsedBalance, let expiry = normalizedExpiry else { return }
        let theme = themes[selectedThemeIndex]
        let number = formattedCardNumber
        let card = Card(
            last4: Card.lastFourDigits(of: number),
            holderName: holderName.trimmingCharacters(in: .whitespacesAndNewlines),
            balance: balance,
            type: cardPurpose.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: theme.colorHex,
            gradientColors: theme.gradient,
            isFrozen: false,
            expiryDate: expiry
        )
        financeService.addCard(card, number: number)
        HapticManager.shared.trigger(.success)
        dismiss()
    }
}

/// Модальный экран создания цели для конкретной карты
struct AddGoalForCardView: View {
    @Environment(\.dismiss) private var dismiss
    let card: Card
    let financeService: FinanceService

    @State private var title: String = ""
    @State private var targetAmountString: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(card.type) (•••• \(card.last4))")
                        .font(.subheadline.bold())
                        .foregroundColor(Theme.textSecondary)
                } header: {
                    Text("card_purpose".localized)
                }

                Section {
                    TextField("goal".localized, text: $title)

                    HStack {
                        Text(String(localized: "Цель (\(CurrencyManager.shared.baseCurrency.symbol))"))
                        Spacer()
                        TextField("0", text: $targetAmountString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("goal".localized)
                }
            }
            .monoForm()
            .navigationTitle("new_card_goal".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localized) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save".localized) {
                        saveGoal()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
    }

    private var isSaveDisabled: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        Double(targetAmountString.replacingOccurrences(of: ",", with: ".")) ?? 0 <= 0
    }

    private func saveGoal() {
        guard let targetAmount = Double(targetAmountString.replacingOccurrences(of: ",", with: ".")) else { return }
        let goal = Goal(
            cardId: card.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            targetAmount: targetAmount,
            currentAmount: 0.0,
            colorHex: "#C6F432",
            gradientColors: ["#C6F432", "#B2E01E"]
        )
        financeService.addGoal(goal)
        HapticManager.shared.trigger(.success)
        dismiss()
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
