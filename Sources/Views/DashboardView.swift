import SwiftUI
import Charts

/// Главный экран приложения с дизайном по макету 2 (баланс, выглядывающие карты справа, расходы и белая шторка транзакций).
struct DashboardView: View {
    let financeService: FinanceService
    @Binding var selectedTab: Int
    @State private var isShowingAddSheet = false
    
    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: "#0E0F12") // Глубокий темный фон из макета
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Шапка (Профиль и уведомления)
                headerView
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                
                // Сводка баланса и выглядывающие карты справа
                HStack(alignment: .center, spacing: 0) {
                    balanceSection
                    
                    Spacer()
                    
                    miniCardsStack
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                
                // Блок расходов Spending
                spendingSection
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                
                // Белая шторка с транзакциями
                transactionsBottomSheet
            }
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
                    .frame(width: 40, height: 40)
                
                Image(systemName: "person.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 18))
            }
            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
            
            Spacer()
            
            // Колокольчик
            Button {
                HapticManager.shared.impact(.light)
            } label: {
                Image(systemName: "bell")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
        }
    }
    
    // MARK: - Раздел баланса
    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Total balance")
                .font(.system(size: 14))
                .foregroundColor(.gray)
            
            // Форматированный баланс с мелкой дробной частью
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                let formatted = balanceFormatted
                Text(formatted.whole)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(formatted.fraction)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
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
                                .frame(width: 22, height: 22)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Text("Send")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.black)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .clipShape(Capsule())
                }
                
                // Кнопка Request (темная)
                Button {
                    HapticManager.shared.impact(.light)
                } label: {
                    Text("Request")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
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
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                selectedTab = 2 // Переключение на вкладку карт
            }
        } label: {
            ZStack {
                // Синяя карта (самая задняя)
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color(hex: "#00C6FF"), Color(hex: "#0072FF")], startPoint: .top, endPoint: .bottom))
                    .frame(width: 46, height: 78)
                    .offset(x: 20, y: 6)
                    .rotationEffect(.degrees(4))
                
                // Зеленая карта (средняя)
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color(hex: "#00F2FE"), Color(hex: "#4FACFE")], startPoint: .top, endPoint: .bottom))
                    .frame(width: 46, height: 78)
                    .offset(x: 10, y: 0)
                    .rotationEffect(.degrees(-2))
                
                // Желтая карта (передняя)
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color(hex: "#FFE259"), Color(hex: "#FFA751")], startPoint: .top, endPoint: .bottom))
                    .frame(width: 46, height: 78)
                    .offset(x: 0, y: -6)
                    .rotationEffect(.degrees(-6))
            }
            .frame(width: 70, height: 90)
            .offset(x: 30) // Выдвигаем за правый край экрана
            .shadow(color: Color.black.opacity(0.4), radius: 8, x: -4, y: 4)
        }
    }
    
    // MARK: - Блок Spending (Расходы)
    private var spendingSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Spending")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                
                Text(formatSpendingAmount(financeService.totalSpending))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            // Наползающие друг на друга иконки брендов из дизайна
            HStack(spacing: -10) {
                brandMiniIcon(name: "apple.logo", color: .white, bgColor: .black)
                brandMiniIcon(name: "at", color: .white, bgColor: .black)
                brandMiniIcon(name: "calendar", color: .white, bgColor: Color(hex: "#34C759"))
                
                // Счетчик
                Text("+2")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color(hex: "#1E1F22"))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(hex: "#0E0F12"), lineWidth: 1.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(20)
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        }
    }
    
    // MARK: - Белая шторка с транзакциями
    private var transactionsBottomSheet: some View {
        VStack(spacing: 0) {
            // Заголовок шторки
            HStack {
                Button {
                    HapticManager.shared.impact(.light)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .foregroundColor(.black.opacity(0.6))
                        .font(.title3)
                }
                
                Spacer()
                
                Text("Transactions")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.black)
                
                Spacer()
                
                Button {
                    HapticManager.shared.impact(.light)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.black.opacity(0.6))
                        .font(.title3)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            // Список транзакций
            ScrollView {
                VStack(spacing: 18) {
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
                .padding(.top, 8)
                .padding(.bottom, 110) // Сдвиг под плавающий таб-бар
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .clipShape(.rect(topLeadingRadius: 32, topTrailingRadius: 32))
        .ignoresSafeArea(edges: .bottom)
    }
    
    // MARK: - Вспомогательные методы
    
    private func brandMiniIcon(name: String, color: Color, bgColor: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(color)
            .frame(width: 28, height: 28)
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
        
        guard let formattedString = formatter.string(from: NSNumber(value: balance)) else {
            return ("$0", ".00")
        }
        
        let components = formattedString.components(separatedBy: ".")
        if components.count == 2 {
            return (components[0], "." + components[1])
        }
        return (formattedString, "")
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

/// Строка транзакции на белой шторке
struct TransactionRowView: View {
    let transaction: Transaction
    
    var body: some View {
        HStack(spacing: 16) {
            // Иконка бренда с цветной точкой в правом нижнем углу
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(transaction.type == .income ? Color.green.opacity(0.12) : Color.black.opacity(0.05))
                    .frame(width: 44, height: 44)
                
                Image(systemName: transaction.brandIcon ?? transaction.category.icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(transaction.type == .income ? .green : .black)
                
                // Цветная точка бренда
                if let colorHex = transaction.brandColorHex {
                    Circle()
                        .fill(Color(hex: colorHex))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                }
            }
            
            // Название бренда и категория
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.brandName ?? transaction.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.black)
                
                Text(transaction.category.name)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Сумма
            Text(transaction.type == .income ? "+\(formatAmount(transaction.amount)) $" : "-\(formatAmount(transaction.amount)) $")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(transaction.type == .income ? .green : .black)
        }
    }
    
    private func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
