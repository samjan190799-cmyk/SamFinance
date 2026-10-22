import SwiftUI

/// Экран банковских карт пользователя с привязанными накопительными целями (копилками)
/// и локализацией (Русский, English, Հայերեն).
@MainActor
struct CardsView: View {
    let financeService: FinanceService
    @State private var isShowingAddCardSheet = false
    @State private var selectedCardForDetails: Card? = nil
    @State private var selectedCardForNewGoal: Card? = nil
    @State private var languageManager = LanguageManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerView

                if financeService.cards.isEmpty {
                    emptyCardsPlaceholder
                } else {
                    VStack(spacing: 36) {
                        ForEach(financeService.cards) { card in
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
                        }
                    }
                    .padding(.top, 20)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
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
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}

/// Блок карты с кнопками действий и привязанными к ней накопительными целями
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
            CardItemView(card: card)
                .contextMenu {
                    Button(role: .destructive) {
                        HapticManager.shared.trigger(.warning)
                        withAnimation {
                            financeService.deleteCard(id: card.id)
                        }
                    } label: {
                        Label("delete_card".localized, systemImage: "trash")
                    }
                }

            actionButtons
                .padding(.top, 12)

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
                withAnimation {
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
        }
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
                    ForEach(goals) { goal in
                        CardGoalRowView(goal: goal, financeService: financeService)
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
                    financeService.addFundsToGoal(id: goal.id, amount: amount)
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
                    .frame(width: geo.size.width * CGFloat(progressPercent))
            }
        }
        .frame(height: 4)
    }
}

/// Визуальное представление банковской карты: плоская заливка, последние 4 цифры и баланс
struct CardItemView: View {
    let card: Card

    private var fillColors: [Color] {
        let colors = card.gradientColors.map { Color(hex: $0) }
        return colors.isEmpty ? [Theme.surface] : colors
    }

    /// Тёмный текст на светлой карте и белый на тёмной
    private var isLightCard: Bool {
        Theme.isLight(hex: card.gradientColors.first ?? card.colorHex)
    }

    private var primaryColor: Color {
        isLightCard ? .black : .white
    }

    private var secondaryColor: Color {
        isLightCard ? Color(hex: "#5A5A5E") : Theme.textSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            Spacer(minLength: 12)
            balanceBlock
            Spacer(minLength: 12)
            bottomRow
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .frame(height: 196)
        .foregroundColor(primaryColor)
        .background(
            LinearGradient(colors: fillColors, startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Theme.line, lineWidth: isLightCard ? 0 : 1))
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

/// Модальный экран создания новой карты
struct AddCardView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService

    @State private var cardPurpose: String = "card_for_gifts".localized
    @State private var holderName: String = "SAMVEL USER"
    @State private var balanceString: String = "1000"
    @State private var cardNumberRaw: String = "5244872190127642"
    @State private var expiryDate: String = "08/29"
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

    /// Маска формата карточного номера: 5244 8721 9012 7642
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

    var body: some View {
        NavigationStack {
            Form {
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
                        Text("base_balance".localized)
                        Spacer()
                        TextField("0", text: $balanceString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("full_card_number".localized)
                        Spacer()
                        TextField("5244 8721 9012 7642", text: $cardNumberRaw)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("expiry_date".localized)
                        Spacer()
                        TextField("08/29", text: $expiryDate)
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
                    .disabled(cardPurpose.isEmpty || balanceString.isEmpty || cardNumberRaw.isEmpty)
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
                cardPurpose = purpose
            }
    }

    private func themeSwatch(_ index: Int) -> some View {
        let theme = themes[index]
        let isSelected = selectedThemeIndex == index
        return Circle()
            .fill(LinearGradient(colors: theme.gradient.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 44, height: 44)
            .overlay(Circle().stroke(isSelected ? Theme.accent : Theme.line, lineWidth: isSelected ? 2 : 1))
            .padding(3)
            .onTapGesture {
                HapticManager.shared.impact(.light)
                selectedThemeIndex = index
            }
            .accessibilityLabel("card_color_theme".localized)
    }

    private func saveCard() {
        guard let balance = Double(balanceString.replacingOccurrences(of: ",", with: ".")) else { return }
        let theme = themes[selectedThemeIndex]
        let number = formattedCardNumber.isEmpty ? "5244 8721 9012 7642" : formattedCardNumber
        let card = Card(
            last4: Card.lastFourDigits(of: number),
            holderName: holderName.isEmpty ? "SAMVEL USER" : holderName,
            balance: balance,
            type: cardPurpose,
            colorHex: theme.colorHex,
            gradientColors: theme.gradient,
            isFrozen: false,
            expiryDate: expiryDate.isEmpty ? "08/29" : expiryDate
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
                        Text("base_balance".localized)
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
                detailRow(title: "Статус", value: card.isFrozen ? "freeze".localized : "Активна", showsDivider: false)
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
                isCopied = false
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                Text(isCopied ? "copied".localized : "copy_number".localized)
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.accent)
            .clipShape(Capsule())
        }
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
