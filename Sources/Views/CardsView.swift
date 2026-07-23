import SwiftUI

/// Экран управления банковскими картами пользователя с неоновым свечением и стеклянными кнопками управления.
struct CardsView: View {
    let financeService: FinanceService
    @State private var isShowingAddCardSheet = false
    @State private var selectedCardForDetails: Card? = nil
    
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
                
                // Список карт
                if financeService.cards.isEmpty {
                    emptyCardsPlaceholder
                } else {
                    ScrollView {
                        VStack(spacing: isSmallScreen ? 16 : 24) {
                            ForEach(financeService.cards) { card in
                                CardItemView(
                                    card: card,
                                    financeService: financeService,
                                    onShowDetails: {
                                        selectedCardForDetails = card
                                    }
                                )
                                .contextMenu {
                                    Button {
                                        financeService.toggleFreezeCard(id: card.id)
                                    } label: {
                                        Label(
                                            card.isFrozen ? "Разморозить" : "Заморозить",
                                            systemImage: card.isFrozen ? "snowflake.circle.fill" : "snowflake"
                                        )
                                    }
                                    
                                    Button(role: .destructive) {
                                        HapticManager.shared.trigger(.warning)
                                        withAnimation(.spring()) {
                                            financeService.deleteCard(id: card.id)
                                        }
                                    } label: {
                                        Label("Удалить карту", systemImage: "trash")
                                    }
                                }
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
    }
    
    // MARK: - Шапка
    private var headerView: some View {
        HStack {
            Text("Cards")
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
                    Text("Order a card")
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
            
            Text("Нет подключенных карт")
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))
            
            Text("Выпустите или добавьте вашу первую банковскую карту для управления счетом.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                HapticManager.shared.trigger(.success)
                isShowingAddCardSheet = true
            } label: {
                Text("Добавить карту")
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
            // Верхняя часть (Тип карты, баланс и последние цифры)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.type)
                        .font(.system(size: isSmallScreen ? 14 : 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                    
                    Text("Баланс: $\(Int(card.balance))")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                Text("•••• \(card.number)")
                    .font(.system(size: isSmallScreen ? 14 : 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 24)
            .padding(.top, isSmallScreen ? 18 : 24)
            
            Spacer()
            
            // Нижняя часть (Управляющие кнопки и логотип платежной системы)
            HStack(alignment: .bottom) {
                HStack(spacing: 10) {
                    // Кнопка заморозки
                    CardActionButton(iconName: card.isFrozen ? "snowflake.circle.fill" : "snowflake") {
                        HapticManager.shared.trigger(.success)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            financeService.toggleFreezeCard(id: card.id)
                        }
                    }
                    .foregroundColor(card.isFrozen ? .blue : .white)
                    
                    // Кнопка показа реквизитов
                    CardActionButton(iconName: "creditcard") {
                        HapticManager.shared.impact(.light)
                        onShowDetails()
                    }
                }
                
                Spacer()
                
                MasterCardLogoView()
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

/// Логотип MasterCard из двух полупрозрачных кругов
struct MasterCardLogoView: View {
    var body: some View {
        HStack(spacing: -10) {
            Circle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 28, height: 28)
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 28, height: 28)
        }
    }
}

/// Модальный экран создания/выпуска новой карты
struct AddCardView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    
    @State private var cardName: String = "Digital card"
    @State private var holderName: String = "SAMVEL USER"
    @State private var balanceString: String = "1000"
    @State private var cardNumber: String = String(Int.random(in: 1000...9999))
    @State private var selectedThemeIndex = 0
    
    let themes = [
        (colorHex: "#FF2D55", gradient: ["#FF2D55", "#FF5E62"]), // Неоновый красный
        (colorHex: "#00F2FE", gradient: ["#00F2FE", "#4FACFE"]), // Неоновый синий
        (colorHex: "#AF52DE", gradient: ["#AF52DE", "#7A00FF"]), // Фиолетовый
        (colorHex: "#34C759", gradient: ["#34C759", "#11998E"])  // Изумрудный
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название карты", text: $cardName)
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
                    Text("Параметры карты")
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
                    Text("Дизайн и цвет карты")
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
                    .disabled(cardName.isEmpty || balanceString.isEmpty)
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
            type: cardName,
            colorHex: theme.colorHex,
            gradientColors: theme.gradient,
            isFrozen: false
        )
        financeService.addCard(card)
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
            
            Text("Реквизиты карты")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 16) {
                detailRow(title: "Тип карты", value: card.type)
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
                    Text(isCopied ? "Номер скопирован!" : "Скопировать номер")
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
