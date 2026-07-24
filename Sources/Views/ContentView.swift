import SwiftUI

/// Главный контейнер приложения. Управляет плавающим стеклянным таб-баром 2026 (Долги, Главная, Карты).
/// Растянут на весь физический экран (ignoresSafeArea) для премиального визуального отображения.
struct ContentView: View {
    @State private var financeService = FinanceService.shared
    @State private var languageManager = LanguageManager.shared
    @State private var selectedTab = 1 // По умолчанию открыт главный экран (индекс 1)
    
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
                        .transition(.opacity)
                case 1:
                    DashboardView(financeService: financeService, selectedTab: $selectedTab)
                        .transition(.opacity)
                case 2:
                    CardsView(financeService: financeService)
                        .transition(.opacity)
                default:
                    DashboardView(financeService: financeService, selectedTab: $selectedTab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            
            // Кастомный плавающий стеклянный таб-бар Aether Glass 2026
            customFloatingTabBar
                .padding(.bottom, isSmallScreen ? 14 : 32)
        }
        .background(Color(hex: "#090A0E"))
        .ignoresSafeArea()
    }
    
    // MARK: - Панель таб-бара (Floating Glass Tab Bar)
    private var customFloatingTabBar: some View {
        HStack(spacing: 6) {
            tabButton(index: 0, title: "Долги", activeIcon: "person.2.fill", inactiveIcon: "person.2")
            tabButton(index: 1, title: "Обзор", activeIcon: "house.fill", inactiveIcon: "house")
            tabButton(index: 2, title: "Карты", activeIcon: "creditcard.fill", inactiveIcon: "creditcard")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            ZStack {
                Capsule()
                    .fill(Color(hex: "#12141C").opacity(0.85))
                Capsule()
                    .fill(Color.white.opacity(0.04))
            }
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.55), radius: 20, x: 0, y: 12)
        .shadow(color: Color(hex: "#00F2FE").opacity(0.12), radius: 15, x: 0, y: 4)
    }
    
    // MARK: - Кнопка вкладки
    private func tabButton(index: Int, title: String, activeIcon: String, inactiveIcon: String) -> some View {
        let isSelected = selectedTab == index
        return Button {
            if selectedTab != index {
                HapticManager.shared.selection()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                    selectedTab = index
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? activeIcon : inactiveIcon)
                    .font(.system(size: isSmallScreen ? 15 : 17, weight: .bold))
                    .foregroundColor(isSelected ? .black : .white.opacity(0.5))
                
                if isSelected {
                    Text(title)
                        .font(.system(size: isSmallScreen ? 12 : 13, weight: .bold))
                        .foregroundColor(.black)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .padding(.horizontal, isSelected ? (isSmallScreen ? 14 : 18) : (isSmallScreen ? 12 : 14))
            .padding(.vertical, isSmallScreen ? 8 : 10)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white, Color(hex: "#E2E8F0")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color.white.opacity(0.4), radius: 8, x: 0, y: 2)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}
