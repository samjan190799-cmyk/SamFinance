import SwiftUI

/// Главный контейнер приложения. Управляет кастомным Floating Tab Bar (плавающей пилюлей)
/// и переключением экранов (Долги, Копилки, Главная, Карты).
/// Растянут на весь физический экран (ignoresSafeArea) для премиального отображения.
struct ContentView: View {
    @State private var financeService = FinanceService()
    @State private var selectedTab = 2 // По умолчанию открыт главный экран (индекс 2)
    
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
                    GoalsView(financeService: financeService)
                case 2:
                    DashboardView(financeService: financeService, selectedTab: $selectedTab)
                case 3:
                    CardsView(financeService: financeService)
                default:
                    DashboardView(financeService: financeService, selectedTab: $selectedTab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea() // Растягиваем контент на весь экран под границы устройства
            
            // Кастомный плавающий таб-бар
            customTabBar
                .padding(.bottom, isSmallScreen ? 12 : 30) // Адаптивный отступ снизу для безрамочных моделей
        }
        .background(Color(hex: "#0E0F12")) // Темный фон на уровне всего контейнера
        .ignoresSafeArea() // Игнорируем безопасную зону для полной заливки
    }
    
    // MARK: - Панель таб-бара (Floating Tab Bar)
    private var customTabBar: some View {
        HStack(spacing: 0) {
            // Таб 0: Долги
            tabButton(index: 0, activeIcon: "person.2.fill", inactiveIcon: "person.2")
            
            Spacer()
            
            // Таб 1: Копилки
            tabButton(index: 1, activeIcon: "star.fill", inactiveIcon: "star")
            
            Spacer()
            
            // Таб 2: Главная
            tabButton(index: 2, activeIcon: "house.fill", inactiveIcon: "house")
            
            Spacer()
            
            // Таб 3: Карты
            tabButton(index: 3, activeIcon: "creditcard.fill", inactiveIcon: "creditcard")
        }
        .padding(.horizontal, 8)
        .frame(width: isSmallScreen ? 240 : 280, height: isSmallScreen ? 52 : 58) // Немного шире для размещения 4 кнопок
        .background(Color(hex: "#17181A")) // Темно-серый матовый фон
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
                    // Белая подложка под активной иконкой
                    Capsule()
                        .fill(Color.white)
                        .frame(width: isSmallScreen ? 42 : 48, height: isSmallScreen ? 34 : 40)
                        .transition(.scale.combined(with: .opacity))
                }
                
                Image(systemName: isSelected ? activeIcon : inactiveIcon)
                    .font(.system(size: isSmallScreen ? 15 : 17, weight: .bold))
                    .foregroundColor(isSelected ? .black : .white.opacity(0.4))
            }
            .frame(width: isSmallScreen ? 50 : 56, height: isSmallScreen ? 42 : 48)
        }
    }
}
