import SwiftUI

/// Экран управления банковскими картами пользователя с неоновым свечением и стеклянными кнопками управления.
struct CardsView: View {
    let financeService: FinanceService
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ForEach(financeService.cards) { card in
                        CardItemView(card: card, financeService: financeService)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)
            }
            .background(Color(hex: "#0E0F12")) // Темный глубокий фон из дизайна
            .preferredColorScheme(.dark)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Cards")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticManager.shared.trigger(.success)
                    } label: {
                        Text("Order a card")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

/// Визуальное представление банковской карты с поддержкой градиентов, неонового свечения и эффекта заморозки.
struct CardItemView: View {
    let card: Card
    let financeService: FinanceService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Верхняя часть (Тип карты и последние цифры)
            HStack {
                Text(card.type)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                
                Spacer()
                
                Text("•••• \(card.number)")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            Spacer()
            
            // Нижняя часть (Управляющие кнопки и логотип платежной системы)
            HStack(alignment: .bottom) {
                HStack(spacing: 12) {
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
                
                // Логотип MasterCard (в макете он представлен перекрывающимися серыми полупрозрачными кругами)
                MasterCardLogoView()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(height: 180)
        .background {
            RoundedRectangle(cornerRadius: 24)
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
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.blue.opacity(0.35), lineWidth: 2)
            }
        }
        // Неоновое свечение (тень с цветом карты)
        .shadow(color: Color(hex: card.colorHex).opacity(card.isFrozen ? 0.12 : 0.38), radius: 18, x: 0, y: 10)
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
