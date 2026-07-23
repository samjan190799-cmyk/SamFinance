import SwiftUI

/// Экран управления банковскими картами пользователя с привязанными накопительными целями (копилочками).
struct CardsView: View {
    let financeService: FinanceService
    @State private var isShowingAddCardSheet = false
    @State private var selectedCardForDetails: Card? = nil
    @State private var selectedCardForNewGoal: Card? = nil
    
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
                            
                            Text("Цели карты (\(goals.count))")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: onAddGoal) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("Цель")
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
                            Text("К этой карте пока не привязано целей.")
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
                Text("$\(Int(goal.currentAmount)) / $\(Int(goal.targetAmount))")
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
                Label("Удалить цель", systemImage: "trash")
            }
        }
        .alert("Пополнить копилку \(goal.title)", isPresented: $isShowingDepositAlert) {
            TextField("Сумма ($)", text: $depositAmountString)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.type)
                        .font(.system(size: isSmallScreen ? 15 : 17, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Баланс: $\(Int(card.balance))")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                }
                
                Spacer()
                
                Text("•••• \(card.number)")
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

/// Модальный экран создания/выпуска новой карты с назначением
struct AddCardView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    
    @State private var cardPurpose: String = "Карта для подарков"
    @State private var holderName: String = "SAMVEL USER"
    @State private var balanceString: String = "1000"
    @State private var cardNumber: String = String(Int.random(in: 1000...9999))
    @State private var selectedThemeIndex = 0
    
    let defaultPurposes = [
        "Карта для подарков",
        "Карта для онлайн покупок",
        "Карта для путешествий",
        "Основная карта"
    ]
    
    let themes = [
        (colorHex: "#FF2D55", gradient: ["#FF2D55", "#FF5E62"]),
        (colorHex: "#00F2FE", gradient: ["#00F2FE", "#4FACFE"]),
        (colorHex: "#AF52DE", gradient: ["#AF52DE", "#7A00FF"]),
        (colorHex: "#34C759", gradient: ["#34C759", "#11998E"])
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Назначение карты (напр. Карта для подарков)", text: $cardPurpose)
                    
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
                    Text("Назначение карты")
                }
                
                Section {
                    TextField("Владелец карты", text: $holderName)
                        .textInputAutocapitalization(.characters)
                    
                    HStack {
                        Text("Базовый баланс ($)")
                        Spacer()
                        TextField("0", text: $balanceString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Последние 4 цифры")
                        Spacer()
                        TextField("7642", text: $cardNumber)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Реквизиты")
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
                    Text("Цветовая гамма карты")
                }
            }
            .navigationTitle("Новая карта")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        saveCard()
                    }
                    .disabled(cardPurpose.isEmpty || balanceString.isEmpty)
                }
            }
        }
    }
    
    private func saveCard() {
        guard let balance = Double(balanceString.replacingOccurrences(of: ",", with: ".")) else { return }
        let theme = themes[selectedThemeIndex]
        let card = Card(
            number: cardNumber.isEmpty ? "7642" : cardNumber,
            holderName: holderName.isEmpty ? "SAMVEL USER" : holderName,
            balance: balance,
            type: cardPurpose,
            colorHex: theme.colorHex,
            gradientColors: theme.gradient,
            isFrozen: false
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
                    Text("Карта: \(card.type) (•••• \(card.number))")
                        .font(.subheadline.bold())
                        .foregroundColor(.gray)
                } header: {
                    Text("Привязка")
                }
                
                Section {
                    TextField("Название цели (напр., На наушники)", text: $title)
                    
                    HStack {
                        Text("Целевая сумма ($)")
                        Spacer()
                        TextField("0", text: $targetAmountString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Детали копилки")
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
                    Text("Цветовая гамма цели")
                }
            }
            .navigationTitle("Новая цель карты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
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

/// Модальный экран просмотра реквизитов карты
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
                detailRow(title: "Назначение карты", value: card.type)
                detailRow(title: "Владелец", value: card.holderName)
                detailRow(title: "Номер карты", value: "5244 8721 9012 \(card.number)")
                detailRow(title: "Срок действия", value: "08/29")
                detailRow(title: "CVV код", value: "•••")
                detailRow(title: "Статус", value: card.isFrozen ? "Заморожена" : "Активна")
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
            
            Button {
                UIPasteboard.general.string = "524487219012\(card.number)"
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
