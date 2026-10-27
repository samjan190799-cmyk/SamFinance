import Combine
import SwiftUI

/// Разделы нижней панели
enum AppTab: Int, CaseIterable, Identifiable, Hashable {
    case overview
    case cards
    case assistant
    case debts
    case report

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .overview: return String(localized: "Обзор")
        case .cards: return String(localized: "Карты")
        case .assistant: return String(localized: "ИИ")
        case .debts: return String(localized: "Долги")
        case .report: return "tab_report".localized
        }
    }

    var icon: String {
        switch self {
        case .overview: return "house"
        case .cards: return "creditcard"
        case .assistant: return "sparkles"
        case .debts: return "person.2"
        case .report: return "chart.bar"
        }
    }

    /// Иконка активной вкладки
    var selectedIcon: String {
        switch self {
        case .assistant: return "sparkles"
        default: return "\(icon).fill"
        }
    }
}

/// Главный контейнер приложения: пять разделов в нижней панели, ИИ — один из них.
struct ContentView: View {
    @State private var financeService = FinanceService.shared
    @State private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .overview
    /// Пока открыта клавиатура, панель прячется, чтобы поле ввода чата стояло прямо над клавиатурой
    @State private var isKeyboardVisible = false
    /// Сколько раз выбирали каждую вкладку: по изменению подпрыгивает только её иконка
    @State private var tabBounces: [AppTab: Int] = [:]
    @Namespace private var tabNamespace

    var body: some View {
        tabContent
            .id(selectedTab)
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .monoScreen()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isKeyboardVisible {
                    tabBar
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
            .task {
                // Курсы валют обновляются сами при каждом запуске
                CurrencyService.shared.fetchLatestRates()
            }
            // Нажатие на напоминание открывает его раздел: долги, карты с копилками или обзор
            .onAppear {
                openRequestedTab()
            }
            .onChange(of: router.requestedTab) {
                openRequestedTab()
            }
            .onChange(of: scenePhase) { _, phase in
                // Вечерние напоминания ставятся на две недели вперёд: при каждом возвращении в приложение окно сдвигается
                if phase == .active {
                    ReminderService.shared.update(from: financeService)
                }
            }
            .screenshotScene(selectedTab: $selectedTab, financeService: financeService)
    }

    // MARK: - Содержимое выбранного раздела
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            DashboardView(financeService: financeService) {
                switchTo(.report)
            }
        case .cards:
            CardsView(financeService: financeService)
        case .assistant:
            AIChatView(financeService: financeService)
        case .debts:
            DebtsView(financeService: financeService)
        case .report:
            ReportView(financeService: financeService)
        }
    }

    private func openRequestedTab() {
        guard let tab = router.requestedTab else { return }
        router.requestedTab = nil
        switchTo(tab)
    }

    private func switchTo(_ tab: AppTab) {
        guard selectedTab != tab else { return }
        HapticManager.shared.selection()
        tabBounces[tab, default: 0] += 1
        withAnimation(Motion.spring) {
            selectedTab = tab
        }
    }

    // MARK: - Нижняя панель
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .background(
            Theme.tabBar
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { MonoDivider() }
        )
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            switchTo(tab)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .symbolEffect(.bounce, value: tabBounces[tab, default: 0])
                Text(tab.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(isSelected ? Theme.accent : Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                // Подложка перетекает от прежней вкладки к новой
                if isSelected {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Theme.accent.opacity(0.12))
                        .matchedGeometryEffect(id: "selectedTab", in: tabNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.9))
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
