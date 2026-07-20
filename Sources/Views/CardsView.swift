import SwiftUI

/// Экран управления банковскими картами пользователя с неоновым свечением и стеклянными кнопками управления.
/// Без лишнего пространства сверху и с фоном, уходящим до самого низа.
struct CardsView: View {
    let financeService: FinanceService
    
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
                    .padding(.top, isSmallScreen ? 12 : 20)
                    .padding(.bottom, isSmallScreen ? 16 : 24)
                
                // Список карт
                ScrollView {
                    VStack(spacing: isSmallScreen ? 16 : 24) {
                        ForEach(financeService.cards) { card in
                            CardItemView(card: card, financeService: financeService)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, isSmallScreen ? 90 : 110) // Сдвиг под плавающий таб-бар
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .preferredColorScheme(.dark)
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
            } label: {
                Text("Order a card")
                    .font(.system(size: isSmallScreen ? 11 : 13, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, isSmallScreen ? 12 : 16)
                    .padding(.vertical, isSmallScreen ? 6 : 8)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
        }
    }
}

/// Визуальное представление банковской карты с поддержкой градиентов, неонового свечения и эффекта заморозки.
struct CardItemView: View {
    let card: Card
    let financeService: FinanceService
    
    private var isSmallScreen: Bool {
        UIScreen.main.bounds.height < 750
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Верхняя часть (Тип карты и последние цифры)
            HStack {
                Text(card.type)
                    .font(.system(size: isSmallScreen ? 14 : 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                
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
                    
                    // Кнопка показа реквизитов (иконка карты с цифрами)
                    CardActionButton(iconName: "creditcard") {
                        HapticManager.shared.impact(.light)
                    }
                    
                    // Кнопка настроек
                    CardActionButton(iconName: "gearshape") {
                        HapticManager.shared.impact(.light)
                    }
                }
                
                Spacer()
                
                // Логотип MasterCard
                MasterCardLogoView()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, isSmallScreen ? 18 : 24)
        }
        .frame(height: isSmallScreen ? 150 : 180) // Адаптивная высота карты
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
        // Неоновое свечение (тень с цветом карты)
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

/// Имитация логотипа MasterCard из двух кругов
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
