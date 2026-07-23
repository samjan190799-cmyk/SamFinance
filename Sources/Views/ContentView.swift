import SwiftUI

/// Главный контейнер приложения. Управляет плавающим таб-баром Floating Tab Bar (Долги, Главная, Карты и Копилки).
/// Растянут на весь физический экран (ignoresSafeArea) для премиального отображения.
struct ContentView: View {
    @State private var financeService = FinanceService.shared
    @State private var languageManager = LanguageManager.shared
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
            .ignoresSafeArea()
            
            // Кастомный плавающий таб-бар
            customTabBar
                .padding(.bottom, isSmallScreen ? 12 : 30)
        }
        .background(Color(hex: "#0E0F12"))
        .ignoresSafeArea()
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
            
            // Таб 2: Карты & Копилки
            tabButton(index: 2, activeIcon: "creditcard.fill", inactiveIcon: "creditcard")
        }
        .padding(.horizontal, 16)
        .frame(width: isSmallScreen ? 200 : 240, height: isSmallScreen ? 52 : 58)
        .background(Color(hex: "#17181A"))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.45), radius: 15, x: 0, y: 8)
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
                    Capsule()
                        .fill(Color.white)
                        .frame(width: isSmallScreen ? 44 : 50, height: isSmallScreen ? 34 : 40)
                        .transition(.scale.combined(with: .opacity))
                }
                
                Image(systemName: isSelected ? activeIcon : inactiveIcon)
                    .font(.system(size: isSmallScreen ? 16 : 18, weight: .bold))
                    .foregroundColor(isSelected ? .black : .white.opacity(0.4))
            }
            .frame(width: isSmallScreen ? 52 : 60, height: isSmallScreen ? 42 : 48)
        }
    }
}
