import SwiftUI

/// Экран управления банковскими картами пользователя с привязанными накопительными целями (копилочками)
/// и полной поддержкой локализации (Русский, English, Հայերեն).
@MainActor
struct CardsView: View {
    let financeService: FinanceService
    @State private var isShowingAddCardSheet = false
    @State private var selectedCardForDetails: Card? = nil
    @State private var selectedCardForNewGoal: Card? = nil
    @State private var languageManager = LanguageManager.shared
    
    private var isSmallScreen: Bool {
        UIScreen.main.bounds.height < 750
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: "#0E0F12") // Темный глубокий фон
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Кастомная шапка
                headerView
                    .padding(.horizontal, 24)
                    .padding(.top, isSmallScreen ? 34 : 54)
                    .padding(.bottom, isSmallScreen ? 16 : 24)
                
                // Список карт с привязанными копилками
                if financeService.cards.isEmpty {
                    emptyCardsPlaceholder
                } else {
                    ScrollView {
                        VStack(spacing: isSmallScreen ? 20 : 28) {
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
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                        .padding(.bottom, isSmallScreen ? 110 : 140)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .preferredColorScheme(.dark)
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
                .font(.system(size: isSmallScreen ? 28 : 32, weight: .bold))
                .foregroundColor(.white)
            
            Spacer()
            
            Button {
                HapticManager.shared.trigger(.success)
                isShowingAddCardSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("order_card".localized)
                        .font(.system(size: isSmallScreen ? 11 : 13, weight: .semibold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, isSmallScreen ? 12 : 16)
                .padding(.vertical, isSmallScreen ? 6 : 8)
                .background(Color.white)
                .clipShape(Capsule())
            }
        }
    }
    
    // MARK: - Заглушка, если карт пока нет
    private var emptyCardsPlaceholder: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "creditcard.fill")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.15))
            
            Text("no_cards".localized)
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))
            
            Text("no_cards_desc".localized)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                HapticManager.shared.trigger(.success)
                isShowingAddCardSheet = true
            } label: {
                Text("add_card".localized)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .padding(.bottom, 100)
    }
}

/// Блок карты с привязанными к ней накопительными целями
struct CardWithGoalsSection: View {
    let card: Card
    let financeService: FinanceService
    let onShowDetails: () -> Void
    let onAddGoal: () -> Void
    
    @State private var isShowingGoals = true
    
