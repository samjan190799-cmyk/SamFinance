import SwiftUI
import Charts

/// Главный экран приложения с дизайном по макету 2.
/// Все элементы (баланс, карты, spending, транзакции) скроллируются в единой ленте,
/// что гарантирует идеальное отображение на любых экранах iPhone (включая iPhone 15 Pro и SE)
/// и предотвращает сжатие списка транзакций.
struct DashboardView: View {
    let financeService: FinanceService
    @Binding var selectedTab: Int
    @State private var isShowingAddSheet = false
    
    /// Определение компактных экранов для динамической адаптации верстки
    private var isSmallScreen: Bool {
        UIScreen.main.bounds.height < 750
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: "#0E0F12") // Глубокий темный фон
                .ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Шапка (Профиль и уведомления)
                    headerView
                        .padding(.horizontal, 24)
                        .padding(.top, isSmallScreen ? 12 : 20)
                    
                    // Сводка баланса и выглядывающие карты справа
                    HStack(alignment: .center, spacing: 0) {
                        balanceSection
                        
                        Spacer()
                        
                        miniCardsStack
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, isSmallScreen ? 12 : 20)
                    
                    // Блок расходов Spending
                    spendingSection
                        .padding(.horizontal, 24)
                        .padding(.top, isSmallScreen ? 16 : 24)
                    
