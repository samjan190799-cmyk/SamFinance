import SwiftUI

/// Главный контейнер приложения. Управляет кастомным Floating Tab Bar (плавающей пилюлей)
/// и переключением экранов (Долги, Главная, Карты). Адаптирован под все типы экранов.
struct ContentView: View {
    @State private var financeService = FinanceService()
    @State private var selectedTab = 1 // По умолчанию открыт главный экран (индекс 1)
    
    /// Определение компактных экранов для динамической адаптации верстки
    private var isSmallScreen: Bool {
        UIScreen.main.bounds.height < 750
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Контент выбранной вкладки
            ZStack {
                switch selectedTab {
                case 0:
                    DebtsView(financeService: financeService)
                case 1:
                    DashboardView(financeService: financeService, selectedTab: $selectedTab)
                case 2:
                    CardsView(financeService: financeService)
                default:
                    DashboardView(financeService: financeService, selectedTab: $selectedTab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Кастомный плавающий таб-бар
            customTabBar
                .padding(.bottom, isSmallScreen ? 12 : 24) // Адаптивный отступ снизу
        }
        .background(Color(hex: "#0E0F12")) // Темный фон на уровне всего контейнера
        .ignoresSafeArea(edges: .bottom)
    }
    
    // MARK: - Панель таб-бара (Floating Tab Bar)
    private var customTabBar: some View {
        HStack(spacing: 0) {
            // Таб 0: Долги
            tabButton(index: 0, activeIcon: "person.2.fill", inactiveIcon: "person.2")
            
            Spacer()
            
            // Таб 1: Главная
            tabButton(index: 1, activeIcon: "house.fill", inactiveIcon: "house")
            
            Spacer()
            
            // Таб 2: Карты
            tabButton(index: 2, activeIcon: "creditcard.fill", inactiveIcon: "creditcard")
        }
        .padding(.horizontal, 8)
        .frame(width: isSmallScreen ? 200 : 220, height: isSmallScreen ? 52 : 58) // Компактный размер на iPhone SE
        .background(Color(hex: "#17181A")) // Темно-серый матовый фон
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
    }
    
    // MARK: - Кнопка вкладки
    private func tabButton(index: Int, activeIcon: String, inactiveIcon: String) -> some View {
        let isSelected = selectedTab == index
        return Button {
            if selectedTab != index {
                HapticManager.shared.selection()
                withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.76)) {
                    selectedTab = index
                }
            }
        } label: {
            ZStack {
                if isSelected {
                    // Белая подложка под активной иконкой
                    Capsule()
                        .fill(Color.white)
                        .frame(width: isSmallScreen ? 44 : 50, height: isSmallScreen ? 34 : 40)
                        .transition(.scale.combined(with: .opacity))
                }
                
                Image(systemName: isSelected ? activeIcon : inactiveIcon)
                    .font(.system(size: isSmallScreen ? 16 : 18, weight: .bold))
                    .foregroundColor(isSelected ? .black : .white.opacity(0.4))
            }
            .frame(width: isSmallScreen ? 54 : 60, height: isSmallScreen ? 42 : 48)
        }
    }
}