    private var goals: [Goal] {
        financeService.goalsForCard(cardId: card.id)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Карточка банка
            CardItemView(
                card: card,
                financeService: financeService,
                onShowDetails: onShowDetails
            )
            .contextMenu {
                Button {
                    financeService.toggleFreezeCard(id: card.id)
                } label: {
                    Label(
                        card.isFrozen ? "unfreeze".localized : "freeze".localized,
                        systemImage: card.isFrozen ? "snowflake.circle.fill" : "snowflake"
                    )
                }
                
                Button(role: .destructive) {
                    HapticManager.shared.trigger(.warning)
                    withAnimation(.spring()) {
                        financeService.deleteCard(id: card.id)
                    }
                } label: {
                    Label("delete_card".localized, systemImage: "trash")
                }
            }
            
            // Заголовок целей карты и кнопка добавления
            VStack(spacing: 10) {
                HStack {
                    Button {
                        withAnimation(.spring()) {
                            isShowingGoals.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isShowingGoals ? "chevron.down" : "chevron.right")
                                .font(.caption.bold())
                                .foregroundColor(.gray)
                            
                            Text("\("card_goals_title".localized) (\(goals.count))")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: onAddGoal) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("goal".localized)
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 6)
                
                // Список копилок карты
                if isShowingGoals {
                    if goals.isEmpty {
                        HStack {
                            Text("no_card_goals".localized)
                                .font(.caption)
                                .foregroundColor(.gray)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(12)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(goals) { goal in
                                CardGoalRowView(goal: goal, financeService: financeService)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Строка копилки, привязанной к карте
struct CardGoalRowView: View {
    let goal: Goal
    let financeService: FinanceService
    @State private var isShowingDepositAlert = false
    @State private var depositAmountString = ""
    
    private var progressPercent: Double {
        guard goal.targetAmount > 0 else { return 0.0 }
        return goal.currentAmount / goal.targetAmount
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: goal.gradientColors.map { Color(hex: $0) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: "star.fill").font(.system(size: 12)).foregroundColor(.white))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 5)
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: goal.colorHex))
                            .frame(width: max(0, min(geo.size.width * CGFloat(progressPercent), geo.size.width)), height: 5)
                    }
                }
                .frame(height: 5)
            }
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(CurrencyManager.shared.format(goal.currentAmount)) / \(CurrencyManager.shared.format(goal.targetAmount))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                
                Button {
                    HapticManager.shared.impact(.light)
                    isShowingDepositAlert = true
                } label: {
                    Text("deposit".localized)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
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
}

/// Визуальное представление банковской карты
struct CardItemView: View {
    let card: Card
    let financeService: FinanceService
    let onShowDetails: () -> Void
    
    private var isSmallScreen: Bool {
        UIScreen.main.bounds.height < 750
    }
    
    /// Отображает последние 4 цифры карты
    private var lastFourDigits: String {
        let clean = card.number.replacingOccurrences(of: " ", with: "")
        if clean.count >= 4 {
            return String(clean.suffix(4))
        }
        return card.number
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.type)
                        .font(.system(size: isSmallScreen ? 15 : 17, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("\( "total_balance".localized ): \(CurrencyManager.shared.format(card.balance))")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                }
                
                Spacer()
                
                Text("•••• \(lastFourDigits)")
                    .font(.system(size: isSmallScreen ? 14 : 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 24)
            .padding(.top, isSmallScreen ? 18 : 24)
            
            Spacer()
            
            HStack(alignment: .bottom) {
                HStack(spacing: 10) {
                    CardActionButton(iconName: card.isFrozen ? "snowflake.circle.fill" : "snowflake") {
                        HapticManager.shared.trigger(.success)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            financeService.toggleFreezeCard(id: card.id)
                        }
                    }
                    .foregroundColor(card.isFrozen ? .blue : .white)
                    
                    CardActionButton(iconName: "creditcard") {
                        HapticManager.shared.impact(.light)
                        onShowDetails()
                    }
                }
                
                Spacer()
                
                Text(card.holderName)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, isSmallScreen ? 18 : 24)
        }
        .frame(height: isSmallScreen ? 150 : 180)
        .background {
            RoundedRectangle(cornerRadius: isSmallScreen ? 20 : 24)
                .fill(
                    LinearGradient(
                        colors: card.gradientColors.map { Color(hex: $0) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(card.isFrozen ? 0.55 : 1.0)
        }
        .overlay {
            if card.isFrozen {
                RoundedRectangle(cornerRadius: isSmallScreen ? 20 : 24)
                    .stroke(Color.blue.opacity(0.35), lineWidth: 2)
            }
        }
        .shadow(color: Color(hex: card.colorHex).opacity(card.isFrozen ? 0.12 : 0.38), radius: isSmallScreen ? 12 : 18, x: 0, y: isSmallScreen ? 6 : 10)
    }
}

/// Полупрозрачная круглая кнопка действия на карте
struct CardActionButton: View {
    let iconName: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.12))
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
    }
}

/// Модальный экран создания/выпуска новой карты с вводом полных 16-значных реквизитов
struct AddCardView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    
    @State private var cardPurpose: String = "card_for_gifts".localized
    @State private var holderName: String = "SAMVEL USER"
    @State private var balanceString: String = "1000"
    @State private var cardNumberRaw: String = "5244872190127642"
    @State private var expiryDate: String = "08/29"
    @State private var cvv: String = "123"
    @State private var selectedThemeIndex = 0
    
    var defaultPurposes: [String] {
        [
            "card_for_gifts".localized,
            "card_for_online".localized,
            "card_for_travel".localized,
            "main_card".localized
        ]
    }
    