                    // Белая шторка с транзакциями (теперь плавно выкатывается снизу в общем скролле)
                    transactionsSection
                        .padding(.top, isSmallScreen ? 20 : 28)
                }
            }
            .ignoresSafeArea(edges: .bottom) // Позволяет скроллу и плашке уходить до низа экрана
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isShowingAddSheet) {
            AddTransactionView(financeService: financeService)
        }
    }
    
    // MARK: - Шапка
    private var headerView: some View {
        HStack {
            // Аватарка (круглая с градиентом)
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#FFE259"), Color(hex: "#FFA751")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: isSmallScreen ? 34 : 40, height: isSmallScreen ? 34 : 40)
                
                Image(systemName: "person.fill")
                    .foregroundColor(.white)
                    .font(.system(size: isSmallScreen ? 15 : 18))
            }
            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
            
            Spacer()
            
            // Колокольчик
            Button {
                HapticManager.shared.impact(.light)
            } label: {
                Image(systemName: "bell")
                    .font(.system(size: isSmallScreen ? 16 : 18))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: isSmallScreen ? 34 : 40, height: isSmallScreen ? 34 : 40)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
        }
    }
    
    // MARK: - Раздел баланса
    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: isSmallScreen ? 6 : 10) {
            Text("Total balance")
                .font(.system(size: isSmallScreen ? 12 : 14))
                .foregroundColor(.gray)
            
            // Форматированный баланс с мелкой дробной частью
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                let formatted = balanceFormatted
                Text(formatted.whole)
                    .font(.system(size: isSmallScreen ? 30 : 38, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(formatted.fraction)
                    .font(.system(size: isSmallScreen ? 18 : 22, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
            }
            
            // Кнопки Send и Request
            HStack(spacing: 8) {
                // Кнопка Send (белая)
                Button {
                    HapticManager.shared.trigger(.success)
                    isShowingAddSheet = true
                } label: {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(Color.black)
                                .frame(width: isSmallScreen ? 18 : 22, height: isSmallScreen ? 18 : 22)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: isSmallScreen ? 8 : 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Text("Send")
                            .font(.system(size: isSmallScreen ? 11 : 13, weight: .bold))
                            .foregroundColor(.black)
                    }
                    .padding(.horizontal, isSmallScreen ? 10 : 14)
                    .padding(.vertical, isSmallScreen ? 6 : 8)
                    .background(Color.white)
                    .clipShape(Capsule())
                }
                
                // Кнопка Request (темная)
                Button {
                    HapticManager.shared.impact(.light)
                } label: {
                    Text("Request")
                        .font(.system(size: isSmallScreen ? 11 : 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, isSmallScreen ? 12 : 16)
                        .padding(.vertical, isSmallScreen ? 6 : 8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
            }
        }
    }
    
    // MARK: - Стопка мини-карт справа
    private var miniCardsStack: some View {
        Button {
            HapticManager.shared.trigger(.success)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                selectedTab = 3 // Переключение на вкладку карт (теперь это вкладка 3)
            }
        } label: {
            ZStack {
                // Синяя карта (самая задняя)
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color(hex: "#00C6FF"), Color(hex: "#0072FF")], startPoint: .top, endPoint: .bottom))
                    .frame(width: isSmallScreen ? 38 : 46, height: isSmallScreen ? 64 : 78)
                    .offset(x: isSmallScreen ? 16 : 20, y: isSmallScreen ? 4 : 6)
                    .rotationEffect(.degrees(4))
                
                // Зеленая карта (средняя)
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color(hex: "#00F2FE"), Color(hex: "#4FACFE")], startPoint: .top, endPoint: .bottom))
                    .frame(width: isSmallScreen ? 38 : 46, height: isSmallScreen ? 64 : 78)
                    .offset(x: isSmallScreen ? 8 : 10, y: 0)
                    .rotationEffect(.degrees(-2))
                
                // Желтая карта (передняя)
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color(hex: "#FFE259"), Color(hex: "#FFA751")], startPoint: .top, endPoint: .bottom))
                    .frame(width: isSmallScreen ? 38 : 46, height: isSmallScreen ? 64 : 78)
                    .offset(x: 0, y: isSmallScreen ? -4 : -6)
                    .rotationEffect(.degrees(-6))
            }
            .frame(width: isSmallScreen ? 60 : 70, height: isSmallScreen ? 80 : 90)
            .offset(x: isSmallScreen ? 24 : 30) // Выдвигаем за правый край экрана
            .shadow(color: Color.black.opacity(0.35), radius: 6, x: -3, y: 3)
        }
    }
    
    // MARK: - Блок расходов Spending
    private var spendingSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Spending")
                    .font(.system(size: isSmallScreen ? 11 : 13))
                    .foregroundColor(.gray)
                
                Text(formatSpendingAmount(financeService.totalSpending))
                    .font(.system(size: isSmallScreen ? 18 : 20, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            // Наползающие друг на друга иконки брендов (если есть расходы)
            if financeService.transactions.filter({ $0.type == .expense }).isEmpty {
                Text("No spending yet")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            } else {
                HStack(spacing: -8) {
                    brandMiniIcon(name: "apple.logo", color: .white, bgColor: .black)
                    brandMiniIcon(name: "at", color: .white, bgColor: .black)
                    brandMiniIcon(name: "calendar", color: .white, bgColor: Color(hex: "#34C759"))
                    
                    Text("+2")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: isSmallScreen ? 24 : 28, height: isSmallScreen ? 24 : 28)
                        .background(Color(hex: "#1E1F22"))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color(hex: "#0E0F12"), lineWidth: 1.5))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isSmallScreen ? 10 : 16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        }
    }
    
    // MARK: - Шторка с транзакциями (интегрирована в общий скролл)
    private var transactionsSection: some View {
        VStack(spacing: 0) {
            // Заголовок шторки
            HStack {
                Button {
                    HapticManager.shared.impact(.light)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .foregroundColor(.black.opacity(0.6))
                        .font(.system(size: isSmallScreen ? 16 : 18))
                }
                
                Spacer()
                
                Text("Transactions")
                    .font(.system(size: isSmallScreen ? 15 : 17, weight: .bold))
                    .foregroundColor(.black)
                
                Spacer()
                
                Button {
                    HapticManager.shared.impact(.light)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.black.opacity(0.6))
                        .font(.system(size: isSmallScreen ? 16 : 18))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            // Список транзакций
            if financeService.transactions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.35))
                        .symbolRenderingMode(.hierarchical)
                    
                    Text("No transactions yet")
                        .font(.headline)
                        .foregroundColor(.black.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                VStack(spacing: isSmallScreen ? 14 : 18) {
                    ForEach(financeService.transactions) { transaction in
                        TransactionRowView(transaction: transaction)
                            .contextMenu {
                                Button(role: .destructive) {
                                    HapticManager.shared.trigger(.warning)
                                    withAnimation(.spring()) {
                                        financeService.deleteTransaction(transaction)
                                    }
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(.rect(topLeadingRadius: 32, topTrailingRadius: 32))
        .padding(.bottom, isSmallScreen ? 80 : 100) // Отступ снизу для плавающего таб-бара
    }
    
    // MARK: - Вспомогательные методы
    
    private func brandMiniIcon(name: String, color: Color, bgColor: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: isSmallScreen ? 9 : 11, weight: .bold))
            .foregroundColor(color)
            .frame(width: isSmallScreen ? 24 : 28, height: isSmallScreen ? 24 : 28)
            .background(bgColor)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color(hex: "#0E0F12"), lineWidth: 1.5))
    }
    
    private var balanceFormatted: (whole: String, fraction: String) {
        let balance = financeService.totalBalance
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        
        let components = formatter.string(from: NSNumber(value: balance))?.components(separatedBy: ".") ?? ["$0", "00"]
        if components.count == 2 {
            return (components[0], "." + components[1])
        }
        return (components[0], ".00")
    }
    
    private func formatSpendingAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}
