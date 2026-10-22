import SwiftUI

/// Вкладка нижней панели
private struct MonoTab: Identifiable {
    let index: Int
    let title: String
    let icon: String

    var id: Int { index }
}

/// Главный контейнер приложения. Три вкладки (Долги, Обзор, Карты) в плавающей панели
/// и отдельная кнопка «+» для новой операции.
struct ContentView: View {
    @State private var financeService = FinanceService.shared
    @State private var languageManager = LanguageManager.shared
    @State private var selectedTab = 1 // По умолчанию открыт главный экран (индекс 1)
    @State private var isShowingAddSheet = false

    private let tabs: [MonoTab] = [
        MonoTab(index: 0, title: "Долги", icon: "person.2"),
        MonoTab(index: 1, title: "Обзор", icon: "house"),
        MonoTab(index: 2, title: "Карты", icon: "creditcard")
    ]

    var body: some View {
        tabContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .monoScreen()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
            .sheet(isPresented: $isShowingAddSheet) {
                AddTransactionView(financeService: financeService)
            }
    }

    // MARK: - Содержимое выбранной вкладки
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0:
            DebtsView(financeService: financeService)
        case 2:
            CardsView(financeService: financeService)
        default:
            DashboardView(financeService: financeService)
        }
    }

    // MARK: - Нижняя панель
    private var bottomBar: some View {
        HStack(spacing: 12) {
            tabPill
            addButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var tabPill: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                tabButton(tab)
            }
        }
        .padding(6)
        .frame(height: 64)
        .background(Theme.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
    }

    private func tabButton(_ tab: MonoTab) -> some View {
        let isSelected = selectedTab == tab.index
        return Button {
            if selectedTab != tab.index {
                HapticManager.shared.selection()
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = tab.index
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "\(tab.icon).fill" : tab.icon)
                    .font(.system(size: 20, weight: .regular))
                if isSelected {
                    Text(tab.title)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundColor(isSelected ? .white : Theme.textTertiary)
            .frame(maxWidth: isSelected ? .infinity : 64, maxHeight: .infinity)
            .background(isSelected ? Theme.line : Color.clear)
            .clipShape(Capsule())
        }
        .accessibilityLabel(tab.title)
    }

    private var addButton: some View {
        Button {
            HapticManager.shared.impact(.light)
            isShowingAddSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.black)
                .frame(width: 64, height: 64)
                .background(Color.white)
                .clipShape(Circle())
        }
        .accessibilityLabel("Новая операция")
    }
}