    let themes = [
        (colorHex: "#FF2D55", gradient: ["#FF2D55", "#FF5E62"]),
        (colorHex: "#00F2FE", gradient: ["#00F2FE", "#4FACFE"]),
        (colorHex: "#AF52DE", gradient: ["#AF52DE", "#7A00FF"]),
        (colorHex: "#34C759", gradient: ["#34C759", "#11998E"])
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
                                Text(purpose)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(cardPurpose == purpose ? Color.accentColor : Color.gray.opacity(0.2))
                                    .foregroundColor(cardPurpose == purpose ? .white : .primary)
                                    .clipShape(Capsule())
                                    .onTapGesture {
                                        cardPurpose = purpose
                                    }
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
                    
                    HStack {
                        Text("cvv_code".localized)
                        Spacer()
                        TextField("123", text: $cvv)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("card_requisites".localized)
                }
                
                Section {
                    HStack(spacing: 16) {
                        ForEach(0..<themes.count, id: \.self) { index in
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: themes[index].gradient.map { Color(hex: $0) },
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if selectedThemeIndex == index {
                                        Circle()
                                            .stroke(Color.white, lineWidth: 3)
                                            .shadow(radius: 4)
                                    }
                                }
                                .scaleEffect(selectedThemeIndex == index ? 1.1 : 1.0)
                                .onTapGesture {
                                    HapticManager.shared.impact(.light)
                                    withAnimation(.spring()) {
                                        selectedThemeIndex = index
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("card_color_theme".localized)
                }
            }
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
    
    private func saveCard() {
        guard let balance = Double(balanceString.replacingOccurrences(of: ",", with: ".")) else { return }
        let theme = themes[selectedThemeIndex]
        let card = Card(
            number: formattedCardNumber.isEmpty ? "5244 8721 9012 7642" : formattedCardNumber,
            holderName: holderName.isEmpty ? "SAMVEL USER" : holderName,
            balance: balance,
            type: cardPurpose,
            colorHex: theme.colorHex,
            gradientColors: theme.gradient,
            isFrozen: false,
            expiryDate: expiryDate.isEmpty ? "08/29" : expiryDate,
            cvv: cvv.isEmpty ? "123" : cvv
        )
        financeService.addCard(card)
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
    @State private var selectedColorIndex = 0
    
    let colorOptions = [
        (colorHex: "#FFD200", gradient: ["#FFE259", "#FFA751"]),
        (colorHex: "#00F2FE", gradient: ["#00F2FE", "#4FACFE"]),
        (colorHex: "#FF2D55", gradient: ["#FF2D55", "#FF5E62"]),
        (colorHex: "#AF52DE", gradient: ["#AF52DE", "#D100F3"])
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(card.type) (•••• \(String(card.number.suffix(4))))")
                        .font(.subheadline.bold())
                        .foregroundColor(.gray)
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
                
                Section {
                    HStack(spacing: 16) {
                        ForEach(0..<colorOptions.count, id: \.self) { index in
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: colorOptions[index].gradient.map { Color(hex: $0) },
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if selectedColorIndex == index {
                                        Circle()
                                            .stroke(Color.white, lineWidth: 3)
                                            .shadow(radius: 4)
                                    }
                                }
                                .scaleEffect(selectedColorIndex == index ? 1.1 : 1.0)
                                .onTapGesture {
                                    HapticManager.shared.impact(.light)
                                    withAnimation(.spring()) {
                                        selectedColorIndex = index
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("card_color_theme".localized)
                }
            }
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
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Double(targetAmountString.replacingOccurrences(of: ",", with: ".")) ?? 0 <= 0)
                }
            }
        }
    }
    
    private func saveGoal() {
        guard let targetAmount = Double(targetAmountString.replacingOccurrences(of: ",", with: ".")) else { return }
        let option = colorOptions[selectedColorIndex]
        let goal = Goal(
            cardId: card.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            targetAmount: targetAmount,
            currentAmount: 0.0,
            colorHex: option.colorHex,
            gradientColors: option.gradient
        )
        financeService.addGoal(goal)
        HapticManager.shared.trigger(.success)
        dismiss()
    }
}

/// Модальный экран просмотра полного 16-значного номера и реквизитов карты
struct CardDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let card: Card
    @State private var isCopied = false
    
    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
            
            Text("card_details".localized)
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 16) {
                detailRow(title: "card_purpose".localized, value: card.type)
                detailRow(title: "card_holder".localized, value: card.holderName)
                detailRow(title: "full_card_number".localized, value: card.number)
                detailRow(title: "expiry_date".localized, value: card.expiryDate)
                detailRow(title: "cvv_code".localized, value: card.cvv)
                detailRow(title: "Статус", value: card.isFrozen ? "freeze".localized : "Активна")
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
            
            Button {
                UIPasteboard.general.string = card.number.replacingOccurrences(of: " ", with: "")
                HapticManager.shared.trigger(.success)
                withAnimation {
                    isCopied = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    isCopied = false
                }
            } label: {
                HStack {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    Text(isCopied ? "copied".localized : "copy_number".localized)
                }
                .fontWeight(.bold)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding()
                .background(isCopied ? Color.green : Color.white)
                .cornerRadius(12)
            }
            
            Spacer()
        }
        .padding(.horizontal, 24)
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
    
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
    }
}
